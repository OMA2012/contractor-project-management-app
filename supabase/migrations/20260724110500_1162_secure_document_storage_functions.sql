BEGIN;

CREATE OR REPLACE FUNCTION app.document_allowed_extension(p_file_name text, p_mime_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $function$
  SELECT CASE lower(substring(p_file_name from '\.([^.]+)$'))
    WHEN 'pdf' THEN p_mime_type = 'application/pdf'
    WHEN 'jpg' THEN p_mime_type = 'image/jpeg'
    WHEN 'jpeg' THEN p_mime_type = 'image/jpeg'
    WHEN 'png' THEN p_mime_type = 'image/png'
    WHEN 'webp' THEN p_mime_type = 'image/webp'
    ELSE false
  END;
$function$;

CREATE OR REPLACE FUNCTION app.document_filename_is_safe(p_file_name text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $function$
  SELECT p_file_name IS NOT NULL
    AND btrim(p_file_name) <> ''
    AND length(btrim(p_file_name)) <= 255
    AND btrim(p_file_name) !~ '[/\\]'
    AND btrim(p_file_name) NOT IN ('.', '..')
    AND lower(btrim(p_file_name)) !~ '\.(exe|dll|bat|cmd|ps1|sh|js|jar|com|msi|vbs|scr|zip|rar|7z|tar|gz|docm|xlsm|pptm)(\.|$)'
    AND lower(substring(btrim(p_file_name) from '\.([^.]+)$')) IN ('pdf','jpg','jpeg','png','webp');
$function$;

CREATE OR REPLACE FUNCTION app.document_validate_upload_request(p_file_name text, p_mime_type text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
DECLARE
  normalized text := btrim(coalesce(p_file_name, ''));
BEGIN
  IF normalized = '' OR length(normalized) > 255 OR normalized ~ '[/\\]' OR normalized IN ('.', '..') OR normalized LIKE '%..%' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid document filename.';
  END IF;
  IF lower(normalized) ~ '\.(exe|dll|bat|cmd|ps1|sh|js|jar|com|msi|vbs|scr|zip|rar|7z|tar|gz|docm|xlsm|pptm)(\.|$)' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document file type is not allowed.';
  END IF;
  IF p_mime_type NOT IN ('application/pdf','image/jpeg','image/png','image/webp') OR NOT app.document_allowed_extension(normalized, p_mime_type) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document MIME type and extension do not match.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.document_target_exists(
  p_client_id uuid,
  p_project_id uuid,
  p_task_id uuid,
  p_progress_update_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN p_client_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.clients c WHERE c.id = p_client_id AND c.is_active AND c.archived_at IS NULL)
    WHEN p_project_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.projects p WHERE p.id = p_project_id AND p.archived_at IS NULL)
    WHEN p_task_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.tasks t JOIN app.projects p ON p.id = t.project_id WHERE t.id = p_task_id AND t.is_active AND p.archived_at IS NULL)
    WHEN p_progress_update_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.progress_updates pu JOIN app.projects p ON p.id = pu.project_id WHERE pu.id = p_progress_update_id AND pu.archived_at IS NULL AND p.archived_at IS NULL)
    ELSE false
  END;
$function$;

