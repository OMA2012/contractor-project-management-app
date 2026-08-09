BEGIN;

CREATE OR REPLACE FUNCTION app.document_business_context(p_document_id uuid)
RETURNS TABLE (client_id uuid, project_id uuid, context_count integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH normalized_context AS (
    SELECT DISTINCT
      coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id, cp.client_id, pr.client_id, pe_project.client_id, ce_project.client_id) AS client_id,
      coalesce(dl.project_id, t.project_id, pu.project_id, cp.project_id, pr.project_id, pe_event.project_id, ce_event.project_id) AS project_id
    FROM app.document_links dl
    LEFT JOIN app.projects p ON p.id = dl.project_id
    LEFT JOIN app.tasks t ON t.id = dl.task_id
    LEFT JOIN app.progress_updates pu ON pu.id = dl.progress_update_id
    LEFT JOIN app.projects tp ON tp.id = t.project_id
    LEFT JOIN app.projects pp ON pp.id = pu.project_id
    LEFT JOIN app.client_payments cp ON cp.id = dl.client_payment_id
    LEFT JOIN app.payment_requests pr ON pr.id = dl.payment_request_id
    LEFT JOIN app.project_expenses pe ON pe.id = dl.project_expense_id
    LEFT JOIN app.financial_events pe_event ON pe_event.id = pe.financial_event_id
    LEFT JOIN app.projects pe_project ON pe_project.id = pe_event.project_id
    LEFT JOIN app.currency_exchanges ce ON ce.id = dl.currency_exchange_id
    LEFT JOIN app.financial_events ce_event ON ce_event.id = ce.financial_event_id
    LEFT JOIN app.projects ce_project ON ce_project.id = ce_event.project_id
    WHERE dl.document_id = p_document_id
  )
  SELECT
    (array_agg(client_id ORDER BY client_id::text))[1] AS client_id,
    (array_agg(project_id ORDER BY project_id::text NULLS FIRST))[1] AS project_id,
    count(*)::integer AS context_count
  FROM normalized_context;
$function$;

CREATE OR REPLACE FUNCTION app.document_is_superseded(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app.document_replacements dr
    WHERE dr.superseded_document_id = p_document_id
  );
$function$;

CREATE OR REPLACE FUNCTION app.document_is_client_lifecycle_private(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app.document_client_access_privacy privacy
    WHERE privacy.document_id = p_document_id
  );
$function$;

