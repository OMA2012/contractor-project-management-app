BEGIN;

CREATE OR REPLACE FUNCTION app.client_identity_context_for_service(
  p_verified_owner_auth_subject uuid,
  p_client_user_id uuid
)
RETURNS TABLE (
  client_user_id uuid,
  auth_subject uuid,
  normalized_email text,
  account_status text,
  is_active boolean,
  latest_invitation_id uuid,
  latest_invitation_status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH authorized_actor AS (
    SELECT 1
    FROM app.require_active_owner_admin(p_verified_owner_auth_subject) AS owner_gate
    LIMIT 1
  ),
  target_client AS (
    SELECT
      u.id,
      u.auth_subject,
      u.email,
      u.status,
      u.is_active
    FROM app.users AS u
    WHERE u.id = p_client_user_id
      AND u.user_type = 'CLIENT'
      AND EXISTS (SELECT 1 FROM authorized_actor)
  )
  SELECT
    target_client.id AS client_user_id,
    target_client.auth_subject,
    target_client.email::text AS normalized_email,
    target_client.status::text AS account_status,
    target_client.is_active,
    latest_invitation.id AS latest_invitation_id,
    latest_invitation.status::text AS latest_invitation_status
  FROM target_client
  LEFT JOIN LATERAL (
    SELECT ui.id, ui.status
    FROM app.user_invitations AS ui
    WHERE ui.invited_user_id = target_client.id
    ORDER BY ui.created_at DESC, ui.id DESC
    LIMIT 1
  ) AS latest_invitation ON true;
$function$;

CREATE OR REPLACE FUNCTION public.server_client_identity_context(
  p_verified_owner_auth_subject uuid,
  p_client_user_id uuid
)
RETURNS TABLE (
  client_user_id uuid,
  auth_subject uuid,
  normalized_email text,
  account_status text,
  is_active boolean,
  latest_invitation_id uuid,
  latest_invitation_status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT *
  FROM app.client_identity_context_for_service(
    p_verified_owner_auth_subject,
    p_client_user_id
  );
$function$;

REVOKE ALL ON FUNCTION app.client_identity_context_for_service(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_client_identity_context(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_client_identity_context(uuid, uuid) TO service_role;

COMMIT;
