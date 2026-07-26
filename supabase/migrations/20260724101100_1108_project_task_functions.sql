BEGIN;

CREATE OR REPLACE FUNCTION app.assert_project_task_editable_project(p_project app.projects)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_project.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record not available.';
  END IF;
  IF p_project.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED', 'ACTIVE', 'ON_HOLD') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task changes are not allowed in this Project status.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.normalize_project_task_weight(
  p_counts_toward_completion boolean,
  p_weight_percent numeric
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_counts_toward_completion IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task completion-counting setting.';
  END IF;
  IF NOT p_counts_toward_completion AND p_weight_percent IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task weight is not allowed when completion counting is disabled.';
  END IF;
  IF p_weight_percent IS NOT NULL AND (p_weight_percent <= 0 OR p_weight_percent > 100) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task weight.';
  END IF;
  RETURN p_weight_percent;
END
$function$;

CREATE OR REPLACE FUNCTION app.create_project_task(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_title text,
  p_phase_id uuid DEFAULT NULL,
  p_milestone_id uuid DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_client_summary text DEFAULT NULL,
  p_weight_percent numeric DEFAULT NULL,
  p_counts_toward_completion boolean DEFAULT true,
  p_start_date date DEFAULT NULL,
  p_due_date date DEFAULT NULL,
  p_client_visible boolean DEFAULT true,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  task_id uuid,
  project_id uuid,
  task_number text,
  status text,
  completion_percent numeric,
  is_active boolean,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  project_row app.projects%ROWTYPE;
  normalized_title text := btrim(coalesce(p_title, ''));
  normalized_description text := app.normalize_project_optional_text(p_description, 4000);
  normalized_client_summary text := app.normalize_project_optional_text(p_client_summary, 4000);
  normalized_weight numeric;
  generated_task_number varchar(40);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF normalized_title = '' OR length(normalized_title) > 200 OR p_client_visible IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task.';
  END IF;
  normalized_weight := app.normalize_project_task_weight(p_counts_toward_completion, p_weight_percent);
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  PERFORM app.assert_project_task_editable_project(project_row);
  generated_task_number := app.generate_project_task_number(p_project_id);

  INSERT INTO app.tasks (
    project_id, phase_id, milestone_id, task_number, title, description, client_summary,
    weight_percent, counts_toward_completion, start_date, due_date, client_visible, created_by, updated_by
  )
  VALUES (
    p_project_id, p_phase_id, p_milestone_id, generated_task_number, normalized_title, normalized_description,
    normalized_client_summary, normalized_weight, p_counts_toward_completion, p_start_date, p_due_date,
    p_client_visible, actor_row.actor_user_id, actor_row.actor_user_id
  )
  RETURNING id, app.tasks.project_id, app.tasks.task_number::text, app.tasks.status::text, app.tasks.completion_percent, app.tasks.is_active, app.tasks.version_number
  INTO task_id, project_id, task_number, status, completion_percent, is_active, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_task_created', 'project_task', task_id, project_id, 'success',
    '{}'::jsonb,
    jsonb_build_object('project_id', project_id, 'task_id', task_id, 'task_number', task_number, 'phase_association_changed', p_phase_id IS NOT NULL, 'milestone_association_changed', p_milestone_id IS NOT NULL, 'date_changed', p_start_date IS NOT NULL OR p_due_date IS NOT NULL, 'client_visibility_changed', p_client_visible IS DISTINCT FROM true, 'completion_counting_changed', p_counts_toward_completion IS DISTINCT FROM true),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('changed_fields', ARRAY['title','description','client_summary','phase_id','milestone_id','weight_percent','counts_toward_completion','dates','client_visible'])
  );
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.update_project_task(
  p_actor_auth_subject uuid,
  p_task_id uuid,
  p_expected_version_number integer,
  p_title text,
  p_phase_id uuid DEFAULT NULL,
  p_milestone_id uuid DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_client_summary text DEFAULT NULL,
  p_weight_percent numeric DEFAULT NULL,
  p_counts_toward_completion boolean DEFAULT true,
  p_start_date date DEFAULT NULL,
  p_due_date date DEFAULT NULL,
  p_client_visible boolean DEFAULT true,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  task_id uuid,
  project_id uuid,
  task_number text,
  status text,
  completion_percent numeric,
  is_active boolean,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
  normalized_title text := btrim(coalesce(p_title, ''));
  normalized_description text := app.normalize_project_optional_text(p_description, 4000);
  normalized_client_summary text := app.normalize_project_optional_text(p_client_summary, 4000);
  normalized_weight numeric;
  changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF normalized_title = '' OR length(normalized_title) > 200 OR p_client_visible IS NULL OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task.';
  END IF;
  normalized_weight := app.normalize_project_task_weight(p_counts_toward_completion, p_weight_percent);

  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active OR existing_row.status <> 'TODO' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be updated.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.';
  END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_task_editable_project(project_row);

  IF existing_row.title IS DISTINCT FROM normalized_title THEN changed_fields := changed_fields || ARRAY['title']; END IF;
  IF existing_row.description IS DISTINCT FROM normalized_description THEN changed_fields := changed_fields || ARRAY['description']; END IF;
  IF existing_row.client_summary IS DISTINCT FROM normalized_client_summary THEN changed_fields := changed_fields || ARRAY['client_summary']; END IF;
  IF existing_row.phase_id IS DISTINCT FROM p_phase_id THEN changed_fields := changed_fields || ARRAY['phase_id']; END IF;
  IF existing_row.milestone_id IS DISTINCT FROM p_milestone_id THEN changed_fields := changed_fields || ARRAY['milestone_id']; END IF;
  IF existing_row.weight_percent IS DISTINCT FROM normalized_weight THEN changed_fields := changed_fields || ARRAY['weight_percent']; END IF;
  IF existing_row.counts_toward_completion IS DISTINCT FROM p_counts_toward_completion THEN changed_fields := changed_fields || ARRAY['counts_toward_completion']; END IF;
  IF existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.due_date IS DISTINCT FROM p_due_date THEN changed_fields := changed_fields || ARRAY['dates']; END IF;
  IF existing_row.client_visible IS DISTINCT FROM p_client_visible THEN changed_fields := changed_fields || ARRAY['client_visible']; END IF;

  IF array_length(changed_fields, 1) IS NULL THEN
    task_id := existing_row.id; project_id := existing_row.project_id; task_number := existing_row.task_number::text; status := existing_row.status::text; completion_percent := existing_row.completion_percent; is_active := existing_row.is_active; version_number := existing_row.version_number; RETURN NEXT; RETURN;
  END IF;

  UPDATE app.tasks AS t
  SET phase_id = p_phase_id,
      milestone_id = p_milestone_id,
      title = normalized_title,
      description = normalized_description,
      client_summary = normalized_client_summary,
      weight_percent = normalized_weight,
      counts_toward_completion = p_counts_toward_completion,
      start_date = p_start_date,
      due_date = p_due_date,
      client_visible = p_client_visible,
      updated_by = actor_row.actor_user_id
  WHERE t.id = p_task_id
  RETURNING t.id, t.project_id, t.task_number::text, t.status::text, t.completion_percent, t.is_active, t.version_number
  INTO task_id, project_id, task_number, status, completion_percent, is_active, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_task_updated', 'project_task', task_id, project_id, 'success',
    jsonb_build_object('version_number', existing_row.version_number),
    jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields, 'phase_association_changed', existing_row.phase_id IS DISTINCT FROM p_phase_id, 'milestone_association_changed', existing_row.milestone_id IS DISTINCT FROM p_milestone_id, 'date_changed', existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.due_date IS DISTINCT FROM p_due_date, 'client_visibility_changed', existing_row.client_visible IS DISTINCT FROM p_client_visible, 'completion_counting_changed', existing_row.counts_toward_completion IS DISTINCT FROM p_counts_toward_completion),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb
  );
  RETURN NEXT;
