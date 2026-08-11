BEGIN;

CREATE OR REPLACE FUNCTION app.current_client_photograph_list_for_authenticated_user(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_type_code text,
  uploaded_at timestamptz,
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
  SELECT DISTINCT
    d.id,
    d.document_number::text,
    d.original_file_name::text,
    d.mime_type::text,
    d.file_size_bytes,
    d.document_type_code::text,
    d.uploaded_at,
    did.processing_status::text,
    coalesce(did.processing_status = 'READY' AND did.thumbnail_file_size_bytes IS NOT NULL, false),
    coalesce(did.processing_status = 'READY' AND did.preview_file_size_bytes IS NOT NULL, false)
  FROM app.documents AS d
  INNER JOIN app.document_links AS dl ON dl.document_id = d.id
  LEFT JOIN app.projects AS p ON p.id = dl.project_id
  LEFT JOIN app.tasks AS t ON t.id = dl.task_id
  LEFT JOIN app.progress_updates AS pu ON pu.id = dl.progress_update_id
  LEFT JOIN app.projects AS tp ON tp.id = t.project_id
  LEFT JOIN app.projects AS pp ON pp.id = pu.project_id
  LEFT JOIN app.document_image_derivatives AS did ON did.document_id = d.id
  WHERE d.status = 'ACTIVE'
    AND d.client_visible
    AND NOT app.document_is_superseded(d.id)
    AND NOT app.document_is_client_lifecycle_private(d.id)
    AND app.document_image_is_eligible(d.id)
    AND app.document_image_client_parent_visible(d.id, client_row.id)
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

CREATE OR REPLACE FUNCTION public.current_client_photograph_list(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_type_code text,
  uploaded_at timestamptz,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_photograph_list_for_authenticated_user(p_limit, p_offset);
$function$;

REVOKE ALL ON FUNCTION app.current_client_photograph_list_for_authenticated_user(integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.current_client_photograph_list(integer, integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.current_client_photograph_list(integer, integer) TO authenticated;

COMMIT;
