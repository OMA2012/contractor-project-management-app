BEGIN;

CREATE OR REPLACE FUNCTION app.assign_project_task(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_project_staff_assignment_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  task_assignment_id uuid,
  task_id uuid,
  project_staff_assignment_id uuid,
  assigned_at timestamptz,
  is_active boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  task_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
  staff_assignment_row app.project_staff_assignments%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO task_row
  FROM app.tasks AS t
  WHERE t.id = p_task_id
  FOR UPDATE;

  IF task_row.id IS NULL OR NOT task_row.is_active OR task_row.status <> 'TODO' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task is not available for assignment.';
  END IF;

  SELECT * INTO project_row
  FROM app.projects AS p
  WHERE p.id = task_row.project_id
  FOR UPDATE;

  IF project_row.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED', 'ACTIVE', 'ON_HOLD') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task assignment is not allowed in this Project status.';
  END IF;

  SELECT * INTO staff_assignment_row
  FROM app.project_staff_assignments AS psa
  WHERE psa.id = p_project_staff_assignment_id
  FOR UPDATE;

  IF staff_assignment_row.id IS NULL
     OR staff_assignment_row.status <> 'ACTIVE'
     OR staff_assignment_row.project_id <> task_row.project_id
     OR staff_assignment_row.assignment_role_code NOT IN ('project_manager', 'site_supervisor') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  PERFORM app.assert_project_staff_assignment_target(
    actor_row.actor_user_id,
    staff_assignment_row.user_id,
    staff_assignment_row.assignment_role_code
  );

  IF EXISTS (
    SELECT 1
    FROM app.task_assignments AS ta
    WHERE ta.task_id = p_task_id
      AND ta.project_staff_assignment_id = p_project_staff_assignment_id
      AND ta.is_active
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Project task assignment already exists.';
  END IF;

  INSERT INTO app.task_assignments (
    task_id,
    project_staff_assignment_id,
    assigned_by
  )
  VALUES (
    p_task_id,
    p_project_staff_assignment_id,
    actor_row.actor_user_id
  )
  RETURNING
    id,
    app.task_assignments.task_id,
    app.task_assignments.project_staff_assignment_id,
    app.task_assignments.assigned_at,
    app.task_assignments.is_active
  INTO task_assignment_id, task_id, project_staff_assignment_id, assigned_at, is_active;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'project_task_assigned',
    'project_task_assignment',
    task_assignment_id,
    task_row.project_id,
    'success',
    '{}'::jsonb,
    jsonb_build_object(
      'project_id', task_row.project_id,
      'task_id', task_id,
      'task_assignment_id', task_assignment_id,
      'project_staff_assignment_id', project_staff_assignment_id,
      'assignment_role_code', staff_assignment_row.assignment_role_code
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
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Project task assignment already exists.';
END
$function$;

CREATE OR REPLACE FUNCTION app.remove_project_task_assignment(
  p_actor_auth_subject uuid,
  p_task_assignment_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  task_assignment_id uuid,
  task_id uuid,
  project_staff_assignment_id uuid,
  removed_at timestamptz,
  is_active boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.task_assignments%ROWTYPE;
  task_row app.tasks%ROWTYPE;
  staff_assignment_row app.project_staff_assignments%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO existing_row
  FROM app.task_assignments AS ta
  WHERE ta.id = p_task_assignment_id
  FOR UPDATE;

  IF existing_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task assignment not available.';
  END IF;
  IF NOT existing_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task assignment is already removed.';
  END IF;

  SELECT * INTO task_row FROM app.tasks AS t WHERE t.id = existing_row.task_id;
  SELECT * INTO staff_assignment_row FROM app.project_staff_assignments AS psa WHERE psa.id = existing_row.project_staff_assignment_id;

  PERFORM set_config('app.allow_project_task_assignment_removal', 'on', true);
  UPDATE app.task_assignments AS ta
  SET is_active = false,
      removed_at = now()
  WHERE ta.id = p_task_assignment_id
  RETURNING
    ta.id,
    ta.task_id,
    ta.project_staff_assignment_id,
    ta.removed_at,
    ta.is_active
  INTO task_assignment_id, task_id, project_staff_assignment_id, removed_at, is_active;
  PERFORM set_config('app.allow_project_task_assignment_removal', 'off', true);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'project_task_assignment_removed',
    'project_task_assignment',
    task_assignment_id,
    task_row.project_id,
    'success',
    jsonb_build_object('project_id', task_row.project_id, 'task_id', task_id, 'task_assignment_id', task_assignment_id, 'project_staff_assignment_id', project_staff_assignment_id, 'assignment_role_code', staff_assignment_row.assignment_role_code),
    jsonb_build_object('project_id', task_row.project_id, 'task_id', task_id, 'task_assignment_id', task_assignment_id, 'project_staff_assignment_id', project_staff_assignment_id, 'assignment_role_code', staff_assignment_row.assignment_role_code, 'removal_cause', 'owner_requested'),
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

CREATE OR REPLACE FUNCTION app.owner_project_task_assignment_list(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_include_inactive boolean DEFAULT true
)
RETURNS TABLE (
  id uuid,
  task_id uuid,
  project_staff_assignment_id uuid,
  assigned_at timestamptz,
  removed_at timestamptz,
  is_active boolean,
  assigned_by uuid,
  staff_user_id uuid,
  staff_full_name text,
  assignment_role_code text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    ta.id,
    ta.task_id,
    ta.project_staff_assignment_id,
    ta.assigned_at,
    ta.removed_at,
    ta.is_active,
    ta.assigned_by,
    psa.user_id AS staff_user_id,
    up.full_name,
    psa.assignment_role_code::text
  FROM app.task_assignments AS ta
  INNER JOIN app.project_staff_assignments AS psa
    ON psa.id = ta.project_staff_assignment_id
  INNER JOIN app.user_profiles AS up
    ON up.user_id = psa.user_id
  WHERE ta.task_id = p_task_id
    AND (coalesce(p_include_inactive, true) OR ta.is_active)
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject))
  ORDER BY ta.is_active DESC, ta.assigned_at ASC, ta.id ASC;
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_task_assignment_detail(
  p_actor_auth_subject uuid,
  p_task_assignment_id uuid
)
RETURNS TABLE (
  id uuid,
  task_id uuid,
  project_staff_assignment_id uuid,
  assigned_at timestamptz,
  removed_at timestamptz,
  is_active boolean,
  assigned_by uuid,
  staff_user_id uuid,
  staff_full_name text,
  assignment_role_code text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    ta.id,
    ta.task_id,
    ta.project_staff_assignment_id,
    ta.assigned_at,
    ta.removed_at,
    ta.is_active,
    ta.assigned_by,
    psa.user_id AS staff_user_id,
    up.full_name,
    psa.assignment_role_code::text
  FROM app.task_assignments AS ta
  INNER JOIN app.project_staff_assignments AS psa
    ON psa.id = ta.project_staff_assignment_id
  INNER JOIN app.user_profiles AS up
    ON up.user_id = psa.user_id
  WHERE ta.id = p_task_assignment_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION public.server_assign_project_task(
  p_verified_owner_auth_subject uuid,
  p_task_id uuid,
  p_project_staff_assignment_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_assignment_id uuid, task_id uuid, project_staff_assignment_id uuid, assigned_at timestamptz, is_active boolean)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.assign_project_task(p_verified_owner_auth_subject, p_task_id, p_project_staff_assignment_id, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_remove_project_task_assignment(
  p_verified_owner_auth_subject uuid,
  p_task_assignment_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_assignment_id uuid, task_id uuid, project_staff_assignment_id uuid, removed_at timestamptz, is_active boolean)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.remove_project_task_assignment(p_verified_owner_auth_subject, p_task_assignment_id, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_task_assignment_list(
  p_verified_owner_auth_subject uuid,
  p_task_id uuid,
  p_include_inactive boolean DEFAULT true
)
RETURNS TABLE (id uuid, task_id uuid, project_staff_assignment_id uuid, assigned_at timestamptz, removed_at timestamptz, is_active boolean, assigned_by uuid, staff_user_id uuid, staff_full_name text, assignment_role_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_task_assignment_list(p_verified_owner_auth_subject, p_task_id, p_include_inactive);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_task_assignment_detail(
  p_verified_owner_auth_subject uuid,
  p_task_assignment_id uuid
)
RETURNS TABLE (id uuid, task_id uuid, project_staff_assignment_id uuid, assigned_at timestamptz, removed_at timestamptz, is_active boolean, assigned_by uuid, staff_user_id uuid, staff_full_name text, assignment_role_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_task_assignment_detail(p_verified_owner_auth_subject, p_task_assignment_id);
$function$;

CREATE OR REPLACE FUNCTION app.archive_project_task(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_id uuid, project_id uuid, task_number text, status text, is_active boolean, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.tasks%ROWTYPE; project_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task archival.'; END IF;
  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be archived.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  IF project_row.status = 'ARCHIVED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task archival is not allowed in this Project status.'; END IF;
  IF EXISTS (SELECT 1 FROM app.task_assignments AS ta WHERE ta.task_id = p_task_id AND ta.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be archived while active assignments exist.';
  END IF;
  PERFORM set_config('app.allow_project_task_archive', 'on', true);
  UPDATE app.tasks AS t SET is_active = false, updated_by = actor_row.actor_user_id WHERE t.id = p_task_id RETURNING t.id, t.project_id, t.task_number::text, t.status::text, t.is_active, t.version_number INTO task_id, project_id, task_number, status, is_active, version_number;
  PERFORM set_config('app.allow_project_task_archive', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_archived', 'project_task', task_id, project_id, 'success', jsonb_build_object('is_active', true, 'version_number', existing_row.version_number), jsonb_build_object('is_active', false, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
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
RETURNS TABLE (assignment_id uuid, project_id uuid, user_id uuid, assignment_role_code text, status text, removed_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.project_staff_assignments%ROWTYPE; child_row record; affected_child_count integer := 0;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.project_staff_assignments AS psa WHERE psa.id = p_assignment_id FOR UPDATE;
  IF existing_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment not available.'; END IF;
  IF existing_row.status <> 'ACTIVE' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment is already removed.'; END IF;

  PERFORM set_config('app.allow_project_task_assignment_removal', 'on', true);
  FOR child_row IN
    UPDATE app.task_assignments AS ta
    SET is_active = false,
        removed_at = now()
    WHERE ta.project_staff_assignment_id = p_assignment_id
      AND ta.is_active
    RETURNING ta.id, ta.task_id, ta.project_staff_assignment_id, ta.removed_at
  LOOP
    affected_child_count := affected_child_count + 1;
    PERFORM app.write_activity_log(
      actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
      'project_task_assignment_removed', 'project_task_assignment', child_row.id, existing_row.project_id, 'success',
      jsonb_build_object('project_id', existing_row.project_id, 'task_id', child_row.task_id, 'task_assignment_id', child_row.id, 'project_staff_assignment_id', child_row.project_staff_assignment_id, 'assignment_role_code', existing_row.assignment_role_code),
      jsonb_build_object('project_id', existing_row.project_id, 'task_id', child_row.task_id, 'task_assignment_id', child_row.id, 'project_staff_assignment_id', child_row.project_staff_assignment_id, 'assignment_role_code', existing_row.assignment_role_code, 'removal_cause', 'project_access_removed'),
      NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
      jsonb_build_object('removal_cause', 'project_access_removed')
    );
  END LOOP;
  PERFORM set_config('app.allow_project_task_assignment_removal', 'off', true);

  PERFORM set_config('app.allow_project_staff_assignment_removal', 'on', true);
  UPDATE app.project_staff_assignments AS psa
  SET status = 'REMOVED',
      removed_at = now(),
      removed_by = actor_row.actor_user_id
  WHERE psa.id = p_assignment_id
  RETURNING psa.id, psa.project_id, psa.user_id, psa.assignment_role_code::text, psa.status::text, psa.removed_at
  INTO assignment_id, project_id, user_id, assignment_role_code, status, removed_at;
  PERFORM set_config('app.allow_project_staff_assignment_removal', 'off', true);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_staff_assignment_removed', 'project_staff_assignment', assignment_id, project_id, 'success',
    jsonb_build_object('project_id', project_id, 'assignment_role_code', assignment_role_code, 'status', 'ACTIVE'),
    jsonb_build_object('project_id', project_id, 'assignment_role_code', assignment_role_code, 'status', status, 'affected_active_assignment_count', affected_child_count),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('affected_active_assignment_count', affected_child_count)
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
  IF existing_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived in this status.'; END IF;
  IF existing_row.status = 'ARCHIVED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project status transition is not allowed.'; END IF;
  IF existing_row.status NOT IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived in this status.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.'; END IF;
  IF EXISTS (SELECT 1 FROM app.task_assignments AS ta INNER JOIN app.tasks AS t ON t.id = ta.task_id WHERE t.project_id = p_project_id AND ta.is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived while active task assignments exist.'; END IF;
  IF EXISTS (SELECT 1 FROM app.project_staff_assignments AS psa WHERE psa.project_id = p_project_id AND psa.status = 'ACTIVE') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived while active staff assignments exist.'; END IF;
  IF EXISTS (SELECT 1 FROM app.project_phases AS pp WHERE pp.project_id = p_project_id AND pp.is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived while active phases exist.'; END IF;
  IF EXISTS (SELECT 1 FROM app.project_milestones AS pm WHERE pm.project_id = p_project_id AND pm.is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived while active milestones exist.'; END IF;
  IF EXISTS (SELECT 1 FROM app.tasks AS t WHERE t.project_id = p_project_id AND t.is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cannot be archived while active tasks exist.'; END IF;
  PERFORM set_config('app.allow_project_status_change', 'on', true);
  PERFORM set_config('app.allow_project_lifecycle_fields', 'on', true);
  UPDATE app.projects AS p SET status = 'ARCHIVED', archived_at = now(), archived_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE p.id = p_project_id RETURNING p.id, p.status::text, p.archived_at, p.version_number INTO project_id, status, archived_at, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_archived', 'project_record', project_id, NULL, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

COMMIT;
