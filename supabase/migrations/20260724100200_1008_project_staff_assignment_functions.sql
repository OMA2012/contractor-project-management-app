BEGIN;

CREATE OR REPLACE FUNCTION app.assert_project_staff_assignment_role(p_assignment_role_code varchar)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_assignment_role_code NOT IN ('project_manager', 'site_supervisor') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment role is not allowed.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.assert_project_staff_assignment_target(
  p_actor_user_id uuid,
  p_user_id uuid,
  p_assignment_role_code varchar
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM app.assert_project_staff_assignment_role(p_assignment_role_code);

  IF p_user_id IS NULL OR p_user_id = p_actor_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app.users AS u
    INNER JOIN app.user_roles AS ur
      ON ur.user_id = u.id
     AND ur.role_code = p_assignment_role_code
     AND ur.is_active
    INNER JOIN app.roles AS r
      ON r.code = ur.role_code
     AND r.is_active
     AND r.is_staff_role
    WHERE u.id = p_user_id
      AND u.user_type = 'STAFF'
      AND u.status = 'ACTIVE'
      AND u.is_active
      AND ur.role_code IN ('project_manager', 'site_supervisor')
      AND NOT EXISTS (
        SELECT 1
        FROM app.user_roles AS client_role
        WHERE client_role.user_id = u.id
          AND client_role.role_code = 'client'
          AND client_role.is_active
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.create_project_staff_assignment(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_user_id uuid,
  p_assignment_role_code varchar,
  p_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  assignment_id uuid,
  project_id uuid,
  user_id uuid,
  assignment_role_code text,
  status text,
  assigned_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  project_row app.projects%ROWTYPE;
  normalized_notes text := app.normalize_project_optional_text(p_notes, 4000);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  PERFORM app.assert_project_staff_assignment_target(actor_row.actor_user_id, p_user_id, p_assignment_role_code);

  SELECT * INTO project_row
  FROM app.projects AS p
  WHERE p.id = p_project_id
  FOR UPDATE;

  IF project_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record not available.';
  END IF;
  IF project_row.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED', 'ACTIVE', 'ON_HOLD') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment is not allowed in this status.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app.project_staff_assignments AS psa
    WHERE psa.project_id = p_project_id
      AND psa.user_id = p_user_id
      AND psa.assignment_role_code = p_assignment_role_code
      AND psa.status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Project staff assignment already exists.';
  END IF;

  INSERT INTO app.project_staff_assignments (
    project_id,
    user_id,
    assignment_role_code,
    notes,
    assigned_by
  )
  VALUES (
    p_project_id,
    p_user_id,
    p_assignment_role_code,
    normalized_notes,
    actor_row.actor_user_id
  )
  RETURNING
    id,
    app.project_staff_assignments.project_id,
    app.project_staff_assignments.user_id,
    app.project_staff_assignments.assignment_role_code::text,
    app.project_staff_assignments.status::text,
    app.project_staff_assignments.assigned_at
  INTO assignment_id, project_id, user_id, assignment_role_code, status, assigned_at;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'project_staff_assignment_created',
    'project_staff_assignment',
    assignment_id,
    project_id,
    'success',
    '{}'::jsonb,
    jsonb_build_object(
      'project_id', project_id,
      'assignment_role_code', assignment_role_code,
      'status', status,
      'notes', '[masked]'
    ),
    NULL,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    '{}'::jsonb
  );

  RETURN NEXT;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Project staff assignment already exists.';
END
$function$;

CREATE OR REPLACE FUNCTION app.remove_project_staff_assignment(
  p_actor_auth_subject uuid,
  p_assignment_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  assignment_id uuid,
  project_id uuid,
  user_id uuid,
  assignment_role_code text,
  status text,
  removed_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.project_staff_assignments%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO existing_row
  FROM app.project_staff_assignments AS psa
  WHERE psa.id = p_assignment_id
  FOR UPDATE;

  IF existing_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment not available.';
  END IF;
  IF existing_row.status <> 'ACTIVE' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment is already removed.';
  END IF;

  PERFORM set_config('app.allow_project_staff_assignment_removal', 'on', true);
  UPDATE app.project_staff_assignments AS psa
  SET status = 'REMOVED',
      removed_at = now(),
      removed_by = actor_row.actor_user_id
  WHERE psa.id = p_assignment_id
  RETURNING
    psa.id,
    psa.project_id,
    psa.user_id,
    psa.assignment_role_code::text,
    psa.status::text,
    psa.removed_at
  INTO assignment_id, project_id, user_id, assignment_role_code, status, removed_at;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'project_staff_assignment_removed',
    'project_staff_assignment',
    assignment_id,
    project_id,
    'success',
    jsonb_build_object(
      'project_id', project_id,
      'assignment_role_code', assignment_role_code,
      'status', 'ACTIVE'
    ),
    jsonb_build_object(
      'project_id', project_id,
      'assignment_role_code', assignment_role_code,
      'status', status
    ),
    NULL,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    '{}'::jsonb
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_staff_assignment_list(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_include_removed boolean DEFAULT true
)
RETURNS TABLE (
  assignment_id uuid,
  project_id uuid,
  project_number text,
  user_id uuid,
  staff_full_name text,
  assignment_role_code text,
  status text,
  assigned_at timestamptz,
  assigned_by uuid,
  removed_at timestamptz,
  removed_by uuid,
  notes text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    psa.id,
    psa.project_id,
    p.project_number::text,
    psa.user_id,
    up.full_name::text,
    psa.assignment_role_code::text,
    psa.status::text,
    psa.assigned_at,
    psa.assigned_by,
    psa.removed_at,
    psa.removed_by,
    psa.notes
  FROM app.project_staff_assignments AS psa
  INNER JOIN app.projects AS p
    ON p.id = psa.project_id
  LEFT JOIN app.user_profiles AS up
    ON up.user_id = psa.user_id
  WHERE psa.project_id = p_project_id
    AND (coalesce(p_include_removed, true) OR psa.status = 'ACTIVE')
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject))
  ORDER BY psa.assigned_at DESC, psa.id DESC;
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_staff_assignment_detail(
  p_actor_auth_subject uuid,
  p_assignment_id uuid
)
RETURNS TABLE (
  assignment_id uuid,
  project_id uuid,
  project_number text,
  user_id uuid,
  staff_full_name text,
  assignment_role_code text,
  status text,
  assigned_at timestamptz,
  assigned_by uuid,
  removed_at timestamptz,
  removed_by uuid,
  notes text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    psa.id,
    psa.project_id,
    p.project_number::text,
    psa.user_id,
    up.full_name::text,
    psa.assignment_role_code::text,
    psa.status::text,
    psa.assigned_at,
    psa.assigned_by,
    psa.removed_at,
    psa.removed_by,
    psa.notes
  FROM app.project_staff_assignments AS psa
  INNER JOIN app.projects AS p
    ON p.id = psa.project_id
  LEFT JOIN app.user_profiles AS up
    ON up.user_id = psa.user_id
  WHERE psa.id = p_assignment_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION app.owner_eligible_project_staff_list(
  p_actor_auth_subject uuid,
  p_assignment_role_code varchar DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  user_id uuid,
  full_name text,
  role_code text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_assignment_role_code IS NOT NULL THEN
    PERFORM app.assert_project_staff_assignment_role(p_assignment_role_code);
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    up.full_name::text,
    ur.role_code::text
  FROM app.users AS u
  INNER JOIN app.user_roles AS ur
    ON ur.user_id = u.id
   AND ur.is_active
   AND ur.role_code IN ('project_manager', 'site_supervisor')
  INNER JOIN app.roles AS r
    ON r.code = ur.role_code
   AND r.is_active
   AND r.is_staff_role
  LEFT JOIN app.user_profiles AS up
    ON up.user_id = u.id
  WHERE u.user_type = 'STAFF'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND (p_assignment_role_code IS NULL OR ur.role_code = p_assignment_role_code)
    AND NOT EXISTS (
      SELECT 1
      FROM app.user_roles AS client_role
      WHERE client_role.user_id = u.id
        AND client_role.role_code = 'client'
        AND client_role.is_active
    )
  ORDER BY up.full_name NULLS LAST, u.id, ur.role_code
  LIMIT safe_limit
  OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.has_active_project_assignment(
  p_user_id uuid,
  p_project_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app.project_staff_assignments AS psa
    INNER JOIN app.users AS u
      ON u.id = psa.user_id
    INNER JOIN app.user_roles AS ur
      ON ur.user_id = u.id
     AND ur.role_code = psa.assignment_role_code
     AND ur.is_active
    INNER JOIN app.roles AS r
      ON r.code = ur.role_code
     AND r.is_active
     AND r.is_staff_role
    INNER JOIN app.projects AS p
      ON p.id = psa.project_id
    WHERE psa.user_id = p_user_id
      AND psa.project_id = p_project_id
      AND psa.status = 'ACTIVE'
      AND psa.assignment_role_code IN ('project_manager', 'site_supervisor')
      AND u.user_type = 'STAFF'
      AND u.status = 'ACTIVE'
      AND u.is_active
      AND p.status <> 'ARCHIVED'
  );
$function$;

CREATE OR REPLACE FUNCTION app.has_active_project_assignment_role(
  p_user_id uuid,
  p_project_id uuid,
  p_role_code varchar
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT p_role_code IN ('project_manager', 'site_supervisor')
    AND EXISTS (
      SELECT 1
      FROM app.project_staff_assignments AS psa
      INNER JOIN app.users AS u
        ON u.id = psa.user_id
      INNER JOIN app.user_roles AS ur
        ON ur.user_id = u.id
       AND ur.role_code = psa.assignment_role_code
       AND ur.is_active
      INNER JOIN app.roles AS r
        ON r.code = ur.role_code
       AND r.is_active
       AND r.is_staff_role
      INNER JOIN app.projects AS p
        ON p.id = psa.project_id
      WHERE psa.user_id = p_user_id
        AND psa.project_id = p_project_id
        AND psa.assignment_role_code = p_role_code
        AND psa.status = 'ACTIVE'
        AND u.user_type = 'STAFF'
        AND u.status = 'ACTIVE'
        AND u.is_active
        AND p.status <> 'ARCHIVED'
    );
$function$;

CREATE OR REPLACE FUNCTION app.change_project_client(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_new_client_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  project_id uuid,
  old_client_id uuid,
  new_client_id uuid,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project Client reassignment.';
  END IF;
  PERFORM app.require_active_client_record(p_new_client_id);
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  IF existing_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record not available.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.';
  END IF;
  IF existing_row.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed in this status.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app.project_staff_assignments AS psa
    WHERE psa.project_id = p_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed after staff assignment history exists.';
  END IF;
  IF existing_row.client_id = p_new_client_id THEN
    project_id := existing_row.id;
    old_client_id := existing_row.client_id;
    new_client_id := existing_row.client_id;
    version_number := existing_row.version_number;
    RETURN NEXT;
    RETURN;
  END IF;

  PERFORM set_config('app.allow_project_client_change', 'on', true);
  UPDATE app.projects AS p
  SET client_id = p_new_client_id,
      updated_by = actor_row.actor_user_id
  WHERE p.id = p_project_id
  RETURNING p.id, existing_row.client_id, p.client_id, p.version_number
  INTO project_id, old_client_id, new_client_id, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_client_changed', 'project_record', project_id, NULL, 'success',
    jsonb_build_object('client', '[masked]', 'version_number', existing_row.version_number),
    jsonb_build_object('client', '[masked]', 'version_number', version_number),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('dependent_record_guard', 'project_staff_assignments')
  );
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.archive_project_record(p_actor_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, status text, archived_at timestamptz, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  IF existing_row.id IS NULL OR p_expected_version_number IS NULL OR existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.'; END IF;
  IF existing_row.status NOT IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project status transition is not allowed.'; END IF;
  IF EXISTS (
    SELECT 1
    FROM app.project_staff_assignments AS psa
    WHERE psa.project_id = p_project_id
      AND psa.status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived while active staff assignments exist.';
  END IF;
  PERFORM set_config('app.allow_project_status_change', 'on', true);
  PERFORM set_config('app.allow_project_lifecycle_fields', 'on', true);
  UPDATE app.projects AS p SET status = 'ARCHIVED', archived_at = now(), archived_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE p.id = p_project_id RETURNING p.id, p.status::text, p.archived_at, p.version_number INTO project_id, status, archived_at, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_archived', 'project_record', project_id, NULL, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION public.server_create_project_staff_assignment(
  p_verified_owner_auth_subject uuid,
  p_project_id uuid,
  p_user_id uuid,
  p_assignment_role_code varchar,
  p_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (assignment_id uuid, project_id uuid, user_id uuid, assignment_role_code text, status text, assigned_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.create_project_staff_assignment(p_verified_owner_auth_subject, p_project_id, p_user_id, p_assignment_role_code, p_notes, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_remove_project_staff_assignment(
  p_verified_owner_auth_subject uuid,
  p_assignment_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (assignment_id uuid, project_id uuid, user_id uuid, assignment_role_code text, status text, removed_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.remove_project_staff_assignment(p_verified_owner_auth_subject, p_assignment_id, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_staff_assignment_list(
  p_verified_owner_auth_subject uuid,
  p_project_id uuid,
  p_include_removed boolean DEFAULT true
)
RETURNS TABLE (assignment_id uuid, project_id uuid, project_number text, user_id uuid, staff_full_name text, assignment_role_code text, status text, assigned_at timestamptz, assigned_by uuid, removed_at timestamptz, removed_by uuid, notes text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_staff_assignment_list(p_verified_owner_auth_subject, p_project_id, p_include_removed);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_staff_assignment_detail(
  p_verified_owner_auth_subject uuid,
  p_assignment_id uuid
)
RETURNS TABLE (assignment_id uuid, project_id uuid, project_number text, user_id uuid, staff_full_name text, assignment_role_code text, status text, assigned_at timestamptz, assigned_by uuid, removed_at timestamptz, removed_by uuid, notes text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_staff_assignment_detail(p_verified_owner_auth_subject, p_assignment_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_eligible_project_staff_list(
  p_verified_owner_auth_subject uuid,
  p_assignment_role_code varchar DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (user_id uuid, full_name text, role_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_eligible_project_staff_list(p_verified_owner_auth_subject, p_assignment_role_code, p_limit, p_offset);
$function$;

COMMIT;
