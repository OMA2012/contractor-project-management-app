BEGIN;

CREATE OR REPLACE FUNCTION app.owner_admin_context_file_projection(
  p_actor_auth_subject uuid,
  p_context_type text,
  p_context_id uuid,
  p_content_kind text,
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
  uploaded_at timestamptz,
  related_context_type text,
  project_number text,
  project_name text,
  task_title text,
  progress_update_title text,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean,
  client_visible boolean
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
  IF p_context_type IS NULL OR p_context_type NOT IN ('PROJECT','TASK','PROGRESS_UPDATE') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Context type is invalid.';
  END IF;
  IF p_context_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Context identifier is required.';
  END IF;
  IF p_content_kind IS NULL OR p_content_kind NOT IN ('DOCUMENT','PHOTOGRAPH') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Content kind is invalid.';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;

  RETURN QUERY
  WITH context_links AS (
    SELECT DISTINCT
      dl.document_id,
      CASE
        WHEN dl.project_id IS NOT NULL THEN 'PROJECT'
        WHEN dl.task_id IS NOT NULL THEN 'TASK'
        WHEN dl.progress_update_id IS NOT NULL THEN 'PROGRESS_UPDATE'
      END AS related_context_type,
      coalesce(dl.project_id, t.project_id, pu.project_id) AS project_id,
      dl.task_id,
      dl.progress_update_id
    FROM app.document_links AS dl
    LEFT JOIN app.tasks AS t ON t.id = dl.task_id
    LEFT JOIN app.progress_updates AS pu ON pu.id = dl.progress_update_id
    WHERE (
        p_context_type = 'PROJECT'
        AND (
          dl.project_id = p_context_id
          OR t.project_id = p_context_id
          OR pu.project_id = p_context_id
        )
      )
      OR (p_context_type = 'TASK' AND dl.task_id = p_context_id AND t.id IS NOT NULL)
      OR (p_context_type = 'PROGRESS_UPDATE' AND dl.progress_update_id = p_context_id AND pu.id IS NOT NULL)
  )
  SELECT DISTINCT
    d.id,
    d.document_number::text,
    d.original_file_name::text,
    d.mime_type::text,
    d.file_size_bytes,
    d.document_type_code::text,
    d.uploaded_at,
    cl.related_context_type,
    p.project_number::text,
    p.name::text,
    CASE WHEN cl.related_context_type = 'TASK' THEN t.title::text ELSE NULL::text END,
    CASE WHEN cl.related_context_type = 'PROGRESS_UPDATE' THEN pu.title::text ELSE NULL::text END,
    did.processing_status::text,
    coalesce(did.processing_status = 'READY' AND did.thumbnail_storage_object_key IS NOT NULL, false),
    coalesce(did.processing_status = 'READY' AND did.preview_storage_object_key IS NOT NULL, false),
    d.client_visible
  FROM context_links AS cl
  JOIN app.documents AS d ON d.id = cl.document_id
  JOIN app.projects AS p ON p.id = cl.project_id
  LEFT JOIN app.tasks AS t ON t.id = cl.task_id AND t.project_id = p.id
  LEFT JOIN app.progress_updates AS pu ON pu.id = cl.progress_update_id AND pu.project_id = p.id
  LEFT JOIN app.document_image_derivatives AS did ON did.document_id = d.id
  WHERE d.status = 'ACTIVE'
    AND NOT app.document_is_superseded(d.id)
    AND p.archived_at IS NULL
    AND (
      (p_context_type = 'PROJECT' AND p.id = p_context_id)
      OR (p_context_type = 'TASK' AND t.id = p_context_id)
      OR (p_context_type = 'PROGRESS_UPDATE' AND pu.id = p_context_id)
    )
    AND (
      (p_content_kind = 'PHOTOGRAPH' AND app.document_image_is_eligible(d.id))
      OR (p_content_kind = 'DOCUMENT' AND NOT app.document_image_is_eligible(d.id))
    )
  ORDER BY d.uploaded_at DESC, d.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_context_file_projection(
  p_context_type text,
  p_context_id uuid,
  p_content_kind text,
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
  uploaded_at timestamptz,
  related_context_type text,
  project_number text,
  project_name text,
  task_title text,
  progress_update_title text,
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
  IF p_context_type IS NULL OR p_context_type NOT IN ('PROJECT','TASK','PROGRESS_UPDATE') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Context type is invalid.';
  END IF;
  IF p_context_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Context identifier is required.';
  END IF;
  IF p_content_kind IS NULL OR p_content_kind NOT IN ('DOCUMENT','PHOTOGRAPH') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Content kind is invalid.';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;

  SELECT c.* INTO client_row
  FROM app.clients AS c
  INNER JOIN app.users AS u ON u.id = c.portal_user_id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
    AND NOT EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      INNER JOIN app.roles AS r ON r.code = ur.role_code
      WHERE ur.user_id = u.id AND ur.is_active AND r.is_staff_role
    );
  IF client_row.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH context_links AS (
    SELECT DISTINCT
      dl.document_id,
      CASE
        WHEN dl.project_id IS NOT NULL THEN 'PROJECT'
        WHEN dl.task_id IS NOT NULL THEN 'TASK'
        WHEN dl.progress_update_id IS NOT NULL THEN 'PROGRESS_UPDATE'
      END AS related_context_type,
      coalesce(dl.project_id, t.project_id, pu.project_id) AS project_id,
      dl.task_id,
      dl.progress_update_id
    FROM app.document_links AS dl
    LEFT JOIN app.tasks AS t ON t.id = dl.task_id
    LEFT JOIN app.progress_updates AS pu ON pu.id = dl.progress_update_id
    WHERE (
        p_context_type = 'PROJECT'
        AND (
          dl.project_id = p_context_id
          OR t.project_id = p_context_id
          OR pu.project_id = p_context_id
        )
      )
      OR (p_context_type = 'TASK' AND dl.task_id = p_context_id AND t.id IS NOT NULL)
      OR (p_context_type = 'PROGRESS_UPDATE' AND dl.progress_update_id = p_context_id AND pu.id IS NOT NULL)
  )
  SELECT DISTINCT
    d.id,
    d.document_number::text,
    d.original_file_name::text,
    d.mime_type::text,
    d.file_size_bytes,
    d.document_type_code::text,
    d.uploaded_at,
    cl.related_context_type,
    p.project_number::text,
    p.name::text,
    CASE WHEN cl.related_context_type = 'TASK' THEN t.title::text ELSE NULL::text END,
    CASE WHEN cl.related_context_type = 'PROGRESS_UPDATE' THEN pu.title::text ELSE NULL::text END,
    did.processing_status::text,
    coalesce(did.processing_status = 'READY' AND did.thumbnail_file_size_bytes IS NOT NULL, false),
    coalesce(did.processing_status = 'READY' AND did.preview_file_size_bytes IS NOT NULL, false)
  FROM context_links AS cl
  JOIN app.documents AS d ON d.id = cl.document_id
  JOIN app.projects AS p ON p.id = cl.project_id
  LEFT JOIN app.tasks AS t ON t.id = cl.task_id AND t.project_id = p.id
  LEFT JOIN app.progress_updates AS pu ON pu.id = cl.progress_update_id AND pu.project_id = p.id
  LEFT JOIN app.document_image_derivatives AS did ON did.document_id = d.id
  WHERE p.client_id = client_row.id
    AND p.archived_at IS NULL
    AND d.status = 'ACTIVE'
    AND d.client_visible
    AND NOT app.document_is_superseded(d.id)
    AND NOT app.document_is_client_lifecycle_private(d.id)
    AND app.document_image_client_parent_visible(d.id, client_row.id)
    AND EXISTS (SELECT 1 FROM app.current_client_project_record_for_authenticated_user(p.id))
    AND (
      (cl.related_context_type = 'PROJECT' AND EXISTS (SELECT 1 FROM app.current_client_project_record_for_authenticated_user(p.id)))
      OR (cl.related_context_type = 'TASK' AND EXISTS (SELECT 1 FROM app.current_client_project_task_for_authenticated_user(t.id)))
      OR (cl.related_context_type = 'PROGRESS_UPDATE' AND EXISTS (SELECT 1 FROM app.current_client_progress_update_detail_for_authenticated_user(pu.id)))
    )
    AND (
      (p_context_type = 'PROJECT' AND p.id = p_context_id)
      OR (p_context_type = 'TASK' AND t.id = p_context_id)
      OR (p_context_type = 'PROGRESS_UPDATE' AND pu.id = p_context_id)
    )
    AND (
      (p_content_kind = 'PHOTOGRAPH' AND app.document_image_is_eligible(d.id))
      OR (p_content_kind = 'DOCUMENT' AND NOT app.document_image_is_eligible(d.id))
    )
  ORDER BY d.uploaded_at DESC, d.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.owner_admin_context_file_list(
  p_context_type text,
  p_context_id uuid,
  p_content_kind text,
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
  uploaded_at timestamptz,
  related_context_type text,
  project_number text,
  project_name text,
  task_title text,
  progress_update_title text,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean,
  client_visible boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_admin_context_file_projection(auth.uid(), p_context_type, p_context_id, p_content_kind, p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_context_file_list(
  p_context_type text,
  p_context_id uuid,
  p_content_kind text,
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
  uploaded_at timestamptz,
  related_context_type text,
  project_number text,
  project_name text,
  task_title text,
  progress_update_title text,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_context_file_projection(p_context_type, p_context_id, p_content_kind, p_limit, p_offset);
$function$;

REVOKE ALL ON FUNCTION app.owner_admin_context_file_projection(uuid, text, uuid, text, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_context_file_projection(text, uuid, text, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.owner_admin_context_file_list(text, uuid, text, integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_context_file_list(text, uuid, text, integer, integer) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.owner_admin_context_file_list(text, uuid, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_context_file_list(text, uuid, text, integer, integer) TO authenticated;

COMMIT;