CREATE OR REPLACE FUNCTION app.owner_reserve_document_upload(
  p_actor_auth_subject uuid,
  p_storage_object_token text,
  p_original_file_name text,
  p_declared_mime_type text,
  p_document_type_code varchar(50),
  p_requested_client_visible boolean DEFAULT false,
  p_client_id uuid DEFAULT NULL,
  p_project_id uuid DEFAULT NULL,
  p_task_id uuid DEFAULT NULL,
  p_progress_update_id uuid DEFAULT NULL,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  reserved_document_id uuid,
  storage_bucket text,
  storage_object_key text,
  expires_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  new_upload_id uuid := gen_random_uuid();
  new_document_id uuid := gen_random_uuid();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_storage_object_token IS NULL OR p_storage_object_token !~ '^[A-Za-z0-9_-]{43}$' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid document upload token.';
  END IF;
  IF p_document_type_code !~ '^[A-Z][A-Z0-9_]{0,49}$' OR NOT EXISTS (SELECT 1 FROM app.document_types dt WHERE dt.code = p_document_type_code AND dt.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document type is not available.';
  END IF;
  IF num_nonnulls(p_client_id, p_project_id, p_task_id, p_progress_update_id) <> 1 OR NOT app.document_target_exists(p_client_id, p_project_id, p_task_id, p_progress_update_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document link target is not available.';
  END IF;
  PERFORM app.document_validate_upload_request(p_original_file_name, p_declared_mime_type);

  INSERT INTO app.document_uploads (
    id, reserved_document_id, storage_object_key, original_file_name, declared_mime_type,
    document_type_code, requested_client_visible, client_id, project_id, task_id,
    progress_update_id, authorized_by, expires_at
  )
  VALUES (
    new_upload_id, new_document_id, 'temporary/' || new_upload_id::text || '/' || p_storage_object_token,
    btrim(p_original_file_name), p_declared_mime_type, p_document_type_code, coalesce(p_requested_client_visible, false),
    p_client_id, p_project_id, p_task_id, p_progress_update_id, actor_row.actor_user_id,
    transaction_timestamp() + interval '5 minutes'
  )
  RETURNING id, document_uploads.reserved_document_id, document_uploads.storage_bucket::text, document_uploads.storage_object_key, document_uploads.expires_at
  INTO upload_id, reserved_document_id, storage_bucket, storage_object_key, expires_at;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_upload_authorized', 'document_upload', upload_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('document_type_code', p_document_type_code));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_complete_document_upload(
  p_actor_auth_subject uuid,
  p_upload_id uuid,
  p_verified_mime_type text,
  p_verified_file_size_bytes bigint,
  p_verified_sha256_hash bytea,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  status app.document_upload_status,
  reserved_document_id uuid,
  verified_mime_type text,
  verified_file_size_bytes bigint,
  verified_sha256_hash bytea
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  upload_row app.document_uploads%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF upload_row.id IS NULL OR upload_row.authorized_by <> actor_row.actor_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload is not authorized.';
  END IF;
  IF upload_row.status = 'AWAITING_SCAN' THEN
    RETURN QUERY SELECT upload_row.id, upload_row.status, upload_row.reserved_document_id, upload_row.verified_mime_type::text, upload_row.verified_file_size_bytes, upload_row.verified_sha256_hash;
    RETURN;
  END IF;
  IF upload_row.status IN ('FAILED','EXPIRED') OR upload_row.expires_at <= transaction_timestamp() THEN
    UPDATE app.document_uploads SET status = 'EXPIRED', expired_at = coalesce(expired_at, transaction_timestamp()), failure_code = coalesce(failure_code, 'reservation_expired') WHERE id = upload_row.id;
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload reservation expired.';
  END IF;
  IF p_verified_mime_type NOT IN ('application/pdf','image/jpeg','image/png','image/webp')
     OR NOT app.document_allowed_extension(upload_row.original_file_name, p_verified_mime_type)
     OR p_verified_mime_type <> upload_row.declared_mime_type THEN
    UPDATE app.document_uploads SET status = 'FAILED', failed_at = transaction_timestamp(), failure_code = 'mime_or_extension_mismatch' WHERE id = upload_row.id;
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload validation failed.';
  END IF;
  IF p_verified_file_size_bytes IS NULL OR p_verified_file_size_bytes <= 0 OR p_verified_file_size_bytes > 26214400 OR octet_length(p_verified_sha256_hash) <> 32 THEN
    UPDATE app.document_uploads SET status = 'FAILED', failed_at = transaction_timestamp(), failure_code = 'size_or_hash_invalid' WHERE id = upload_row.id;
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload validation failed.';
  END IF;

  UPDATE app.document_uploads
  SET status = 'AWAITING_SCAN',
      uploaded_at = coalesce(uploaded_at, transaction_timestamp()),
      validated_at = coalesce(validated_at, transaction_timestamp()),
      awaiting_scan_at = coalesce(awaiting_scan_at, transaction_timestamp()),
      verified_mime_type = p_verified_mime_type,
      verified_file_size_bytes = p_verified_file_size_bytes,
      verified_sha256_hash = p_verified_sha256_hash
  WHERE id = upload_row.id
  RETURNING id, document_uploads.status, document_uploads.reserved_document_id, document_uploads.verified_mime_type::text, document_uploads.verified_file_size_bytes, document_uploads.verified_sha256_hash
  INTO upload_id, status, reserved_document_id, verified_mime_type, verified_file_size_bytes, verified_sha256_hash;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_upload_awaiting_scan', 'document_upload', upload_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('verified_mime_type', p_verified_mime_type, 'verified_file_size_bytes', p_verified_file_size_bytes));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_document_upload_storage_context(
  p_actor_auth_subject uuid,
  p_upload_id uuid
)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  RETURN QUERY
  SELECT du.id, du.status, du.storage_bucket::text, du.storage_object_key, du.expires_at
  FROM app.document_uploads du
  WHERE du.id = p_upload_id
    AND du.authorized_by = actor_row.actor_user_id
    AND du.finalized_document_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload is not authorized.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.authorize_document_access(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_purpose text,
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
  safe_name text;
BEGIN
  IF p_purpose NOT IN ('preview','download') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document access purpose is invalid.';
  END IF;
  SELECT * INTO doc_row FROM app.documents WHERE id = p_document_id;
  IF doc_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
  END IF;

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
    IF client_row.id IS NULL OR doc_row.status <> 'ACTIVE' OR NOT doc_row.client_visible OR NOT EXISTS (
      SELECT 1
      FROM app.document_links dl
      LEFT JOIN app.projects p ON p.id = dl.project_id
      LEFT JOIN app.tasks t ON t.id = dl.task_id
      LEFT JOIN app.progress_updates pu ON pu.id = dl.progress_update_id
      LEFT JOIN app.projects tp ON tp.id = t.project_id
      LEFT JOIN app.projects pp ON pp.id = pu.project_id
      WHERE dl.document_id = doc_row.id
        AND (dl.client_id = client_row.id OR p.client_id = client_row.id OR tp.client_id = client_row.id OR pp.client_id = client_row.id)
    ) OR EXISTS (
      SELECT 1
      FROM app.document_links dl
      LEFT JOIN app.projects p ON p.id = dl.project_id
      LEFT JOIN app.tasks t ON t.id = dl.task_id
      LEFT JOIN app.progress_updates pu ON pu.id = dl.progress_update_id
      LEFT JOIN app.projects tp ON tp.id = t.project_id
      LEFT JOIN app.projects pp ON pp.id = pu.project_id
      WHERE dl.document_id = doc_row.id
        AND coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id) IS DISTINCT FROM client_row.id
    ) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
    actor_role.actor_user_id := client_row.portal_user_id;
    actor_role.actor_auth_subject := p_actor_auth_subject;
    actor_role.effective_role_code := 'client';
  END IF;

  safe_name := regexp_replace(doc_row.original_file_name, '[\r\n"\\/]+', '_', 'g');
  PERFORM app.write_activity_log(actor_role.actor_user_id, actor_role.actor_auth_subject, actor_role.effective_role_code, CASE p_purpose WHEN 'preview' THEN 'document_preview_authorized' ELSE 'document_download_authorized' END, 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('purpose', p_purpose));
  RETURN QUERY SELECT doc_row.id, doc_row.document_number::text, doc_row.storage_bucket::text, doc_row.storage_object_key, doc_row.original_file_name::text, doc_row.mime_type::text, doc_row.file_size_bytes, doc_row.status, (CASE WHEN p_purpose = 'preview' THEN 'inline' ELSE 'attachment' END) || '; filename="' || safe_name || '"';
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_document_list_for_authenticated_user(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_type_code text,
  uploaded_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  client_row app.clients%ROWTYPE;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;
  SELECT c.* INTO client_row
  FROM app.clients AS c
  INNER JOIN app.users AS u ON u.id = c.portal_user_id
  WHERE u.auth_subject = auth.uid()
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL;
  IF client_row.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT d.id, d.document_number::text, d.original_file_name::text, d.mime_type::text, d.file_size_bytes, d.document_type_code::text, d.uploaded_at
  FROM app.documents AS d
  INNER JOIN app.document_links AS dl ON dl.document_id = d.id
  LEFT JOIN app.projects AS p ON p.id = dl.project_id
  LEFT JOIN app.tasks AS t ON t.id = dl.task_id
  LEFT JOIN app.progress_updates AS pu ON pu.id = dl.progress_update_id
  LEFT JOIN app.projects AS tp ON tp.id = t.project_id
  LEFT JOIN app.projects AS pp ON pp.id = pu.project_id
  WHERE d.status = 'ACTIVE'
    AND d.client_visible
    AND (
      dl.client_id = client_row.id
      OR p.client_id = client_row.id
      OR tp.client_id = client_row.id
      OR pp.client_id = client_row.id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM app.document_links other_dl
      LEFT JOIN app.projects other_p ON other_p.id = other_dl.project_id
      LEFT JOIN app.tasks other_t ON other_t.id = other_dl.task_id
      LEFT JOIN app.progress_updates other_pu ON other_pu.id = other_dl.progress_update_id
      LEFT JOIN app.projects other_tp ON other_tp.id = other_t.project_id
      LEFT JOIN app.projects other_pp ON other_pp.id = other_pu.project_id
      WHERE other_dl.document_id = d.id
        AND coalesce(other_dl.client_id, other_p.client_id, other_tp.client_id, other_pp.client_id) IS DISTINCT FROM client_row.id
    )
  ORDER BY d.uploaded_at DESC, d.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_invalidate_expired_document_upload(
  p_actor_auth_subject uuid,
  p_upload_id uuid,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, storage_bucket text, storage_object_key text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  upload_row app.document_uploads%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF upload_row.id IS NULL
     OR upload_row.finalized_document_id IS NOT NULL
     OR upload_row.status NOT IN ('AUTHORIZED','UPLOADED','VALIDATED','FAILED','EXPIRED') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload invalidation denied.';
  END IF;
  IF EXISTS (SELECT 1 FROM app.documents d WHERE d.storage_bucket = upload_row.storage_bucket AND d.storage_object_key = upload_row.storage_object_key) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload invalidation denied.';
  END IF;
  UPDATE app.document_uploads
  SET status = CASE WHEN app.document_uploads.status = 'AUTHORIZED' AND app.document_uploads.expires_at <= transaction_timestamp() THEN 'EXPIRED' ELSE app.document_uploads.status END,
      expired_at = CASE WHEN app.document_uploads.status = 'AUTHORIZED' AND app.document_uploads.expires_at <= transaction_timestamp() THEN coalesce(app.document_uploads.expired_at, transaction_timestamp()) ELSE app.document_uploads.expired_at END,
      invalidated_at = coalesce(invalidated_at, transaction_timestamp()),
      failure_code = coalesce(failure_code, 'orphan_invalidated')
  WHERE id = upload_row.id
  RETURNING id, document_uploads.status, document_uploads.storage_bucket::text, document_uploads.storage_object_key
  INTO upload_id, status, storage_bucket, storage_object_key;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'orphan_upload_invalidated', 'document_upload', upload_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_document_metadata(
  p_actor_auth_subject uuid,
  p_storage_bucket text,
  p_storage_object_key text,
  p_original_file_name text,
  p_mime_type text,
  p_file_size_bytes bigint,
  p_sha256_hash bytea,
  p_document_type_code varchar(50),
  p_client_visible boolean DEFAULT false,
  p_notes text DEFAULT NULL
)
RETURNS TABLE (document_id uuid, document_number text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document metadata creation requires secure upload finalization.';
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_reserve_document_upload(p_verified_owner_auth_subject uuid, p_storage_object_token text, p_original_file_name text, p_declared_mime_type text, p_document_type_code varchar(50), p_requested_client_visible boolean DEFAULT false, p_client_id uuid DEFAULT NULL, p_project_id uuid DEFAULT NULL, p_task_id uuid DEFAULT NULL, p_progress_update_id uuid DEFAULT NULL, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (upload_id uuid, reserved_document_id uuid, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_reserve_document_upload(p_verified_owner_auth_subject, p_storage_object_token, p_original_file_name, p_declared_mime_type, p_document_type_code, p_requested_client_visible, p_client_id, p_project_id, p_task_id, p_progress_update_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_complete_document_upload(p_verified_owner_auth_subject uuid, p_upload_id uuid, p_verified_mime_type text, p_verified_file_size_bytes bigint, p_verified_sha256_hash bytea, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, reserved_document_id uuid, verified_mime_type text, verified_file_size_bytes bigint, verified_sha256_hash bytea)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_complete_document_upload(p_verified_owner_auth_subject, p_upload_id, p_verified_mime_type, p_verified_file_size_bytes, p_verified_sha256_hash, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_document_upload_storage_context(p_verified_owner_auth_subject uuid, p_upload_id uuid)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_document_upload_storage_context(p_verified_owner_auth_subject, p_upload_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_authorize_document_access(p_verified_auth_subject uuid, p_document_id uuid, p_purpose text, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, document_number text, storage_bucket text, storage_object_key text, original_file_name text, mime_type text, file_size_bytes bigint, status app.document_status, content_disposition text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.authorize_document_access(p_verified_auth_subject, p_document_id, p_purpose, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_invalidate_expired_document_upload(p_verified_owner_auth_subject uuid, p_upload_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, storage_bucket text, storage_object_key text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_invalidate_expired_document_upload(p_verified_owner_auth_subject, p_upload_id, p_request_identifier);
$function$;

COMMIT;
