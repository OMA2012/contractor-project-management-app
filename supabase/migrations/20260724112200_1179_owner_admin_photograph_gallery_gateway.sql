BEGIN;

CREATE OR REPLACE FUNCTION app.owner_admin_photograph_projection(
  p_actor_auth_subject uuid,
  p_document_type_code text,
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
  client_visible boolean,
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
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  IF p_document_type_code IS NULL OR p_document_type_code NOT IN ('PROGRESS_PHOTOGRAPH','TASK_ATTACHMENT') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Photograph category is invalid.';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
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
    d.client_visible,
    did.processing_status::text,
    coalesce(did.processing_status = 'READY' AND did.thumbnail_storage_object_key IS NOT NULL, false),
    coalesce(did.processing_status = 'READY' AND did.preview_storage_object_key IS NOT NULL, false)
  FROM app.documents AS d
  LEFT JOIN app.document_image_derivatives AS did ON did.document_id = d.id
  WHERE d.document_type_code = p_document_type_code
    AND d.status = 'ACTIVE'
    AND NOT app.document_is_superseded(d.id)
    AND app.document_image_is_eligible(d.id)
  ORDER BY d.uploaded_at DESC, d.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.owner_admin_photograph_list(
  p_document_type_code text,
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
  client_visible boolean,
  photograph_processing_status text,
  thumbnail_available boolean,
  preview_available boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_admin_photograph_projection(auth.uid(), p_document_type_code, p_limit, p_offset);
$function$;

REVOKE ALL ON FUNCTION app.owner_admin_photograph_projection(uuid, text, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.owner_admin_photograph_list(text, integer, integer) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.owner_admin_photograph_list(text, integer, integer) TO authenticated;

COMMIT;
