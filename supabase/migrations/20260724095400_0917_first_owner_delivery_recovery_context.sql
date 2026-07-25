BEGIN;

CREATE OR REPLACE FUNCTION app.first_owner_delivery_context_for_service(
  p_owner_auth_subject uuid,
  p_normalized_email citext
)
RETURNS TABLE (
  owner_user_id uuid,
  auth_subject uuid,
  normalized_email text,
  account_status text,
  is_active boolean,
  invitation_id uuid,
  invitation_status text,
  expires_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM app.users AS u
    JOIN LATERAL (
      SELECT ui.status, ui.expires_at
      FROM app.user_invitations AS ui
      WHERE ui.invited_user_id = u.id
      ORDER BY ui.created_at DESC, ui.id DESC
      LIMIT 1
    ) AS latest_invitation ON true
    WHERE u.auth_subject = p_owner_auth_subject
      AND u.email = p_normalized_email
      AND u.user_type = 'STAFF'
      AND u.status = 'INVITED'
      AND NOT u.is_active
      AND latest_invitation.status = 'PENDING'
      AND latest_invitation.expires_at <= now()
      AND EXISTS (
        SELECT 1
        FROM app.user_profiles AS up
        WHERE up.user_id = u.id
          AND btrim(up.full_name) <> ''
      )
      AND EXISTS (
        SELECT 1
        FROM app.user_roles AS ur
        WHERE ur.user_id = u.id
          AND ur.role_code = 'owner_admin'
          AND ur.is_active
      )
      AND NOT EXISTS (
        SELECT 1
        FROM app.users AS other_u
        JOIN app.user_roles AS other_ur
          ON other_ur.user_id = other_u.id
        WHERE other_u.id <> u.id
          AND other_ur.role_code = 'owner_admin'
          AND other_ur.is_active
          AND other_u.status IN ('INVITED', 'ACTIVE')
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'First Owner invitation expired.';
  END IF;

  RETURN QUERY
  WITH candidate AS (
    SELECT
      u.id,
      u.auth_subject,
      u.email,
      u.status,
      u.is_active
    FROM app.users AS u
    WHERE u.auth_subject = p_owner_auth_subject
      AND u.email = p_normalized_email
      AND u.user_type = 'STAFF'
      AND u.status = 'INVITED'
      AND NOT u.is_active
      AND EXISTS (
        SELECT 1
        FROM app.user_profiles AS up
        WHERE up.user_id = u.id
          AND btrim(up.full_name) <> ''
      )
      AND EXISTS (
        SELECT 1
        FROM app.user_roles AS ur
        WHERE ur.user_id = u.id
          AND ur.role_code = 'owner_admin'
          AND ur.is_active
      )
      AND NOT EXISTS (
        SELECT 1
        FROM app.users AS other_u
        JOIN app.user_roles AS other_ur
          ON other_ur.user_id = other_u.id
        WHERE other_u.id <> u.id
          AND other_ur.role_code = 'owner_admin'
          AND other_ur.is_active
          AND other_u.status IN ('INVITED', 'ACTIVE')
      )
    LIMIT 1
  )
  SELECT
    c.id AS owner_user_id,
    c.auth_subject,
    c.email::text AS normalized_email,
    c.status::text AS account_status,
    c.is_active,
    latest_invitation.id AS invitation_id,
    latest_invitation.status::text AS invitation_status,
    latest_invitation.expires_at
  FROM candidate AS c
  JOIN LATERAL (
    SELECT ui.id, ui.status, ui.expires_at
    FROM app.user_invitations AS ui
    WHERE ui.invited_user_id = c.id
    ORDER BY ui.created_at DESC, ui.id DESC
    LIMIT 1
  ) AS latest_invitation ON true
  WHERE latest_invitation.status = 'PENDING'
    AND latest_invitation.expires_at > now();
END;
$function$;

CREATE OR REPLACE FUNCTION public.server_first_owner_delivery_context(
  p_owner_auth_subject uuid,
  p_normalized_email citext
)
RETURNS TABLE (
  owner_user_id uuid,
  auth_subject uuid,
  normalized_email text,
  account_status text,
  is_active boolean,
  invitation_id uuid,
  invitation_status text,
  expires_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT *
  FROM app.first_owner_delivery_context_for_service(
    p_owner_auth_subject,
    p_normalized_email
  );
$function$;

REVOKE ALL ON FUNCTION app.first_owner_delivery_context_for_service(uuid, citext) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_first_owner_delivery_context(uuid, citext) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_first_owner_delivery_context(uuid, citext) TO service_role;

COMMIT;
