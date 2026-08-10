BEGIN;

CREATE OR REPLACE FUNCTION app.owner_admin_document_projection(
  p_actor_auth_subject uuid,
  p_document_id uuid DEFAULT NULL,
  p_project_id uuid DEFAULT NULL,
  p_document_type_code text DEFAULT NULL,
  p_client_visible boolean DEFAULT NULL,
  p_status app.document_status DEFAULT NULL,
  p_context_type text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_type_code text,
  status app.document_status,
  client_visible boolean,
  uploaded_at timestamptz,
  archived_at timestamptz,
  client_id uuid,
  project_id uuid,
  task_id uuid,
  progress_update_id uuid,
  client_payment_id uuid,
  superseded_by_document_id uuid,
  replaces_document_id uuid,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  bounded_limit integer;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;
  IF p_context_type IS NOT NULL AND p_context_type NOT IN ('client','project','task','progress_update','client_payment') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document context filter is invalid.';
  END IF;
  bounded_limit := p_limit;

  RETURN QUERY
  WITH link_summary AS (
    SELECT
      dl.document_id,
      CASE WHEN count(DISTINCT coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id, cp.client_id)) FILTER (WHERE coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id, cp.client_id) IS NOT NULL) = 1
        THEN (array_agg(DISTINCT coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id, cp.client_id) ORDER BY coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id, cp.client_id)) FILTER (WHERE coalesce(dl.client_id, p.client_id, tp.client_id, pp.client_id, cp.client_id) IS NOT NULL))[1] END AS client_id,
      CASE WHEN count(DISTINCT coalesce(dl.project_id, t.project_id, pu.project_id, cp.project_id)) FILTER (WHERE coalesce(dl.project_id, t.project_id, pu.project_id, cp.project_id) IS NOT NULL) = 1
        THEN (array_agg(DISTINCT coalesce(dl.project_id, t.project_id, pu.project_id, cp.project_id) ORDER BY coalesce(dl.project_id, t.project_id, pu.project_id, cp.project_id)) FILTER (WHERE coalesce(dl.project_id, t.project_id, pu.project_id, cp.project_id) IS NOT NULL))[1] END AS project_id,
      CASE WHEN count(DISTINCT dl.task_id) FILTER (WHERE dl.task_id IS NOT NULL) = 1 THEN (array_agg(DISTINCT dl.task_id ORDER BY dl.task_id) FILTER (WHERE dl.task_id IS NOT NULL))[1] END AS task_id,
      CASE WHEN count(DISTINCT dl.progress_update_id) FILTER (WHERE dl.progress_update_id IS NOT NULL) = 1 THEN (array_agg(DISTINCT dl.progress_update_id ORDER BY dl.progress_update_id) FILTER (WHERE dl.progress_update_id IS NOT NULL))[1] END AS progress_update_id,
      CASE WHEN count(DISTINCT dl.client_payment_id) FILTER (WHERE dl.client_payment_id IS NOT NULL) = 1 THEN (array_agg(DISTINCT dl.client_payment_id ORDER BY dl.client_payment_id) FILTER (WHERE dl.client_payment_id IS NOT NULL))[1] END AS client_payment_id,
      bool_or(dl.client_id IS NOT NULL) AS has_client_link,
      bool_or(dl.project_id IS NOT NULL) AS has_project_link,
      bool_or(dl.task_id IS NOT NULL) AS has_task_link,
      bool_or(dl.progress_update_id IS NOT NULL) AS has_progress_update_link,
      bool_or(dl.client_payment_id IS NOT NULL) AS has_client_payment_link
    FROM app.document_links dl
    LEFT JOIN app.projects p ON p.id = dl.project_id
    LEFT JOIN app.tasks t ON t.id = dl.task_id
    LEFT JOIN app.projects tp ON tp.id = t.project_id
    LEFT JOIN app.progress_updates pu ON pu.id = dl.progress_update_id
    LEFT JOIN app.projects pp ON pp.id = pu.project_id
    LEFT JOIN app.client_payments cp ON cp.id = dl.client_payment_id
    GROUP BY dl.document_id
  )
  SELECT
    d.id,
    d.document_number::text,
    d.original_file_name::text,
    d.mime_type::text,
    d.file_size_bytes,
    d.document_type_code::text,
    d.status,
    d.client_visible,
    d.uploaded_at,
    d.archived_at,
    ls.client_id,
    ls.project_id,
    ls.task_id,
    ls.progress_update_id,
    ls.client_payment_id,
    dr_out.replacement_document_id,
    dr_in.superseded_document_id,
    did.processing_status::text,
    coalesce(did.thumbnail_storage_object_key IS NOT NULL AND did.processing_status = 'READY', false),
    coalesce(did.preview_storage_object_key IS NOT NULL AND did.processing_status = 'READY', false)
  FROM app.documents d
  LEFT JOIN link_summary ls ON ls.document_id = d.id
  LEFT JOIN app.document_replacements dr_out ON dr_out.superseded_document_id = d.id
  LEFT JOIN app.document_replacements dr_in ON dr_in.replacement_document_id = d.id
  LEFT JOIN app.document_image_derivatives did ON did.document_id = d.id
  WHERE (p_document_id IS NULL OR d.id = p_document_id)
    AND (p_project_id IS NULL OR ls.project_id = p_project_id)
    AND (p_document_type_code IS NULL OR d.document_type_code = p_document_type_code)
    AND (p_client_visible IS NULL OR d.client_visible = p_client_visible)
    AND (p_status IS NULL OR d.status = p_status)
    AND (
      p_context_type IS NULL
      OR (p_context_type = 'client' AND ls.has_client_link)
      OR (p_context_type = 'project' AND ls.has_project_link)
      OR (p_context_type = 'task' AND ls.has_task_link)
      OR (p_context_type = 'progress_update' AND ls.has_progress_update_link)
      OR (p_context_type = 'client_payment' AND ls.has_client_payment_link)
    )
  ORDER BY d.uploaded_at DESC, d.id DESC
  LIMIT bounded_limit OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.owner_admin_document_list(
  p_project_id uuid DEFAULT NULL,
  p_document_type_code text DEFAULT NULL,
  p_client_visible boolean DEFAULT NULL,
  p_status app.document_status DEFAULT NULL,
  p_context_type text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_type_code text,
  status app.document_status,
  client_visible boolean,
  uploaded_at timestamptz,
  archived_at timestamptz,
  client_id uuid,
  project_id uuid,
  task_id uuid,
  progress_update_id uuid,
  client_payment_id uuid,
  superseded_by_document_id uuid,
  replaces_document_id uuid,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_admin_document_projection(auth.uid(), NULL, p_project_id, p_document_type_code, p_client_visible, p_status, p_context_type, p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.owner_admin_document_detail(p_document_id uuid)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_type_code text,
  status app.document_status,
  client_visible boolean,
  uploaded_at timestamptz,
  archived_at timestamptz,
  client_id uuid,
  project_id uuid,
  task_id uuid,
  progress_update_id uuid,
  client_payment_id uuid,
  superseded_by_document_id uuid,
  replaces_document_id uuid,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN QUERY
  SELECT * FROM app.owner_admin_document_projection(auth.uid(), p_document_id, NULL, NULL, NULL, NULL, NULL, 1, 0);
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document metadata is not available.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION public.owner_admin_archive_document(p_document_id uuid)
RETURNS TABLE (document_id uuid, status app.document_status, archived_at timestamptz, archived_by uuid)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_archive_document_metadata(auth.uid(), p_document_id);
$function$;

CREATE OR REPLACE FUNCTION public.owner_admin_restore_document(p_document_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, status app.document_status, client_visible boolean, archived_at timestamptz, archived_by uuid)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_restore_document_metadata(auth.uid(), p_document_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.owner_admin_replace_document(p_superseded_document_id uuid, p_replacement_document_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (superseded_document_id uuid, replacement_document_id uuid, created_at timestamptz)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_declare_document_replacement(auth.uid(), p_superseded_document_id, p_replacement_document_id, p_request_identifier);
$function$;

REVOKE ALL ON FUNCTION app.owner_admin_document_projection(uuid, uuid, uuid, text, boolean, app.document_status, text, integer, integer) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.owner_admin_document_list(uuid, text, boolean, app.document_status, text, integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.owner_admin_document_detail(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.owner_admin_archive_document(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.owner_admin_restore_document(uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.owner_admin_replace_document(uuid, uuid, text) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.owner_admin_document_list(uuid, text, boolean, app.document_status, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.owner_admin_document_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.owner_admin_archive_document(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.owner_admin_restore_document(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.owner_admin_replace_document(uuid, uuid, text) TO authenticated;

COMMIT;