END
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
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.tasks%ROWTYPE;
  project_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task archival.';
  END IF;
  SELECT * INTO existing_row FROM app.tasks AS t WHERE t.id = p_task_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task cannot be archived.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project task version conflict.';
  END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  IF project_row.status = 'ARCHIVED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task archival is not allowed in this Project status.';
  END IF;
  PERFORM set_config('app.allow_project_task_archive', 'on', true);
  UPDATE app.tasks AS t
  SET is_active = false, updated_by = actor_row.actor_user_id
  WHERE t.id = p_task_id
  RETURNING t.id, t.project_id, t.task_number::text, t.status::text, t.is_active, t.version_number
  INTO task_id, project_id, task_number, status, is_active, version_number;
  PERFORM set_config('app.allow_project_task_archive', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_task_archived', 'project_task', task_id, project_id, 'success', jsonb_build_object('is_active', true, 'version_number', existing_row.version_number), jsonb_build_object('is_active', false, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_task_list(p_actor_auth_subject uuid, p_project_id uuid, p_include_inactive boolean DEFAULT true)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, description text, client_summary text, status text, completion_percent numeric, weight_percent numeric, counts_toward_completion boolean, start_date date, due_date date, completed_at timestamptz, client_visible boolean, is_active boolean, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT t.id, t.project_id, t.phase_id, t.milestone_id, t.task_number::text, t.title::text, t.description, t.client_summary, t.status::text, t.completion_percent, t.weight_percent, t.counts_toward_completion, t.start_date, t.due_date, t.completed_at, t.client_visible, t.is_active, t.created_at, t.created_by, t.updated_at, t.updated_by, t.version_number
  FROM app.tasks AS t
  WHERE t.project_id = p_project_id
    AND (coalesce(p_include_inactive, true) OR t.is_active)
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject))
  ORDER BY t.due_date ASC NULLS LAST, t.created_at ASC, t.id ASC;
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_task_detail(p_actor_auth_subject uuid, p_task_id uuid)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, description text, client_summary text, status text, completion_percent numeric, weight_percent numeric, counts_toward_completion boolean, start_date date, due_date date, completed_at timestamptz, client_visible boolean, is_active boolean, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT t.id, t.project_id, t.phase_id, t.milestone_id, t.task_number::text, t.title::text, t.description, t.client_summary, t.status::text, t.completion_percent, t.weight_percent, t.counts_toward_completion, t.start_date, t.due_date, t.completed_at, t.client_visible, t.is_active, t.created_at, t.created_by, t.updated_at, t.updated_by, t.version_number
  FROM app.tasks AS t
  WHERE t.id = p_task_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION app.current_client_project_tasks_for_authenticated_user(p_project_id uuid)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, client_summary text, status text, completion_percent numeric, start_date date, due_date date, completed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT t.id, t.project_id, t.phase_id, t.milestone_id, t.task_number::text, t.title::text, t.client_summary, t.status::text, t.completion_percent, t.start_date, t.due_date, t.completed_at
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  INNER JOIN app.tasks AS t ON t.project_id = p.id
  LEFT JOIN app.project_phases AS pp ON pp.id = t.phase_id
  LEFT JOIN app.project_milestones AS pm ON pm.id = t.milestone_id
  LEFT JOIN app.project_phases AS mpp ON mpp.id = pm.phase_id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT' AND u.status = 'ACTIVE' AND u.is_active
    AND c.status = 'ACTIVE' AND c.is_active AND c.archived_at IS NULL
    AND p.id = p_project_id
    AND t.is_active AND t.client_visible
    AND (t.phase_id IS NULL OR (pp.is_active AND pp.client_visible))
    AND (t.milestone_id IS NULL OR (pm.is_active AND pm.client_visible AND (pm.phase_id IS NULL OR (mpp.is_active AND mpp.client_visible))))
    AND EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
    AND NOT EXISTS (SELECT 1 FROM app.user_roles AS ur INNER JOIN app.roles AS r ON r.code = ur.role_code WHERE ur.user_id = u.id AND ur.is_active AND r.is_staff_role)
  ORDER BY t.due_date ASC NULLS LAST, t.created_at ASC, t.id ASC;
