BEGIN;

CREATE OR REPLACE FUNCTION app.assert_project_task_workflow_project(p_project app.projects, p_allow_pre_active boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_project.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task workflow is not available.';
  END IF;
  IF p_allow_pre_active THEN
    IF p_project.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED', 'ACTIVE', 'ON_HOLD') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task workflow is not allowed in this Project status.';
    END IF;
  ELSE
    IF p_project.status NOT IN ('ACTIVE', 'ON_HOLD') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task workflow is not allowed in this Project status.';
    END IF;
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.insert_project_task_update(
  p_actor_user_id uuid,
  p_task_id uuid,
  p_previous_status app.project_task_status,
  p_new_status app.project_task_status,
  p_previous_completion_percent numeric,
  p_new_completion_percent numeric,
  p_update_note text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  task_update_id uuid;
  normalized_note text := nullif(btrim(coalesce(p_update_note, '')), '');
BEGIN
  IF normalized_note IS NOT NULL AND length(normalized_note) > 4000 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task update note is invalid.';
  END IF;
  INSERT INTO app.task_updates (
    task_id,
    previous_status,
    new_status,
    previous_completion_percent,
    new_completion_percent,
    update_note,
    created_by
  )
  VALUES (
    p_task_id,
    p_previous_status,
    p_new_status,
    p_previous_completion_percent,
    p_new_completion_percent,
    normalized_note,
    p_actor_user_id
  )
  RETURNING id INTO task_update_id;
  RETURN task_update_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.update_project_task_progress(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_expected_version_number integer,
  p_new_completion_percent numeric,
  p_update_note text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.tasks%ROWTYPE;
  updated_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 OR p_new_completion_percent IS NULL OR p_new_completion_percent < 0 OR p_new_completion_percent >= 100 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task progress update.';
  END IF;
  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active OR existing_row.status NOT IN ('IN_PROGRESS', 'BLOCKED') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task progress cannot be updated.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.'; END IF;
  IF existing_row.completion_percent = p_new_completion_percent THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task progress is unchanged.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_task_workflow_project(project_row, false);

  PERFORM set_config('app.allow_project_task_workflow', 'on', true);
  UPDATE app.tasks AS t
  SET completion_percent = p_new_completion_percent,
      updated_by = actor_row.actor_user_id
  WHERE t.id = p_task_id
  RETURNING * INTO updated_row;
  PERFORM set_config('app.allow_project_task_workflow', 'off', true);

  task_update_id := app.insert_project_task_update(actor_row.actor_user_id, updated_row.id, existing_row.status, updated_row.status, existing_row.completion_percent, updated_row.completion_percent, p_update_note);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_progress_updated', 'project_task', updated_row.id, updated_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text, 'completion_percent', existing_row.completion_percent, 'version_number', existing_row.version_number), jsonb_build_object('status', updated_row.status::text, 'completion_percent', updated_row.completion_percent, 'version_number', updated_row.version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('project_id', updated_row.project_id, 'task_id', updated_row.id, 'task_update_id', task_update_id, 'previous_status', existing_row.status::text, 'new_status', updated_row.status::text, 'previous_completion_percent', existing_row.completion_percent, 'new_completion_percent', updated_row.completion_percent, 'reason_provided', nullif(btrim(coalesce(p_update_note, '')), '') IS NOT NULL));
  task_id := updated_row.id; project_id := updated_row.project_id; status := updated_row.status::text; completion_percent := updated_row.completion_percent; completed_at := updated_row.completed_at; version_number := updated_row.version_number;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.change_project_task_status(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_expected_version_number integer,
  p_new_status app.project_task_status,
  p_update_note text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.tasks%ROWTYPE;
  updated_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 OR p_new_status IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task status transition.';
  END IF;
  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task status cannot be changed.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.'; END IF;
  IF existing_row.status = p_new_status THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task status is unchanged.'; END IF;
  IF NOT (
    (existing_row.status = 'TODO' AND p_new_status IN ('IN_PROGRESS', 'BLOCKED')) OR
    (existing_row.status = 'IN_PROGRESS' AND p_new_status = 'BLOCKED') OR
    (existing_row.status = 'BLOCKED' AND p_new_status = 'IN_PROGRESS')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task status transition is not allowed.';
  END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_task_workflow_project(project_row, false);

  PERFORM set_config('app.allow_project_task_workflow', 'on', true);
  UPDATE app.tasks AS t
  SET status = p_new_status,
      updated_by = actor_row.actor_user_id
  WHERE t.id = p_task_id
  RETURNING * INTO updated_row;
  PERFORM set_config('app.allow_project_task_workflow', 'off', true);

  task_update_id := app.insert_project_task_update(actor_row.actor_user_id, updated_row.id, existing_row.status, updated_row.status, existing_row.completion_percent, updated_row.completion_percent, p_update_note);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_status_changed', 'project_task', updated_row.id, updated_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text, 'completion_percent', existing_row.completion_percent, 'version_number', existing_row.version_number), jsonb_build_object('status', updated_row.status::text, 'completion_percent', updated_row.completion_percent, 'version_number', updated_row.version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('project_id', updated_row.project_id, 'task_id', updated_row.id, 'task_update_id', task_update_id, 'previous_status', existing_row.status::text, 'new_status', updated_row.status::text, 'previous_completion_percent', existing_row.completion_percent, 'new_completion_percent', updated_row.completion_percent, 'reason_provided', nullif(btrim(coalesce(p_update_note, '')), '') IS NOT NULL));
  task_id := updated_row.id; project_id := updated_row.project_id; status := updated_row.status::text; completion_percent := updated_row.completion_percent; completed_at := updated_row.completed_at; version_number := updated_row.version_number;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.complete_project_task(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_expected_version_number integer,
  p_update_note text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.tasks%ROWTYPE;
  updated_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task completion.'; END IF;
  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active OR existing_row.status NOT IN ('IN_PROGRESS', 'BLOCKED') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be completed.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_task_workflow_project(project_row, false);

  PERFORM set_config('app.allow_project_task_workflow', 'on', true);
  UPDATE app.tasks AS t
  SET status = 'COMPLETED',
      completion_percent = 100,
      completed_at = now(),
      updated_by = actor_row.actor_user_id
  WHERE t.id = p_task_id
  RETURNING * INTO updated_row;
  PERFORM set_config('app.allow_project_task_workflow', 'off', true);

  task_update_id := app.insert_project_task_update(actor_row.actor_user_id, updated_row.id, existing_row.status, updated_row.status, existing_row.completion_percent, updated_row.completion_percent, p_update_note);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_completed', 'project_task', updated_row.id, updated_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text, 'completion_percent', existing_row.completion_percent, 'version_number', existing_row.version_number), jsonb_build_object('status', updated_row.status::text, 'completion_percent', updated_row.completion_percent, 'version_number', updated_row.version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('project_id', updated_row.project_id, 'task_id', updated_row.id, 'task_update_id', task_update_id, 'previous_status', existing_row.status::text, 'new_status', updated_row.status::text, 'previous_completion_percent', existing_row.completion_percent, 'new_completion_percent', updated_row.completion_percent, 'reason_provided', nullif(btrim(coalesce(p_update_note, '')), '') IS NOT NULL));
  task_id := updated_row.id; project_id := updated_row.project_id; status := updated_row.status::text; completion_percent := updated_row.completion_percent; completed_at := updated_row.completed_at; version_number := updated_row.version_number;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.reopen_project_task(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_expected_version_number integer,
  p_new_completion_percent numeric,
  p_reason text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.tasks%ROWTYPE;
  updated_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
  reason_text text := btrim(coalesce(p_reason, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 OR p_new_completion_percent IS NULL OR p_new_completion_percent < 0 OR p_new_completion_percent >= 100 OR reason_text = '' OR length(reason_text) > 4000 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task reopening.';
  END IF;
  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active OR existing_row.status <> 'COMPLETED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be reopened.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_task_workflow_project(project_row, false);

  PERFORM set_config('app.allow_project_task_workflow', 'on', true);
  UPDATE app.tasks AS t
  SET status = 'IN_PROGRESS',
      completion_percent = p_new_completion_percent,
      completed_at = NULL,
      updated_by = actor_row.actor_user_id
  WHERE t.id = p_task_id
  RETURNING * INTO updated_row;
  PERFORM set_config('app.allow_project_task_workflow', 'off', true);

  task_update_id := app.insert_project_task_update(actor_row.actor_user_id, updated_row.id, existing_row.status, updated_row.status, existing_row.completion_percent, updated_row.completion_percent, reason_text);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_reopened', 'project_task', updated_row.id, updated_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text, 'completion_percent', existing_row.completion_percent, 'version_number', existing_row.version_number), jsonb_build_object('status', updated_row.status::text, 'completion_percent', updated_row.completion_percent, 'version_number', updated_row.version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('project_id', updated_row.project_id, 'task_id', updated_row.id, 'task_update_id', task_update_id, 'previous_status', existing_row.status::text, 'new_status', updated_row.status::text, 'previous_completion_percent', existing_row.completion_percent, 'new_completion_percent', updated_row.completion_percent, 'reason_provided', true));
  task_id := updated_row.id; project_id := updated_row.project_id; status := updated_row.status::text; completion_percent := updated_row.completion_percent; completed_at := updated_row.completed_at; version_number := updated_row.version_number;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.cancel_project_task(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_expected_version_number integer,
  p_reason text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.tasks%ROWTYPE;
  updated_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
  reason_text text := btrim(coalesce(p_reason, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 OR reason_text = '' OR length(reason_text) > 4000 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task cancellation.';
  END IF;
  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active OR existing_row.status NOT IN ('TODO', 'IN_PROGRESS', 'BLOCKED') OR existing_row.completion_percent >= 100 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be cancelled.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_task_workflow_project(project_row, true);

  PERFORM set_config('app.allow_project_task_workflow', 'on', true);
  UPDATE app.tasks AS t
  SET status = 'CANCELLED',
      updated_by = actor_row.actor_user_id
  WHERE t.id = p_task_id
  RETURNING * INTO updated_row;
  PERFORM set_config('app.allow_project_task_workflow', 'off', true);

  task_update_id := app.insert_project_task_update(actor_row.actor_user_id, updated_row.id, existing_row.status, updated_row.status, existing_row.completion_percent, updated_row.completion_percent, reason_text);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_cancelled', 'project_task', updated_row.id, updated_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text, 'completion_percent', existing_row.completion_percent, 'version_number', existing_row.version_number), jsonb_build_object('status', updated_row.status::text, 'completion_percent', updated_row.completion_percent, 'version_number', updated_row.version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('project_id', updated_row.project_id, 'task_id', updated_row.id, 'task_update_id', task_update_id, 'previous_status', existing_row.status::text, 'new_status', updated_row.status::text, 'previous_completion_percent', existing_row.completion_percent, 'new_completion_percent', updated_row.completion_percent, 'reason_provided', true));
  task_id := updated_row.id; project_id := updated_row.project_id; status := updated_row.status::text; completion_percent := updated_row.completion_percent; completed_at := updated_row.completed_at; version_number := updated_row.version_number;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_task_update_list(p_actor_auth_subject uuid, p_task_id uuid)
RETURNS TABLE (id uuid, task_id uuid, previous_status app.project_task_status, new_status app.project_task_status, previous_completion_percent numeric, new_completion_percent numeric, update_note text, created_at timestamptz, created_by uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT tu.id, tu.task_id, tu.previous_status, tu.new_status, tu.previous_completion_percent, tu.new_completion_percent, tu.update_note, tu.created_at, tu.created_by
  FROM app.task_updates AS tu
  WHERE tu.task_id = p_task_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject))
  ORDER BY tu.created_at ASC, tu.id ASC;
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_task_update_detail(p_actor_auth_subject uuid, p_task_update_id uuid)
RETURNS TABLE (id uuid, task_id uuid, previous_status app.project_task_status, new_status app.project_task_status, previous_completion_percent numeric, new_completion_percent numeric, update_note text, created_at timestamptz, created_by uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT tu.id, tu.task_id, tu.previous_status, tu.new_status, tu.previous_completion_percent, tu.new_completion_percent, tu.update_note, tu.created_at, tu.created_by
  FROM app.task_updates AS tu
  WHERE tu.id = p_task_update_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION public.server_update_project_task_progress(p_verified_owner_auth_subject uuid, p_task_id uuid, p_expected_version_number integer, p_new_completion_percent numeric, p_update_note text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.update_project_task_progress(p_verified_owner_auth_subject, p_task_id, p_expected_version_number, p_new_completion_percent, p_update_note, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_change_project_task_status(p_verified_owner_auth_subject uuid, p_task_id uuid, p_expected_version_number integer, p_new_status app.project_task_status, p_update_note text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.change_project_task_status(p_verified_owner_auth_subject, p_task_id, p_expected_version_number, p_new_status, p_update_note, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_complete_project_task(p_verified_owner_auth_subject uuid, p_task_id uuid, p_expected_version_number integer, p_update_note text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.complete_project_task(p_verified_owner_auth_subject, p_task_id, p_expected_version_number, p_update_note, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_reopen_project_task(p_verified_owner_auth_subject uuid, p_task_id uuid, p_expected_version_number integer, p_new_completion_percent numeric, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.reopen_project_task(p_verified_owner_auth_subject, p_task_id, p_expected_version_number, p_new_completion_percent, p_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_cancel_project_task(p_verified_owner_auth_subject uuid, p_task_id uuid, p_expected_version_number integer, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, status text, completion_percent numeric, completed_at timestamptz, version_number integer, task_update_id uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.cancel_project_task(p_verified_owner_auth_subject, p_task_id, p_expected_version_number, p_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_task_update_list(p_verified_owner_auth_subject uuid, p_task_id uuid)
RETURNS TABLE (id uuid, task_id uuid, previous_status app.project_task_status, new_status app.project_task_status, previous_completion_percent numeric, new_completion_percent numeric, update_note text, created_at timestamptz, created_by uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_task_update_list(p_verified_owner_auth_subject, p_task_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_task_update_detail(p_verified_owner_auth_subject uuid, p_task_update_id uuid)
RETURNS TABLE (id uuid, task_id uuid, previous_status app.project_task_status, new_status app.project_task_status, previous_completion_percent numeric, new_completion_percent numeric, update_note text, created_at timestamptz, created_by uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_task_update_detail(p_verified_owner_auth_subject, p_task_update_id);
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
  IF existing_row.status NOT IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task archival requires a terminal task status.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  IF project_row.status = 'ARCHIVED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task archival is not allowed in this Project status.'; END IF;
  IF EXISTS (SELECT 1 FROM app.task_assignments AS ta WHERE ta.task_id = p_task_id AND ta.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be archived while active assignments exist.';
  END IF;
  PERFORM set_config('app.allow_project_task_archive', 'on', true);
  UPDATE app.tasks AS t SET is_active = false, updated_by = actor_row.actor_user_id WHERE t.id = p_task_id RETURNING t.id, t.project_id, t.task_number::text, t.status::text, t.is_active, t.version_number INTO task_id, project_id, task_number, status, is_active, version_number;
  PERFORM set_config('app.allow_project_task_archive', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_archived', 'project_task', task_id, project_id, 'success', jsonb_build_object('is_active', true, 'status', existing_row.status::text, 'version_number', existing_row.version_number), jsonb_build_object('is_active', false, 'status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

COMMIT;
