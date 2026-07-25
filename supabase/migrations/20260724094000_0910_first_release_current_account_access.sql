BEGIN;

CREATE OR REPLACE FUNCTION public.current_account()
RETURNS TABLE (
  application_user_id uuid,
  account_status text,
  is_active boolean,
  access_allowed boolean,
  user_type text,
  full_name varchar(160),
  job_title varchar(120),
  active_role_codes varchar(40)[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH current_user_row AS (
    SELECT
      u.id,
      u.status,
      u.is_active,
      u.user_type
    FROM app.users AS u
    WHERE u.auth_subject = auth.uid()
  ),
  active_role_summary AS (
    SELECT
      ur.user_id,
      bool_or(ur.role_code = 'owner_admin') AS has_owner_admin,
      bool_or(ur.role_code = 'client') AS has_client_role,
      bool_or(ur.role_code IN ('project_manager', 'accountant', 'site_supervisor')) AS has_reserved_staff_role,
      bool_or(r.is_staff_role) AS has_any_staff_role
    FROM app.user_roles AS ur
    INNER JOIN app.roles AS r
      ON r.code = ur.role_code
    INNER JOIN current_user_row AS u
      ON u.id = ur.user_id
    WHERE ur.is_active
      AND r.is_active
      AND ur.role_code IN (
        'owner_admin',
        'project_manager',
        'accountant',
        'site_supervisor',
        'client'
      )
    GROUP BY ur.user_id
  ),
  current_account_row AS (
    SELECT
      u.id,
      u.status,
      u.is_active,
      u.user_type,
      up.full_name,
      up.job_title,
      CASE
        WHEN u.status = 'ACTIVE'
          AND u.is_active
          AND u.user_type = 'STAFF'
          AND coalesce(ar.has_owner_admin, false)
          AND NOT coalesce(ar.has_client_role, false)
          THEN true
        WHEN u.status = 'ACTIVE'
          AND u.is_active
          AND u.user_type = 'CLIENT'
          AND coalesce(ar.has_client_role, false)
          AND NOT coalesce(ar.has_any_staff_role, false)
          THEN true
        ELSE false
      END AS access_allowed,
      CASE
        WHEN u.status = 'ACTIVE'
          AND u.is_active
          AND u.user_type = 'STAFF'
          AND coalesce(ar.has_owner_admin, false)
          AND NOT coalesce(ar.has_client_role, false)
          THEN ARRAY['owner_admin']::varchar(40)[]
        WHEN u.status = 'ACTIVE'
          AND u.is_active
          AND u.user_type = 'CLIENT'
          AND coalesce(ar.has_client_role, false)
          AND NOT coalesce(ar.has_any_staff_role, false)
          THEN ARRAY['client']::varchar(40)[]
        ELSE ARRAY[]::varchar(40)[]
      END AS usable_role_codes
    FROM current_user_row AS u
    LEFT JOIN app.user_profiles AS up
      ON up.user_id = u.id
    LEFT JOIN active_role_summary AS ar
      ON ar.user_id = u.id
  )
  SELECT
    u.id AS application_user_id,
    u.status::text AS account_status,
    u.is_active,
    u.access_allowed,
    u.user_type::text AS user_type,
    CASE
      WHEN u.status = 'ACTIVE' AND u.is_active THEN u.full_name
      ELSE NULL::varchar(160)
    END AS full_name,
    CASE
      WHEN u.status = 'ACTIVE' AND u.is_active THEN u.job_title
      ELSE NULL::varchar(120)
    END AS job_title,
    coalesce(u.usable_role_codes, ARRAY[]::varchar(40)[]) AS active_role_codes
  FROM current_account_row AS u;
$function$;

REVOKE ALL ON FUNCTION public.current_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.current_account() TO authenticated;

REVOKE USAGE ON SCHEMA app FROM PUBLIC, anon, authenticated;

REVOKE ALL ON app.users FROM anon, authenticated;
REVOKE ALL ON app.user_profiles FROM anon, authenticated;
REVOKE ALL ON app.user_roles FROM anon, authenticated;
REVOKE ALL ON app.roles FROM anon, authenticated;

COMMIT;