$function$;

CREATE OR REPLACE FUNCTION app.current_client_project_task_for_authenticated_user(p_task_id uuid)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, client_summary text, status text, completion_percent numeric, start_date date, due_date date, completed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT t.id, t.project_id, t.phase_id, t.milestone_id, t.task_number, t.title, t.client_summary, t.status, t.completion_percent, t.start_date, t.due_date, t.completed_at
  FROM app.current_client_project_tasks_for_authenticated_user(
    (SELECT project_id FROM app.tasks WHERE id = p_task_id AND is_active AND client_visible)
  ) AS t
  WHERE t.id = p_task_id;
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_tasks(p_project_id uuid)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, client_summary text, status text, completion_percent numeric, start_date date, due_date date, completed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_client_project_tasks_for_authenticated_user(p_project_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_task(p_task_id uuid)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, client_summary text, status text, completion_percent numeric, start_date date, due_date date, completed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_client_project_task_for_authenticated_user(p_task_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_create_project_task(p_verified_owner_auth_subject uuid, p_project_id uuid, p_title text, p_phase_id uuid DEFAULT NULL, p_milestone_id uuid DEFAULT NULL, p_description text DEFAULT NULL, p_client_summary text DEFAULT NULL, p_weight_percent numeric DEFAULT NULL, p_counts_toward_completion boolean DEFAULT true, p_start_date date DEFAULT NULL, p_due_date date DEFAULT NULL, p_client_visible boolean DEFAULT true, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, task_number text, status text, completion_percent numeric, is_active boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.create_project_task(p_verified_owner_auth_subject, p_project_id, p_title, p_phase_id, p_milestone_id, p_description, p_client_summary, p_weight_percent, p_counts_toward_completion, p_start_date, p_due_date, p_client_visible, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_update_project_task(p_verified_owner_auth_subject uuid, p_task_id uuid, p_expected_version_number integer, p_title text, p_phase_id uuid DEFAULT NULL, p_milestone_id uuid DEFAULT NULL, p_description text DEFAULT NULL, p_client_summary text DEFAULT NULL, p_weight_percent numeric DEFAULT NULL, p_counts_toward_completion boolean DEFAULT true, p_start_date date DEFAULT NULL, p_due_date date DEFAULT NULL, p_client_visible boolean DEFAULT true, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, task_number text, status text, completion_percent numeric, is_active boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.update_project_task(p_verified_owner_auth_subject, p_task_id, p_expected_version_number, p_title, p_phase_id, p_milestone_id, p_description, p_client_summary, p_weight_percent, p_counts_toward_completion, p_start_date, p_due_date, p_client_visible, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_archive_project_task(p_verified_owner_auth_subject uuid, p_task_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (task_id uuid, project_id uuid, task_number text, status text, is_active boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.archive_project_task(p_verified_owner_auth_subject, p_task_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_task_list(p_verified_owner_auth_subject uuid, p_project_id uuid, p_include_inactive boolean DEFAULT true)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, description text, client_summary text, status text, completion_percent numeric, weight_percent numeric, counts_toward_completion boolean, start_date date, due_date date, completed_at timestamptz, client_visible boolean, is_active boolean, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_task_list(p_verified_owner_auth_subject, p_project_id, p_include_inactive);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_task_detail(p_verified_owner_auth_subject uuid, p_task_id uuid)
RETURNS TABLE (id uuid, project_id uuid, phase_id uuid, milestone_id uuid, task_number text, title text, description text, client_summary text, status text, completion_percent numeric, weight_percent numeric, counts_toward_completion boolean, start_date date, due_date date, completed_at timestamptz, client_visible boolean, is_active boolean, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_task_detail(p_verified_owner_auth_subject, p_task_id);
$function$;

-- Dependency guards introduced by task history.
CREATE OR REPLACE FUNCTION app.change_project_client(p_actor_auth_subject uuid, p_project_id uuid, p_new_client_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, old_client_id uuid, new_client_id uuid, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project Client reassignment.'; END IF;
  PERFORM app.require_active_client_record(p_new_client_id);
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  IF existing_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record not available.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.'; END IF;
  IF existing_row.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed in this status.'; END IF;
  IF EXISTS (SELECT 1 FROM app.project_staff_assignments AS psa WHERE psa.project_id = p_project_id) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed after staff assignment history exists.'; END IF;
  IF EXISTS (SELECT 1 FROM app.project_phases AS pp WHERE pp.project_id = p_project_id) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed after phase history exists.'; END IF;
  IF EXISTS (SELECT 1 FROM app.project_milestones AS pm WHERE pm.project_id = p_project_id) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed after milestone history exists.'; END IF;
  IF EXISTS (SELECT 1 FROM app.tasks AS t WHERE t.project_id = p_project_id) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed after task history exists.'; END IF;
  IF existing_row.client_id = p_new_client_id THEN project_id := existing_row.id; old_client_id := existing_row.client_id; new_client_id := existing_row.client_id; version_number := existing_row.version_number; RETURN NEXT; RETURN; END IF;
  PERFORM set_config('app.allow_project_client_change', 'on', true);
  UPDATE app.projects AS p SET client_id = p_new_client_id, updated_by = actor_row.actor_user_id WHERE p.id = p_project_id RETURNING p.id, existing_row.client_id, p.client_id, p.version_number INTO project_id, old_client_id, new_client_id, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_client_changed', 'project_record', project_id, NULL, 'success', jsonb_build_object('client', '[masked]', 'version_number', existing_row.version_number), jsonb_build_object('client', '[masked]', 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('dependent_record_guard', 'project_staff_assignments,project_phases,project_milestones,tasks'));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.archive_project_phase(p_actor_auth_subject uuid, p_phase_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (phase_id uuid, project_id uuid, sequence_no integer, is_active boolean, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.project_phases%ROWTYPE; project_row app.projects%ROWTYPE; total_count integer; shifted_count integer;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase archival.'; END IF;
  SELECT * INTO existing_row FROM app.project_phases AS pp WHERE pp.id = p_phase_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase cannot be archived.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project phase version conflict.'; END IF;
  IF EXISTS (SELECT 1 FROM app.project_milestones AS pm WHERE pm.phase_id = p_phase_id AND pm.is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase cannot be archived while active milestones reference it.'; END IF;
  IF EXISTS (SELECT 1 FROM app.tasks AS t WHERE t.phase_id = p_phase_id AND t.is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase cannot be archived while active tasks reference it.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  IF project_row.id IS NULL OR project_row.status = 'ARCHIVED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase archival is not allowed in this Project status.'; END IF;
  SET CONSTRAINTS app.project_phases_project_sequence_uk DEFERRED;
  PERFORM 1 FROM app.project_phases AS pp WHERE pp.project_id = existing_row.project_id FOR UPDATE;
  SELECT count(*)::integer INTO total_count FROM app.project_phases AS pp WHERE pp.project_id = existing_row.project_id;
  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'on', true);
  UPDATE app.project_phases AS pp SET sequence_no = pp.sequence_no - 1, updated_by = actor_row.actor_user_id WHERE pp.project_id = existing_row.project_id AND pp.sequence_no > existing_row.sequence_no;
  GET DIAGNOSTICS shifted_count = ROW_COUNT;
  PERFORM set_config('app.allow_project_phase_archive', 'on', true);
  UPDATE app.project_phases AS pp SET is_active = false, sequence_no = total_count, updated_by = actor_row.actor_user_id WHERE pp.id = p_phase_id RETURNING pp.id, pp.project_id, pp.sequence_no, pp.is_active, pp.version_number INTO phase_id, project_id, sequence_no, is_active, version_number;
  PERFORM set_config('app.allow_project_phase_archive', 'off', true);
  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_phase_archived', 'project_phase', phase_id, project_id, 'success', jsonb_build_object('sequence_no', existing_row.sequence_no, 'is_active', true, 'version_number', existing_row.version_number), jsonb_build_object('sequence_no', sequence_no, 'is_active', false, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('affected_phase_count', shifted_count + 1));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.archive_project_milestone(p_actor_auth_subject uuid, p_milestone_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (milestone_id uuid, project_id uuid, phase_id uuid, is_active boolean, completed_at timestamptz, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.project_milestones%ROWTYPE; project_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project milestone archival.'; END IF;
  SELECT * INTO existing_row FROM app.project_milestones AS pm WHERE pm.id = p_milestone_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone cannot be archived.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project milestone version conflict.'; END IF;
  IF EXISTS (SELECT 1 FROM app.tasks AS t WHERE t.milestone_id = p_milestone_id AND t.is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone cannot be archived while active tasks reference it.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  IF project_row.status = 'ARCHIVED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone archival is not allowed in this Project status.'; END IF;
  PERFORM set_config('app.allow_project_milestone_archive', 'on', true);
  UPDATE app.project_milestones AS pm SET is_active = false, updated_by = actor_row.actor_user_id WHERE pm.id = p_milestone_id RETURNING pm.id, pm.project_id, pm.phase_id, pm.is_active, pm.completed_at, pm.version_number INTO milestone_id, project_id, phase_id, is_active, completed_at, version_number;
  PERFORM set_config('app.allow_project_milestone_archive', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_milestone_archived', 'project_milestone', milestone_id, project_id, 'success', jsonb_build_object('is_active', true, 'version_number', existing_row.version_number), jsonb_build_object('is_active', false, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('completion_state_changed', false));
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

CREATE OR REPLACE FUNCTION app.update_project_record(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_expected_version_number integer,
  p_name text,
  p_reporting_currency_code char(3),
  p_project_type text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_contract_amount numeric DEFAULT NULL,
  p_contract_currency_code char(3) DEFAULT NULL,
  p_budget_amount numeric DEFAULT NULL,
  p_budget_currency_code char(3) DEFAULT NULL,
  p_client_visible_summary text DEFAULT NULL,
  p_internal_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (project_id uuid, project_number text, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.projects%ROWTYPE; normalized_name text := btrim(coalesce(p_name, '')); changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF normalized_name = '' OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project record.'; END IF;
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  PERFORM app.assert_project_updateable(existing_row);
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.'; END IF;
  IF (existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date)
     AND EXISTS (SELECT 1 FROM app.project_phases AS pp WHERE pp.project_id = p_project_id AND ((p_start_date IS NOT NULL AND pp.start_date IS NOT NULL AND pp.start_date < p_start_date) OR (p_end_date IS NOT NULL AND pp.end_date IS NOT NULL AND pp.end_date > p_end_date))) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project dates cannot exclude existing phase history.';
  END IF;
  IF (existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date)
     AND EXISTS (SELECT 1 FROM app.project_milestones AS pm WHERE pm.project_id = p_project_id AND pm.due_date IS NOT NULL AND ((p_start_date IS NOT NULL AND pm.due_date < p_start_date) OR (p_end_date IS NOT NULL AND pm.due_date > p_end_date))) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project dates cannot exclude existing milestone history.';
  END IF;
  IF (existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date)
     AND EXISTS (SELECT 1 FROM app.tasks AS t WHERE t.project_id = p_project_id AND ((p_start_date IS NOT NULL AND t.start_date IS NOT NULL AND t.start_date < p_start_date) OR (p_start_date IS NOT NULL AND t.due_date IS NOT NULL AND t.due_date < p_start_date) OR (p_end_date IS NOT NULL AND t.start_date IS NOT NULL AND t.start_date > p_end_date) OR (p_end_date IS NOT NULL AND t.due_date IS NOT NULL AND t.due_date > p_end_date))) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project dates cannot exclude existing task history.';
  END IF;
  IF existing_row.name IS DISTINCT FROM normalized_name THEN changed_fields := changed_fields || ARRAY['name']; END IF;
  IF existing_row.project_type IS DISTINCT FROM app.normalize_project_optional_text(p_project_type, 80) THEN changed_fields := changed_fields || ARRAY['project_type']; END IF;
  IF existing_row.location IS DISTINCT FROM app.normalize_project_optional_text(p_location, 500) THEN changed_fields := changed_fields || ARRAY['location']; END IF;
  IF existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date THEN changed_fields := changed_fields || ARRAY['dates']; END IF;
  IF existing_row.contract_amount IS DISTINCT FROM p_contract_amount OR existing_row.contract_currency_code IS DISTINCT FROM p_contract_currency_code OR existing_row.budget_amount IS DISTINCT FROM p_budget_amount OR existing_row.budget_currency_code IS DISTINCT FROM p_budget_currency_code OR existing_row.reporting_currency_code IS DISTINCT FROM p_reporting_currency_code THEN changed_fields := changed_fields || ARRAY['monetary_metadata']; END IF;
  IF existing_row.client_visible_summary IS DISTINCT FROM app.normalize_project_optional_text(p_client_visible_summary, 1200) THEN changed_fields := changed_fields || ARRAY['client_visible_summary']; END IF;
  IF existing_row.internal_notes IS DISTINCT FROM app.normalize_project_optional_text(p_internal_notes, 4000) THEN changed_fields := changed_fields || ARRAY['internal_notes']; END IF;
  UPDATE app.projects AS p
  SET name = normalized_name, project_type = app.normalize_project_optional_text(p_project_type, 80), location = app.normalize_project_optional_text(p_location, 500), start_date = p_start_date, end_date = p_end_date, contract_amount = p_contract_amount, contract_currency_code = p_contract_currency_code, budget_amount = p_budget_amount, budget_currency_code = p_budget_currency_code, reporting_currency_code = p_reporting_currency_code, client_visible_summary = app.normalize_project_optional_text(p_client_visible_summary, 1200), internal_notes = app.normalize_project_optional_text(p_internal_notes, 4000), updated_by = actor_row.actor_user_id
  WHERE p.id = p_project_id
  RETURNING p.id, p.project_number::text, p.status::text, p.version_number INTO project_id, project_number, status, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_record_updated', 'project_record', project_id, NULL, 'success', jsonb_build_object('version_number', existing_row.version_number), jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.update_project_phase(p_actor_auth_subject uuid, p_phase_id uuid, p_expected_version_number integer, p_name text, p_description text DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_client_visible boolean DEFAULT true, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (phase_id uuid, project_id uuid, sequence_no integer, is_active boolean, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.project_phases%ROWTYPE; project_row app.projects%ROWTYPE; normalized_name text := btrim(coalesce(p_name, '')); normalized_description text := app.normalize_project_optional_text(p_description, 4000); changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF normalized_name = '' OR length(normalized_name) > 160 OR p_client_visible IS NULL OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase.'; END IF;
  SELECT * INTO existing_row FROM app.project_phases AS pp WHERE pp.id = p_phase_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase cannot be updated.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project phase version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_phase_editable(project_row);
  PERFORM app.assert_project_phase_dates(project_row, p_start_date, p_end_date);
  IF (existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date)
     AND EXISTS (SELECT 1 FROM app.project_milestones AS pm WHERE pm.phase_id = p_phase_id AND pm.due_date IS NOT NULL AND ((p_start_date IS NOT NULL AND pm.due_date < p_start_date) OR (p_end_date IS NOT NULL AND pm.due_date > p_end_date))) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase dates cannot exclude existing milestone history.';
  END IF;
  IF (existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date)
     AND EXISTS (SELECT 1 FROM app.tasks AS t WHERE t.phase_id = p_phase_id AND ((p_start_date IS NOT NULL AND t.start_date IS NOT NULL AND t.start_date < p_start_date) OR (p_start_date IS NOT NULL AND t.due_date IS NOT NULL AND t.due_date < p_start_date) OR (p_end_date IS NOT NULL AND t.start_date IS NOT NULL AND t.start_date > p_end_date) OR (p_end_date IS NOT NULL AND t.due_date IS NOT NULL AND t.due_date > p_end_date))) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase dates cannot exclude existing task history.';
  END IF;
  IF existing_row.name IS DISTINCT FROM normalized_name THEN changed_fields := changed_fields || ARRAY['name']; END IF;
  IF existing_row.description IS DISTINCT FROM normalized_description THEN changed_fields := changed_fields || ARRAY['description']; END IF;
  IF existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date THEN changed_fields := changed_fields || ARRAY['dates']; END IF;
  IF existing_row.client_visible IS DISTINCT FROM p_client_visible THEN changed_fields := changed_fields || ARRAY['client_visible']; END IF;
  IF array_length(changed_fields, 1) IS NULL THEN phase_id := existing_row.id; project_id := existing_row.project_id; sequence_no := existing_row.sequence_no; is_active := existing_row.is_active; version_number := existing_row.version_number; RETURN NEXT; RETURN; END IF;
  UPDATE app.project_phases AS pp SET name = normalized_name, description = normalized_description, start_date = p_start_date, end_date = p_end_date, client_visible = p_client_visible, updated_by = actor_row.actor_user_id WHERE pp.id = p_phase_id RETURNING pp.id, pp.project_id, pp.sequence_no, pp.is_active, pp.version_number INTO phase_id, project_id, sequence_no, is_active, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_phase_updated', 'project_phase', phase_id, project_id, 'success', jsonb_build_object('version_number', existing_row.version_number), jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields, 'client_visibility_changed', existing_row.client_visible IS DISTINCT FROM p_client_visible), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.update_project_milestone(p_actor_auth_subject uuid, p_milestone_id uuid, p_expected_version_number integer, p_name text, p_phase_id uuid DEFAULT NULL, p_description text DEFAULT NULL, p_due_date date DEFAULT NULL, p_client_visible boolean DEFAULT true, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (milestone_id uuid, project_id uuid, phase_id uuid, is_active boolean, completed_at timestamptz, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.project_milestones%ROWTYPE; project_row app.projects%ROWTYPE; normalized_name text := btrim(coalesce(p_name, '')); normalized_description text := app.normalize_project_optional_text(p_description, 4000); changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF normalized_name = '' OR length(normalized_name) > 160 OR p_client_visible IS NULL OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project milestone.'; END IF;
  SELECT * INTO existing_row FROM app.project_milestones AS pm WHERE pm.id = p_milestone_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active OR existing_row.completed_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone cannot be updated.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project milestone version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_milestone_editable_project(project_row);
  PERFORM app.assert_project_milestone_due_date(project_row, p_phase_id, p_due_date);
  IF existing_row.phase_id IS DISTINCT FROM p_phase_id
     AND EXISTS (
       SELECT 1 FROM app.tasks AS t
       WHERE t.milestone_id = p_milestone_id
         AND (
           (p_phase_id IS NULL AND t.phase_id IS NOT NULL)
           OR (p_phase_id IS NOT NULL AND t.phase_id IS NOT NULL AND t.phase_id <> p_phase_id)
         )
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone phase cannot change while task history would become inconsistent.';
  END IF;
  IF existing_row.name IS DISTINCT FROM normalized_name THEN changed_fields := changed_fields || ARRAY['name']; END IF;
  IF existing_row.description IS DISTINCT FROM normalized_description THEN changed_fields := changed_fields || ARRAY['description']; END IF;
  IF existing_row.phase_id IS DISTINCT FROM p_phase_id THEN changed_fields := changed_fields || ARRAY['phase_id']; END IF;
  IF existing_row.due_date IS DISTINCT FROM p_due_date THEN changed_fields := changed_fields || ARRAY['due_date']; END IF;
  IF existing_row.client_visible IS DISTINCT FROM p_client_visible THEN changed_fields := changed_fields || ARRAY['client_visible']; END IF;
  IF array_length(changed_fields, 1) IS NULL THEN milestone_id := existing_row.id; project_id := existing_row.project_id; phase_id := existing_row.phase_id; is_active := existing_row.is_active; completed_at := existing_row.completed_at; version_number := existing_row.version_number; RETURN NEXT; RETURN; END IF;
  UPDATE app.project_milestones AS pm SET phase_id = p_phase_id, name = normalized_name, description = normalized_description, due_date = p_due_date, client_visible = p_client_visible, updated_by = actor_row.actor_user_id WHERE pm.id = p_milestone_id RETURNING pm.id, pm.project_id, pm.phase_id, pm.is_active, pm.completed_at, pm.version_number INTO milestone_id, project_id, phase_id, is_active, completed_at, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_milestone_updated', 'project_milestone', milestone_id, project_id, 'success', jsonb_build_object('version_number', existing_row.version_number), jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields, 'phase_association_changed', existing_row.phase_id IS DISTINCT FROM p_phase_id, 'due_date_changed', existing_row.due_date IS DISTINCT FROM p_due_date, 'client_visibility_changed', existing_row.client_visible IS DISTINCT FROM p_client_visible), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

COMMIT;
