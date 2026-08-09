BEGIN;

CREATE OR REPLACE FUNCTION app.document_image_generate_derivative_token()
RETURNS text
LANGUAGE sql
VOLATILE
SET search_path = ''
AS $function$
  SELECT substring(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') from 1 for 43);
$function$;

CREATE OR REPLACE FUNCTION app.document_image_is_eligible(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app.documents d
    JOIN app.document_links dl ON dl.document_id = d.id
    WHERE d.id = p_document_id
      AND d.status = 'ACTIVE'
      AND d.mime_type IN ('image/jpeg','image/png','image/webp')
      AND (
        (
          d.document_type_code = 'PROGRESS_PHOTOGRAPH'
          AND (
            (dl.project_id IS NOT NULL AND EXISTS (SELECT 1 FROM app.projects p WHERE p.id = dl.project_id AND p.archived_at IS NULL))
            OR
            (dl.progress_update_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM app.progress_updates pu JOIN app.projects p ON p.id = pu.project_id
              WHERE pu.id = dl.progress_update_id AND pu.archived_at IS NULL AND p.archived_at IS NULL
            ))
          )
        )
        OR
        (
          d.document_type_code = 'TASK_ATTACHMENT'
          AND dl.task_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM app.tasks t JOIN app.projects p ON p.id = t.project_id
            WHERE t.id = dl.task_id AND t.is_active AND p.archived_at IS NULL
          )
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION app.document_image_client_parent_visible(p_document_id uuid, p_client_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT NOT EXISTS (
    SELECT 1
    FROM app.documents d
    JOIN app.document_links dl ON dl.document_id = d.id
    WHERE d.id = p_document_id
      AND d.document_type_code = 'PROGRESS_PHOTOGRAPH'
      AND dl.progress_update_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM app.progress_updates pu
        JOIN app.projects p ON p.id = pu.project_id
        WHERE pu.id = dl.progress_update_id
          AND p.client_id = p_client_id
          AND pu.status = 'APPROVED'
          AND pu.client_visible
          AND pu.published_at IS NOT NULL
          AND pu.archived_at IS NULL
          AND p.archived_at IS NULL
      )
  )
  AND NOT EXISTS (
    SELECT 1
    FROM app.documents d
    JOIN app.document_links dl ON dl.document_id = d.id
    WHERE d.id = p_document_id
      AND d.document_type_code = 'TASK_ATTACHMENT'
      AND dl.task_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM app.tasks t
        JOIN app.projects p ON p.id = t.project_id
        WHERE t.id = dl.task_id
          AND p.client_id = p_client_id
          AND t.is_active
          AND t.client_visible
          AND p.archived_at IS NULL
      )
  );
$function$;

CREATE OR REPLACE FUNCTION app.owner_prepare_document_image_processing(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  document_id uuid,
  storage_bucket text,
  storage_object_key text,
  mime_type text,
  source_file_size_bytes bigint,
  source_sha256_hash bytea,
  document_type_code text,
  processing_status app.document_image_processing_status,
  thumbnail_storage_object_key text,
  preview_storage_object_key text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  doc_row app.documents%ROWTYPE;
  upload_row app.document_uploads%ROWTYPE;
  derivative_row app.document_image_derivatives%ROWTYPE;
  derivative_token text;
  did_start boolean := false;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO doc_row FROM app.documents WHERE id = p_document_id FOR UPDATE;
  IF doc_row.id IS NULL OR doc_row.status <> 'ACTIVE' OR doc_row.storage_bucket <> 'documents-private' OR doc_row.storage_object_key !~ '^objects/' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Photograph processing is not available.';
  END IF;
  IF doc_row.mime_type NOT IN ('image/jpeg','image/png','image/webp') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'unsupported_mime';
  END IF;
  IF doc_row.file_size_bytes > 5242880 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'source_dimensions_exceeded';
  END IF;
  IF NOT app.document_image_is_eligible(p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'not_photograph_type';
  END IF;
  SELECT * INTO upload_row
  FROM app.document_uploads du
  WHERE du.finalized_document_id = doc_row.id
    AND du.status = 'FINALIZED'
    AND du.final_storage_object_key = doc_row.storage_object_key
    AND du.verified_sha256_hash = doc_row.sha256_hash
    AND du.verified_file_size_bytes = doc_row.file_size_bytes
    AND EXISTS (
      SELECT 1 FROM app.document_scans ds
      WHERE ds.document_upload_id = du.id
        AND ds.status = 'CLEAN'
        AND ds.scanned_sha256_hash = du.verified_sha256_hash
        AND ds.scanned_file_size_bytes = du.verified_file_size_bytes
    )
  LIMIT 1;
  IF upload_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Photograph source is not finalized from a clean scan.';
  END IF;

  SELECT * INTO derivative_row FROM app.document_image_derivatives WHERE document_image_derivatives.document_id = doc_row.id FOR UPDATE;
  IF derivative_row.document_id IS NULL THEN
    derivative_token := app.document_image_generate_derivative_token();
    INSERT INTO app.document_image_derivatives (
      document_id,
      processing_status,
      source_sha256_hash,
      thumbnail_storage_object_key,
      preview_storage_object_key
    )
    VALUES (
      doc_row.id,
      'PENDING',
      doc_row.sha256_hash,
      'derivatives/' || doc_row.id::text || '/' || derivative_token || '/thumbnail.webp',
      'derivatives/' || doc_row.id::text || '/' || derivative_token || '/preview.webp'
    )
    RETURNING * INTO derivative_row;
  END IF;

  IF derivative_row.processing_status = 'READY' THEN
    RETURN QUERY SELECT doc_row.id, doc_row.storage_bucket::text, doc_row.storage_object_key, doc_row.mime_type::text, doc_row.file_size_bytes, doc_row.sha256_hash, doc_row.document_type_code::text, derivative_row.processing_status, derivative_row.thumbnail_storage_object_key, derivative_row.preview_storage_object_key;
    RETURN;
  END IF;

  IF derivative_row.processing_status IN ('PENDING','FAILED') THEN
    did_start := true;
  END IF;

  UPDATE app.document_image_derivatives
  SET processing_status = 'PROCESSING',
      source_sha256_hash = doc_row.sha256_hash,
      processing_started_at = coalesce(processing_started_at, transaction_timestamp()),
      processing_completed_at = NULL,
      processing_failed_at = NULL,
      failure_code = NULL,
      thumbnail_file_size_bytes = NULL,
      thumbnail_sha256_hash = NULL,
      thumbnail_width = NULL,
      thumbnail_height = NULL,
      preview_file_size_bytes = NULL,
      preview_sha256_hash = NULL,
      preview_width = NULL,
      preview_height = NULL
  WHERE document_image_derivatives.document_id = doc_row.id
  RETURNING * INTO derivative_row;

  IF did_start THEN
    PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'photograph_processing_started', 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('document_type_code', doc_row.document_type_code));
  END IF;

  RETURN QUERY SELECT doc_row.id, doc_row.storage_bucket::text, doc_row.storage_object_key, doc_row.mime_type::text, doc_row.file_size_bytes, doc_row.sha256_hash, doc_row.document_type_code::text, derivative_row.processing_status, derivative_row.thumbnail_storage_object_key, derivative_row.preview_storage_object_key;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_complete_document_image_processing(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_source_sha256_hash bytea,
  p_source_width integer,
  p_source_height integer,
  p_thumbnail_file_size_bytes bigint,
  p_thumbnail_sha256_hash bytea,
  p_thumbnail_width integer,
  p_thumbnail_height integer,
  p_preview_file_size_bytes bigint,
  p_preview_sha256_hash bytea,
  p_preview_width integer,
  p_preview_height integer,
  p_processor_version text,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  document_id uuid,
  processing_status app.document_image_processing_status,
  thumbnail_storage_object_key text,
  preview_storage_object_key text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  doc_row app.documents%ROWTYPE;
  derivative_row app.document_image_derivatives%ROWTYPE;
  was_ready boolean := false;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO doc_row FROM app.documents WHERE id = p_document_id FOR UPDATE;
  SELECT * INTO derivative_row FROM app.document_image_derivatives WHERE document_image_derivatives.document_id = p_document_id FOR UPDATE;
  IF doc_row.id IS NULL OR derivative_row.document_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Photograph processing is not available.';
  END IF;
  IF derivative_row.processing_status = 'READY' THEN
    RETURN QUERY SELECT derivative_row.document_id, derivative_row.processing_status, derivative_row.thumbnail_storage_object_key, derivative_row.preview_storage_object_key;
    RETURN;
  END IF;
  IF derivative_row.processing_status <> 'PROCESSING' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Photograph processing is not in progress.';
  END IF;
  IF doc_row.sha256_hash <> p_source_sha256_hash OR derivative_row.source_sha256_hash <> p_source_sha256_hash THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Photograph source hash mismatch.';
  END IF;

  UPDATE app.document_image_derivatives
  SET processing_status = 'READY',
      source_sha256_hash = p_source_sha256_hash,
      source_width = p_source_width,
      source_height = p_source_height,
      thumbnail_file_size_bytes = p_thumbnail_file_size_bytes,
      thumbnail_sha256_hash = p_thumbnail_sha256_hash,
      thumbnail_width = p_thumbnail_width,
      thumbnail_height = p_thumbnail_height,
      preview_file_size_bytes = p_preview_file_size_bytes,
      preview_sha256_hash = p_preview_sha256_hash,
      preview_width = p_preview_width,
      preview_height = p_preview_height,
      processor_version = left(NULLIF(btrim(p_processor_version), ''), 80),
      failure_code = NULL,
      processing_completed_at = transaction_timestamp(),
      processing_failed_at = NULL
  WHERE document_image_derivatives.document_id = p_document_id
  RETURNING * INTO derivative_row;

  IF NOT was_ready THEN
    PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'photograph_processing_completed', 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('source_width', p_source_width, 'source_height', p_source_height, 'thumbnail_width', p_thumbnail_width, 'thumbnail_height', p_thumbnail_height, 'preview_width', p_preview_width, 'preview_height', p_preview_height));
  END IF;
  RETURN QUERY SELECT derivative_row.document_id, derivative_row.processing_status, derivative_row.thumbnail_storage_object_key, derivative_row.preview_storage_object_key;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_fail_document_image_processing(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_failure_code text,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (document_id uuid, processing_status app.document_image_processing_status, failure_code text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  derivative_row app.document_image_derivatives%ROWTYPE;
  safe_failure text;
  did_fail boolean := false;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  safe_failure := CASE p_failure_code
    WHEN 'unsupported_mime' THEN p_failure_code
    WHEN 'not_photograph_type' THEN p_failure_code
    WHEN 'original_unavailable' THEN p_failure_code
    WHEN 'original_hash_mismatch' THEN p_failure_code
    WHEN 'decode_failed' THEN p_failure_code
    WHEN 'dimensions_unavailable' THEN p_failure_code
    WHEN 'source_dimensions_exceeded' THEN p_failure_code
    WHEN 'decoded_pixels_exceeded' THEN p_failure_code
    WHEN 'animated_image_unsupported' THEN p_failure_code
    WHEN 'processor_timeout' THEN p_failure_code
    WHEN 'processor_error' THEN p_failure_code
    WHEN 'derivative_upload_failed' THEN p_failure_code
    WHEN 'derivative_verify_failed' THEN p_failure_code
    ELSE 'processor_error'
  END;
  SELECT * INTO derivative_row FROM app.document_image_derivatives WHERE document_image_derivatives.document_id = p_document_id FOR UPDATE;
  IF derivative_row.document_id IS NULL THEN
    INSERT INTO app.document_image_derivatives (document_id, processing_status, failure_code, processing_failed_at)
    VALUES (p_document_id, 'FAILED', safe_failure, transaction_timestamp())
    RETURNING * INTO derivative_row;
    did_fail := true;
  ELSIF derivative_row.processing_status <> 'READY' THEN
    did_fail := derivative_row.processing_status IS DISTINCT FROM 'FAILED' OR derivative_row.failure_code IS DISTINCT FROM safe_failure;
    UPDATE app.document_image_derivatives
    SET processing_status = 'FAILED',
        failure_code = safe_failure,
        processing_failed_at = transaction_timestamp(),
        processing_completed_at = NULL,
        thumbnail_file_size_bytes = NULL,
        thumbnail_sha256_hash = NULL,
        thumbnail_width = NULL,
        thumbnail_height = NULL,
        preview_file_size_bytes = NULL,
        preview_sha256_hash = NULL,
        preview_width = NULL,
        preview_height = NULL
    WHERE document_image_derivatives.document_id = p_document_id
    RETURNING * INTO derivative_row;
  END IF;
  IF did_fail THEN
    PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'photograph_processing_failed', 'document', p_document_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('failure_code', safe_failure));
  END IF;
  RETURN QUERY SELECT derivative_row.document_id, derivative_row.processing_status, derivative_row.failure_code::text;
END
$function$;

CREATE OR REPLACE FUNCTION app.authorize_document_image_access(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_mode text,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  document_id uuid,
  document_number text,
  storage_bucket text,
  storage_object_key text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  status app.document_status,
  content_disposition text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_role record;
  client_row app.clients%ROWTYPE;
  doc_row app.documents%ROWTYPE;
  derivative_row app.document_image_derivatives%ROWTYPE;
  client_allowed boolean := false;
  safe_name text;
BEGIN
  IF p_mode NOT IN ('original','preview','thumbnail','download') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document access purpose is invalid.';
  END IF;
  SELECT * INTO doc_row FROM app.documents WHERE id = p_document_id;
  IF doc_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
  END IF;
  SELECT * INTO derivative_row FROM app.document_image_derivatives WHERE document_image_derivatives.document_id = doc_row.id;

  SELECT * INTO actor_role FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_role.actor_user_id IS NOT NULL THEN
    IF doc_row.status NOT IN ('ACTIVE','ARCHIVED') THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
  ELSE
    SELECT c.* INTO client_row
    FROM app.clients c
    JOIN app.users u ON u.id = c.portal_user_id
    WHERE u.auth_subject = p_actor_auth_subject
      AND u.status = 'ACTIVE'
      AND u.is_active
      AND c.status = 'ACTIVE'
      AND c.is_active
      AND c.archived_at IS NULL;
    IF client_row.id IS NULL OR doc_row.status <> 'ACTIVE' OR NOT doc_row.client_visible THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
    client_allowed := EXISTS (
      SELECT 1
      FROM app.document_links dl
      LEFT JOIN app.projects p ON p.id = dl.project_id
      LEFT JOIN app.tasks t ON t.id = dl.task_id
      LEFT JOIN app.progress_updates pu ON pu.id = dl.progress_update_id
      LEFT JOIN app.projects tp ON tp.id = t.project_id
      LEFT JOIN app.projects pp ON pp.id = pu.project_id
      LEFT JOIN app.client_payments cp ON cp.id = dl.client_payment_id
      LEFT JOIN app.payment_requests pr ON pr.id = dl.payment_request_id
      WHERE dl.document_id = doc_row.id
        AND dl.project_expense_id IS NULL
        AND dl.currency_exchange_id IS NULL
        AND (
          dl.client_id = client_row.id
          OR p.client_id = client_row.id
          OR tp.client_id = client_row.id
          OR pp.client_id = client_row.id
          OR cp.client_id = client_row.id
          OR pr.client_id = client_row.id
        )
    ) AND NOT EXISTS (
      SELECT 1
      FROM app.document_links other_dl
      LEFT JOIN app.projects other_p ON other_p.id = other_dl.project_id
      LEFT JOIN app.tasks other_t ON other_t.id = other_dl.task_id
      LEFT JOIN app.progress_updates other_pu ON other_pu.id = other_dl.progress_update_id
      LEFT JOIN app.projects other_tp ON other_tp.id = other_t.project_id
      LEFT JOIN app.projects other_pp ON other_pp.id = other_pu.project_id
      LEFT JOIN app.client_payments other_cp ON other_cp.id = other_dl.client_payment_id
      LEFT JOIN app.payment_requests other_pr ON other_pr.id = other_dl.payment_request_id
      WHERE other_dl.document_id = doc_row.id
        AND coalesce(other_dl.client_id, other_p.client_id, other_tp.client_id, other_pp.client_id, other_cp.client_id, other_pr.client_id) IS DISTINCT FROM client_row.id
    ) AND app.document_image_client_parent_visible(doc_row.id, client_row.id);
    IF NOT client_allowed THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
    actor_role.actor_user_id := client_row.portal_user_id;
    actor_role.actor_auth_subject := p_actor_auth_subject;
    actor_role.effective_role_code := 'client';
    IF p_mode = 'original' AND doc_row.document_type_code IN ('PROGRESS_PHOTOGRAPH','TASK_ATTACHMENT') AND doc_row.mime_type IN ('image/jpeg','image/png','image/webp') THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
  END IF;

  safe_name := regexp_replace(doc_row.original_file_name, '[\r\n"\\/]+', '_', 'g');
  IF p_mode IN ('preview','thumbnail','download') AND doc_row.document_type_code IN ('PROGRESS_PHOTOGRAPH','TASK_ATTACHMENT') AND doc_row.mime_type IN ('image/jpeg','image/png','image/webp') THEN
    IF derivative_row.processing_status <> 'READY' THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
    IF p_mode = 'thumbnail' THEN
      PERFORM app.write_activity_log(actor_role.actor_user_id, actor_role.actor_auth_subject, actor_role.effective_role_code, 'document_preview_authorized', 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('purpose', 'thumbnail'));
      RETURN QUERY SELECT doc_row.id, doc_row.document_number::text, 'documents-private'::text, derivative_row.thumbnail_storage_object_key, safe_name, 'image/webp'::text, derivative_row.thumbnail_file_size_bytes, doc_row.status, 'inline; filename="' || safe_name || '.webp"';
      RETURN;
    ELSE
      PERFORM app.write_activity_log(actor_role.actor_user_id, actor_role.actor_auth_subject, actor_role.effective_role_code, CASE WHEN p_mode = 'download' THEN 'document_download_authorized' ELSE 'document_preview_authorized' END, 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('purpose', p_mode, 'sanitized_derivative', true));
      RETURN QUERY SELECT doc_row.id, doc_row.document_number::text, 'documents-private'::text, derivative_row.preview_storage_object_key, safe_name, 'image/webp'::text, derivative_row.preview_file_size_bytes, doc_row.status, (CASE WHEN p_mode = 'download' THEN 'attachment' ELSE 'inline' END) || '; filename="' || safe_name || '.webp"';
      RETURN;
    END IF;
  END IF;

  IF p_mode = 'thumbnail' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document cannot be previewed.';
  END IF;
  RETURN QUERY SELECT * FROM app.authorize_document_access(p_actor_auth_subject, p_document_id, CASE WHEN p_mode = 'download' THEN 'download' ELSE 'preview' END, p_request_identifier);
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_prepare_document_image_processing(p_verified_owner_auth_subject uuid, p_document_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, storage_bucket text, storage_object_key text, mime_type text, source_file_size_bytes bigint, source_sha256_hash bytea, document_type_code text, processing_status app.document_image_processing_status, thumbnail_storage_object_key text, preview_storage_object_key text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_prepare_document_image_processing(p_verified_owner_auth_subject, p_document_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_complete_document_image_processing(p_verified_owner_auth_subject uuid, p_document_id uuid, p_source_sha256_hash bytea, p_source_width integer, p_source_height integer, p_thumbnail_file_size_bytes bigint, p_thumbnail_sha256_hash bytea, p_thumbnail_width integer, p_thumbnail_height integer, p_preview_file_size_bytes bigint, p_preview_sha256_hash bytea, p_preview_width integer, p_preview_height integer, p_processor_version text, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, processing_status app.document_image_processing_status, thumbnail_storage_object_key text, preview_storage_object_key text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_complete_document_image_processing(p_verified_owner_auth_subject, p_document_id, p_source_sha256_hash, p_source_width, p_source_height, p_thumbnail_file_size_bytes, p_thumbnail_sha256_hash, p_thumbnail_width, p_thumbnail_height, p_preview_file_size_bytes, p_preview_sha256_hash, p_preview_width, p_preview_height, p_processor_version, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_fail_document_image_processing(p_verified_owner_auth_subject uuid, p_document_id uuid, p_failure_code text, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, processing_status app.document_image_processing_status, failure_code text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_fail_document_image_processing(p_verified_owner_auth_subject, p_document_id, p_failure_code, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_authorize_document_image_access(p_verified_auth_subject uuid, p_document_id uuid, p_mode text, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, document_number text, storage_bucket text, storage_object_key text, original_file_name text, mime_type text, file_size_bytes bigint, status app.document_status, content_disposition text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.authorize_document_image_access(p_verified_auth_subject, p_document_id, p_mode, p_request_identifier);
$function$;

COMMIT;