CREATE OR REPLACE FUNCTION app.document_replacement_would_cycle(
  p_superseded_document_id uuid,
  p_replacement_document_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH RECURSIVE replacement_chain(document_id) AS (
    SELECT p_replacement_document_id
    UNION ALL
    SELECT dr.replacement_document_id
    FROM app.document_replacements dr
    JOIN replacement_chain rc ON rc.document_id = dr.superseded_document_id
  )
  SELECT EXISTS (
    SELECT 1
    FROM replacement_chain
    WHERE document_id = p_superseded_document_id
  );
$function$;

CREATE OR REPLACE FUNCTION app.document_is_finalized_from_clean_scan(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app.document_uploads du
    JOIN app.documents d ON d.id = du.finalized_document_id
    WHERE d.id = p_document_id
      AND d.status = 'ACTIVE'
      AND du.status = 'FINALIZED'
      AND du.finalized_document_id = d.id
      AND du.final_storage_object_key = d.storage_object_key
      AND du.verified_sha256_hash = d.sha256_hash
      AND du.verified_file_size_bytes = d.file_size_bytes
      AND EXISTS (
        SELECT 1
        FROM app.document_scans ds
        WHERE ds.document_upload_id = du.id
          AND ds.status = 'CLEAN'
          AND ds.scanned_sha256_hash = du.verified_sha256_hash
          AND ds.scanned_file_size_bytes = du.verified_file_size_bytes
      )
  );
$function$;

CREATE OR REPLACE FUNCTION app.owner_archive_document_metadata(p_actor_auth_subject uuid, p_document_id uuid)
RETURNS TABLE (document_id uuid, status app.document_status, archived_at timestamptz, archived_by uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  doc_row app.documents%ROWTYPE;
  workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO doc_row FROM app.documents WHERE id = p_document_id FOR UPDATE;
  IF doc_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document metadata is not available.';
  END IF;

  IF doc_row.status = 'ARCHIVED' THEN
    RETURN QUERY SELECT doc_row.id, doc_row.status, doc_row.archived_at, doc_row.archived_by;
    RETURN;
  END IF;

  PERFORM set_config('app.document_metadata_context', 'owner_metadata_mutation', true);
  UPDATE app.documents AS d
  SET status = 'ARCHIVED',
      archived_at = workflow_at,
      archived_by = actor_row.actor_user_id
  WHERE d.id = doc_row.id
  RETURNING d.id, d.status, d.archived_at, d.archived_by
  INTO document_id, status, archived_at, archived_by;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_archived', 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, NULL, NULL, jsonb_build_object('document_id', doc_row.id, 'previous_status', doc_row.status, 'new_status', 'ARCHIVED'));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_restore_document_metadata(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (document_id uuid, status app.document_status, client_visible boolean, archived_at timestamptz, archived_by uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  doc_row app.documents%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO doc_row FROM app.documents WHERE id = p_document_id FOR UPDATE;
  IF doc_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document metadata is not available.';
  END IF;
  IF doc_row.status <> 'ARCHIVED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Only archived documents can be restored.';
  END IF;
  IF app.document_is_superseded(doc_row.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Superseded documents cannot be restored as current documents.';
  END IF;

  PERFORM set_config('app.document_metadata_context', 'owner_metadata_mutation', true);
  UPDATE app.documents AS d
  SET status = 'ACTIVE',
      client_visible = false,
      archived_at = NULL,
      archived_by = NULL
  WHERE d.id = doc_row.id
  RETURNING d.id, d.status, d.client_visible, d.archived_at, d.archived_by
  INTO document_id, status, client_visible, archived_at, archived_by;

  PERFORM set_config('app.document_lifecycle_context', 'owner_document_lifecycle_mutation', true);
  INSERT INTO app.document_client_access_privacy (document_id, privacy_reason, created_by)
  VALUES (doc_row.id, 'RESTORED_PRIVATE', actor_row.actor_user_id)
  ON CONFLICT ON CONSTRAINT document_client_access_privacy_pkey DO NOTHING;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_restored', 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('document_id', doc_row.id, 'previous_status', 'ARCHIVED', 'new_status', 'ACTIVE', 'client_visible', false));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_declare_document_replacement(
  p_actor_auth_subject uuid,
  p_superseded_document_id uuid,
  p_replacement_document_id uuid,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (superseded_document_id uuid, replacement_document_id uuid, created_at timestamptz)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  old_doc app.documents%ROWTYPE;
  new_doc app.documents%ROWTYPE;
  old_context record;
  new_context record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_superseded_document_id = p_replacement_document_id THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'A document cannot replace itself.';
  END IF;

  SELECT * INTO old_doc FROM app.documents WHERE id = p_superseded_document_id FOR UPDATE;
  SELECT * INTO new_doc FROM app.documents WHERE id = p_replacement_document_id FOR UPDATE;
  IF old_doc.id IS NULL OR new_doc.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document metadata is not available.';
  END IF;
  IF app.document_is_superseded(old_doc.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document already has a direct replacement.';
  END IF;
  IF EXISTS (SELECT 1 FROM app.document_replacements dr WHERE dr.replacement_document_id = new_doc.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Replacement document is already linked to another original.';
  END IF;
  IF old_doc.status <> 'ACTIVE' OR new_doc.status <> 'ACTIVE' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Replacement requires active finalized documents.';
  END IF;
  IF NOT app.document_is_finalized_from_clean_scan(new_doc.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Replacement document must be finalized from a clean scan.';
  END IF;
  IF app.document_replacement_would_cycle(old_doc.id, new_doc.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document replacement cycles are not allowed.';
  END IF;

  SELECT * INTO old_context FROM app.document_business_context(old_doc.id);
  SELECT * INTO new_context FROM app.document_business_context(new_doc.id);
  IF old_context.context_count IS DISTINCT FROM 1 OR new_context.context_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document replacement requires one unambiguous business context.';
  END IF;
  IF old_context.client_id IS NULL OR new_context.client_id IS NULL OR old_context.client_id IS DISTINCT FROM new_context.client_id THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document replacement requires matching Client context.';
  END IF;
  IF old_context.project_id IS DISTINCT FROM new_context.project_id THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document replacement requires matching Project context.';
  END IF;

  PERFORM set_config('app.document_lifecycle_context', 'owner_document_lifecycle_mutation', true);
  INSERT INTO app.document_replacements (superseded_document_id, replacement_document_id, created_by)
  VALUES (old_doc.id, new_doc.id, actor_row.actor_user_id)
  RETURNING document_replacements.superseded_document_id, document_replacements.replacement_document_id, document_replacements.created_at
  INTO superseded_document_id, replacement_document_id, created_at;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_replaced', 'document', old_doc.id, old_context.project_id, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('document_id', old_doc.id, 'replacement_document_id', new_doc.id, 'previous_lifecycle_state', 'current', 'new_lifecycle_state', 'superseded'));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_document_lifecycle_history(
  p_actor_auth_subject uuid,
  p_document_id uuid
)
RETURNS TABLE (
  document_id uuid,
  document_number text,
  status app.document_status,
  client_visible boolean,
  is_superseded boolean,
  superseded_by_document_id uuid,
  replaces_document_id uuid,
  uploaded_at timestamptz,
  archived_at timestamptz
)
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
  SELECT d.id, d.document_number::text, d.status, d.client_visible,
         dr_out.id IS NOT NULL,
         dr_out.replacement_document_id,
         dr_in.superseded_document_id,
         d.uploaded_at,
         d.archived_at
  FROM app.documents d
  LEFT JOIN app.document_replacements dr_out ON dr_out.superseded_document_id = d.id
  LEFT JOIN app.document_replacements dr_in ON dr_in.replacement_document_id = d.id
  WHERE d.id = p_document_id
     OR d.id IN (
       WITH RECURSIVE
       forward_chain(document_id) AS (
         SELECT p_document_id
         UNION
         SELECT dr.replacement_document_id FROM app.document_replacements dr JOIN forward_chain fc ON fc.document_id = dr.superseded_document_id
       ),
       backward_chain(document_id) AS (
         SELECT p_document_id
         UNION
         SELECT dr.superseded_document_id FROM app.document_replacements dr JOIN backward_chain bc ON bc.document_id = dr.replacement_document_id
       )
       SELECT fc.document_id FROM forward_chain fc
       UNION
       SELECT bc.document_id FROM backward_chain bc
     )
  ORDER BY d.uploaded_at, d.id;
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
    AND NOT app.document_is_superseded(d.id)
    AND NOT app.document_is_client_lifecycle_private(d.id)
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
  client_allowed boolean := false;
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
    IF client_row.id IS NULL OR doc_row.status <> 'ACTIVE' OR app.document_is_superseded(doc_row.id) OR app.document_is_client_lifecycle_private(doc_row.id) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;

    client_allowed := EXISTS (
      SELECT 1
      FROM app.document_links dl
      JOIN app.client_payments cp ON cp.id = dl.client_payment_id
      JOIN app.projects p ON p.id = cp.project_id
      WHERE dl.document_id = doc_row.id
        AND doc_row.document_type_code = 'BANK_TRANSFER_EVIDENCE'
        AND NOT doc_row.client_visible
        AND cp.is_client_submitted
        AND cp.submitted_by_client_user_id = client_row.portal_user_id
        AND cp.client_id = client_row.id
        AND p.client_id = client_row.id
        AND doc_row.uploaded_by = client_row.portal_user_id
    );

    IF NOT client_allowed AND doc_row.client_visible THEN
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
          OR (cp.client_id = client_row.id AND EXISTS (SELECT 1 FROM app.projects cpp WHERE cpp.id = cp.project_id AND cpp.client_id = client_row.id))
          OR (pr.client_id = client_row.id AND EXISTS (SELECT 1 FROM app.projects prp WHERE prp.id = pr.project_id AND prp.client_id = client_row.id))
        )
      ) AND NOT EXISTS (
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
        AND coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id, cp.client_id, pr.client_id) IS DISTINCT FROM client_row.id
      );
    END IF;

    IF NOT client_allowed THEN
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

CREATE OR REPLACE FUNCTION public.server_owner_restore_document_metadata(p_verified_owner_auth_subject uuid, p_document_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, status app.document_status, client_visible boolean, archived_at timestamptz, archived_by uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_restore_document_metadata(p_verified_owner_auth_subject, p_document_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_declare_document_replacement(p_verified_owner_auth_subject uuid, p_superseded_document_id uuid, p_replacement_document_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (superseded_document_id uuid, replacement_document_id uuid, created_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_declare_document_replacement(p_verified_owner_auth_subject, p_superseded_document_id, p_replacement_document_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_document_lifecycle_history(p_verified_owner_auth_subject uuid, p_document_id uuid)
RETURNS TABLE (document_id uuid, document_number text, status app.document_status, client_visible boolean, is_superseded boolean, superseded_by_document_id uuid, replaces_document_id uuid, uploaded_at timestamptz, archived_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_document_lifecycle_history(p_verified_owner_auth_subject, p_document_id);
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
    IF client_row.id IS NULL OR doc_row.status <> 'ACTIVE' OR NOT doc_row.client_visible OR app.document_is_superseded(doc_row.id) OR app.document_is_client_lifecycle_private(doc_row.id) THEN
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

COMMIT;
