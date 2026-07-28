BEGIN;

CREATE OR REPLACE FUNCTION app.document_safe_row(p_document_id uuid)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  sha256_hash bytea,
  document_type_code text,
  status app.document_status,
  client_visible boolean,
  notes text,
  uploaded_at timestamptz,
  uploaded_by uuid,
  archived_at timestamptz,
  archived_by uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT d.id, d.document_number::text, d.original_file_name::text, d.mime_type::text, d.file_size_bytes, d.sha256_hash,
         d.document_type_code::text, d.status, d.client_visible, d.notes, d.uploaded_at, d.uploaded_by, d.archived_at, d.archived_by
  FROM app.documents AS d
  WHERE d.id = p_document_id;
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
DECLARE
  actor_row record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_document_type_code !~ '^[A-Z][A-Z0-9_]{0,49}$' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document type code must be uppercase and stable.';
  END IF;

  PERFORM set_config('app.document_metadata_context', 'owner_metadata_mutation', true);
  INSERT INTO app.documents (
    storage_bucket,
    storage_object_key,
    original_file_name,
    mime_type,
    file_size_bytes,
    sha256_hash,
    document_type_code,
    client_visible,
    notes,
    uploaded_by
  )
  VALUES (
    p_storage_bucket,
    p_storage_object_key,
    p_original_file_name,
    p_mime_type,
    p_file_size_bytes,
    p_sha256_hash,
    p_document_type_code,
    coalesce(p_client_visible, false),
    p_notes,
    actor_row.actor_user_id
  )
  RETURNING id, documents.document_number::text INTO document_id, document_number;
  RETURN NEXT;
END
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
  workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  PERFORM set_config('app.document_metadata_context', 'owner_metadata_mutation', true);
  UPDATE app.documents AS d
  SET status = 'ARCHIVED',
      archived_at = coalesce(d.archived_at, workflow_at),
      archived_by = coalesce(d.archived_by, actor_row.actor_user_id)
  WHERE d.id = p_document_id
  RETURNING d.id, d.status, d.archived_at, d.archived_by
  INTO document_id, status, archived_at, archived_by;
  IF document_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document metadata is not available.';
  END IF;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_link_document(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_client_id uuid DEFAULT NULL,
  p_project_id uuid DEFAULT NULL,
  p_task_id uuid DEFAULT NULL,
  p_progress_update_id uuid DEFAULT NULL,
  p_client_payment_id uuid DEFAULT NULL,
  p_payment_request_id uuid DEFAULT NULL,
  p_project_expense_id uuid DEFAULT NULL,
  p_currency_exchange_id uuid DEFAULT NULL
)
RETURNS TABLE (document_link_id uuid)
LANGUAGE plpgsql
VOLATILE
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
  IF num_nonnulls(p_client_id, p_project_id, p_task_id, p_progress_update_id, p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id) <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document link requires exactly one target.';
  END IF;
  IF p_client_payment_id IS NOT NULL OR p_payment_request_id IS NOT NULL OR p_project_expense_id IS NOT NULL OR p_currency_exchange_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Finance document link targets are not enabled.';
  END IF;

  INSERT INTO app.document_links (
    document_id,
    client_id,
    project_id,
    task_id,
    progress_update_id,
    created_by
  )
  VALUES (
    p_document_id,
    p_client_id,
    p_project_id,
    p_task_id,
    p_progress_update_id,
    actor_row.actor_user_id
  )
  RETURNING id INTO document_link_id;
  RETURN NEXT;
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
  ORDER BY d.uploaded_at DESC, d.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.current_client_document_list(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, document_number text, original_file_name text, mime_type text, file_size_bytes bigint, document_type_code text, uploaded_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_document_list_for_authenticated_user(p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_document_metadata(p_verified_owner_auth_subject uuid, p_storage_bucket text, p_storage_object_key text, p_original_file_name text, p_mime_type text, p_file_size_bytes bigint, p_sha256_hash bytea, p_document_type_code varchar(50), p_client_visible boolean DEFAULT false, p_notes text DEFAULT NULL)
RETURNS TABLE (document_id uuid, document_number text)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_create_document_metadata(p_verified_owner_auth_subject, p_storage_bucket, p_storage_object_key, p_original_file_name, p_mime_type, p_file_size_bytes, p_sha256_hash, p_document_type_code, p_client_visible, p_notes);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_archive_document_metadata(p_verified_owner_auth_subject uuid, p_document_id uuid)
RETURNS TABLE (document_id uuid, status app.document_status, archived_at timestamptz, archived_by uuid)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_archive_document_metadata(p_verified_owner_auth_subject, p_document_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_link_document(p_verified_owner_auth_subject uuid, p_document_id uuid, p_client_id uuid DEFAULT NULL, p_project_id uuid DEFAULT NULL, p_task_id uuid DEFAULT NULL, p_progress_update_id uuid DEFAULT NULL, p_client_payment_id uuid DEFAULT NULL, p_payment_request_id uuid DEFAULT NULL, p_project_expense_id uuid DEFAULT NULL, p_currency_exchange_id uuid DEFAULT NULL)
RETURNS TABLE (document_link_id uuid)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_link_document(p_verified_owner_auth_subject, p_document_id, p_client_id, p_project_id, p_task_id, p_progress_update_id, p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id);
$function$;

COMMIT;
