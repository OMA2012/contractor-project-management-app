BEGIN;

CREATE OR REPLACE FUNCTION app.assert_progress_update_project_writable(p_project app.projects)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_project.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record is not available.';
  END IF;
  IF p_project.status IN ('COMPLETED', 'CANCELLED', 'ARCHIVED') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress updates are not allowed in this Project status.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.assert_progress_update_milestone(
  p_project_id uuid,
  p_milestone_id uuid,
  p_require_active boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  milestone_row app.project_milestones%ROWTYPE;
BEGIN
  IF p_milestone_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO milestone_row
  FROM app.project_milestones AS pm
  WHERE pm.id = p_milestone_id;

  IF milestone_row.id IS NULL OR milestone_row.project_id <> p_project_id THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update milestone must belong to the same Project.';
  END IF;
  IF p_require_active AND NOT milestone_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update requires an active milestone.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.assert_project_client_readable_for_progress(p_project_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app.projects AS p
    INNER JOIN app.clients AS c ON c.id = p.client_id
    INNER JOIN app.users AS u ON u.id = c.portal_user_id
    WHERE p.id = p_project_id
      AND c.status = 'ACTIVE'
      AND c.is_active
      AND c.archived_at IS NULL
      AND u.status = 'ACTIVE'
      AND u.is_active
      AND EXISTS (
        SELECT 1 FROM app.user_roles AS ur
        WHERE ur.user_id = u.id
          AND ur.role_code = 'client'
          AND ur.is_active
      )
      AND NOT EXISTS (
        SELECT 1
        FROM app.user_roles AS ur
        INNER JOIN app.roles AS r ON r.code = ur.role_code
        WHERE ur.user_id = u.id
          AND ur.is_active
          AND r.is_staff_role
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be published for this Project Client.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_progress_update(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_milestone_id uuid,
  p_title text,
  p_summary text,
  p_reported_completion_percent numeric,
  p_client_visible boolean DEFAULT false,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  progress_update_id uuid,
  project_id uuid,
  status text,
  client_visible boolean,
  version_number integer,
  created_at timestamptz,
  created_by uuid
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
  normalized_summary text := btrim(coalesce(p_summary, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF normalized_title = '' OR length(normalized_title) > 200 OR normalized_summary = '' OR p_client_visible IS NULL
     OR (p_reported_completion_percent IS NOT NULL AND (p_reported_completion_percent < 0 OR p_reported_completion_percent > 100)) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid progress update.';
  END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  PERFORM app.assert_progress_update_project_writable(project_row);
  PERFORM app.assert_progress_update_milestone(project_row.id, p_milestone_id, true);

  INSERT INTO app.progress_updates (
    project_id, milestone_id, title, summary, reported_completion_percent,
    client_visible, created_by, updated_by
  )
  VALUES (
    project_row.id, p_milestone_id, normalized_title, normalized_summary,
    p_reported_completion_percent, p_client_visible, actor_row.actor_user_id, actor_row.actor_user_id
  )
  RETURNING id, app.progress_updates.project_id, app.progress_updates.status::text, app.progress_updates.client_visible,
            app.progress_updates.version_number, app.progress_updates.created_at, app.progress_updates.created_by
  INTO progress_update_id, project_id, status, client_visible, version_number, created_at, created_by;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'progress_update_created', 'progress_update', progress_update_id, project_id, 'success',
    '{}'::jsonb,
    jsonb_build_object('status', status, 'client_visible', client_visible, 'reported_completion_percent', p_reported_completion_percent),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('project_id', project_id, 'progress_update_id', progress_update_id, 'milestone_id', p_milestone_id)
  );
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_progress_update_draft(
  p_actor_auth_subject uuid,
  p_progress_update_id uuid,
  p_expected_version_number integer,
  p_milestone_id uuid,
  p_title text,
  p_summary text,
  p_reported_completion_percent numeric,
  p_client_visible boolean,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, client_visible boolean, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.progress_updates%ROWTYPE;
  project_row app.projects%ROWTYPE;
  normalized_title text := btrim(coalesce(p_title, ''));
  normalized_summary text := btrim(coalesce(p_summary, ''));
  changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 OR normalized_title = '' OR length(normalized_title) > 200
     OR normalized_summary = '' OR p_client_visible IS NULL
     OR (p_reported_completion_percent IS NOT NULL AND (p_reported_completion_percent < 0 OR p_reported_completion_percent > 100)) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid progress update.';
  END IF;

  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status <> 'DRAFT' OR existing_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be edited.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.';
  END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_progress_update_project_writable(project_row);
  PERFORM app.assert_progress_update_milestone(project_row.id, p_milestone_id, true);

  IF existing_row.title IS DISTINCT FROM normalized_title THEN changed_fields := changed_fields || ARRAY['title']; END IF;
  IF existing_row.summary IS DISTINCT FROM normalized_summary THEN changed_fields := changed_fields || ARRAY['summary']; END IF;
  IF existing_row.reported_completion_percent IS DISTINCT FROM p_reported_completion_percent THEN changed_fields := changed_fields || ARRAY['reported_completion_percent']; END IF;
  IF existing_row.milestone_id IS DISTINCT FROM p_milestone_id THEN changed_fields := changed_fields || ARRAY['milestone_id']; END IF;
  IF existing_row.client_visible IS DISTINCT FROM p_client_visible THEN changed_fields := changed_fields || ARRAY['client_visible']; END IF;

  IF array_length(changed_fields, 1) IS NULL THEN
    progress_update_id := existing_row.id; project_id := existing_row.project_id; status := existing_row.status::text; client_visible := existing_row.client_visible; version_number := existing_row.version_number; RETURN NEXT; RETURN;
  END IF;

  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu
  SET milestone_id = p_milestone_id,
      title = normalized_title,
      summary = normalized_summary,
      reported_completion_percent = p_reported_completion_percent,
      client_visible = p_client_visible,
      updated_by = actor_row.actor_user_id
  WHERE pu.id = p_progress_update_id
  RETURNING pu.id, pu.project_id, pu.status::text, pu.client_visible, pu.version_number
  INTO progress_update_id, project_id, status, client_visible, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'progress_update_updated', 'progress_update', progress_update_id, project_id, 'success',
    jsonb_build_object('version_number', existing_row.version_number),
    jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields, 'client_visible', client_visible, 'reported_completion_percent', p_reported_completion_percent),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_submit_progress_update(p_actor_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.progress_updates%ROWTYPE; project_row app.projects%ROWTYPE; workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status <> 'DRAFT' OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be submitted.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_progress_update_project_writable(project_row);
  PERFORM app.assert_progress_update_milestone(project_row.id, existing_row.milestone_id, true);
  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu SET status = 'SUBMITTED', submitted_at = workflow_at, submitted_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE pu.id = p_progress_update_id RETURNING pu.id, pu.project_id, pu.status::text, pu.version_number INTO progress_update_id, project_id, status, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'progress_update_submitted', 'progress_update', progress_update_id, project_id, 'success', jsonb_build_object('status','DRAFT','version_number',existing_row.version_number), jsonb_build_object('status',status,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_approve_progress_update(p_actor_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.progress_updates%ROWTYPE; project_row app.projects%ROWTYPE; workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status <> 'SUBMITTED' OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be approved.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.'; END IF;
  IF existing_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Progress update requires different Owner approval.'; END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_progress_update_project_writable(project_row);
  PERFORM app.assert_progress_update_milestone(project_row.id, existing_row.milestone_id, false);
  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu SET status = 'APPROVED', approved_at = workflow_at, approved_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE pu.id = p_progress_update_id RETURNING pu.id, pu.project_id, pu.status::text, pu.version_number INTO progress_update_id, project_id, status, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'progress_update_approved', 'progress_update', progress_update_id, project_id, 'success', jsonb_build_object('status','SUBMITTED','version_number',existing_row.version_number), jsonb_build_object('status',status,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_reject_progress_update(p_actor_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.progress_updates%ROWTYPE; reason_text text := btrim(coalesce(p_rejection_reason,'')); workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update rejection reason is required.'; END IF;
  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status <> 'SUBMITTED' OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be rejected.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.'; END IF;
  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu SET status = 'REJECTED', rejected_at = workflow_at, rejected_by = actor_row.actor_user_id, rejection_reason = reason_text, updated_by = actor_row.actor_user_id WHERE pu.id = p_progress_update_id RETURNING pu.id, pu.project_id, pu.status::text, pu.version_number INTO progress_update_id, project_id, status, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'progress_update_rejected', 'progress_update', progress_update_id, project_id, 'success', jsonb_build_object('status','SUBMITTED','version_number',existing_row.version_number), jsonb_build_object('status',status,'version_number',version_number), reason_text, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_set_progress_update_client_visibility(p_actor_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_client_visible boolean, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, client_visible boolean, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.progress_updates%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_client_visible IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid progress update visibility.'; END IF;
  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status <> 'APPROVED' OR existing_row.published_at IS NOT NULL OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update visibility cannot be changed.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.'; END IF;
  IF existing_row.client_visible IS NOT DISTINCT FROM p_client_visible THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update visibility is unchanged.'; END IF;
  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu SET client_visible = p_client_visible, updated_by = actor_row.actor_user_id WHERE pu.id = p_progress_update_id RETURNING pu.id, pu.project_id, pu.client_visible, pu.version_number INTO progress_update_id, project_id, client_visible, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'progress_update_client_visibility_changed', 'progress_update', progress_update_id, project_id, 'success', jsonb_build_object('client_visible', existing_row.client_visible, 'version_number', existing_row.version_number), jsonb_build_object('client_visible', client_visible, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_publish_progress_update(p_actor_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, published_at timestamptz, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.progress_updates%ROWTYPE; workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status <> 'APPROVED' OR NOT existing_row.client_visible OR existing_row.approved_at IS NULL OR existing_row.approved_by IS NULL OR existing_row.published_at IS NOT NULL OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be published.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.'; END IF;
  PERFORM app.assert_project_client_readable_for_progress(existing_row.project_id);
  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu SET published_at = workflow_at, updated_by = actor_row.actor_user_id WHERE pu.id = p_progress_update_id RETURNING pu.id, pu.project_id, pu.published_at, pu.version_number INTO progress_update_id, project_id, published_at, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'progress_update_published', 'progress_update', progress_update_id, project_id, 'success', jsonb_build_object('published', false, 'version_number', existing_row.version_number), jsonb_build_object('published', true, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_archive_progress_update(p_actor_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, archived_at timestamptz, archived_by uuid, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.progress_updates%ROWTYPE; workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status NOT IN ('APPROVED','REJECTED') OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be archived.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.'; END IF;
  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu SET archived_at = workflow_at, archived_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE pu.id = p_progress_update_id RETURNING pu.id, pu.project_id, pu.archived_at, pu.archived_by, pu.version_number INTO progress_update_id, project_id, archived_at, archived_by, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'progress_update_archived', 'progress_update', progress_update_id, project_id, 'success', jsonb_build_object('archived', false, 'version_number', existing_row.version_number), jsonb_build_object('archived', true, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_progress_update_list(p_actor_auth_subject uuid, p_project_id uuid DEFAULT NULL, p_status app.progress_update_status DEFAULT NULL, p_include_archived boolean DEFAULT true, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), status text, client_visible boolean, submitted_at timestamptz, submitted_by uuid, approved_at timestamptz, approved_by uuid, rejected_at timestamptz, rejected_by uuid, rejection_reason text, published_at timestamptz, archived_at timestamptz, archived_by uuid, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT pu.id, pu.project_id, pu.milestone_id, pu.title::text, pu.summary, pu.reported_completion_percent, pu.status::text, pu.client_visible, pu.submitted_at, pu.submitted_by, pu.approved_at, pu.approved_by, pu.rejected_at, pu.rejected_by, pu.rejection_reason, pu.published_at, pu.archived_at, pu.archived_by, pu.created_at, pu.created_by, pu.updated_at, pu.updated_by, pu.version_number
  FROM app.progress_updates AS pu
  WHERE EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject))
    AND (p_project_id IS NULL OR pu.project_id = p_project_id)
    AND (p_status IS NULL OR pu.status = p_status)
    AND (coalesce(p_include_archived, true) OR pu.archived_at IS NULL)
    AND p_limit BETWEEN 1 AND 100
    AND p_offset >= 0
  ORDER BY pu.created_at DESC, pu.id DESC
  LIMIT p_limit OFFSET p_offset;
$function$;

CREATE OR REPLACE FUNCTION app.owner_progress_update_detail(p_actor_auth_subject uuid, p_progress_update_id uuid)
RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), status text, client_visible boolean, submitted_at timestamptz, submitted_by uuid, approved_at timestamptz, approved_by uuid, rejected_at timestamptz, rejected_by uuid, rejection_reason text, published_at timestamptz, archived_at timestamptz, archived_by uuid, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT pu.id, pu.project_id, pu.milestone_id, pu.title::text, pu.summary, pu.reported_completion_percent, pu.status::text, pu.client_visible, pu.submitted_at, pu.submitted_by, pu.approved_at, pu.approved_by, pu.rejected_at, pu.rejected_by, pu.rejection_reason, pu.published_at, pu.archived_at, pu.archived_by, pu.created_at, pu.created_by, pu.updated_at, pu.updated_by, pu.version_number
  FROM app.progress_updates AS pu
  WHERE pu.id = p_progress_update_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION app.current_client_progress_update_list_for_authenticated_user(p_project_id uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), published_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT pu.id, pu.project_id,
    CASE
      WHEN pm.id IS NOT NULL
           AND pm.is_active
           AND pm.client_visible
           AND (pm.phase_id IS NULL OR (phase_row.is_active AND phase_row.client_visible))
        THEN pu.milestone_id
      ELSE NULL::uuid
    END,
    pu.title::text, pu.summary, pu.reported_completion_percent, pu.published_at
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  INNER JOIN app.progress_updates AS pu ON pu.project_id = p.id
  LEFT JOIN app.project_milestones AS pm ON pm.id = pu.milestone_id AND pm.project_id = p.id
  LEFT JOIN app.project_phases AS phase_row ON phase_row.id = pm.phase_id AND phase_row.project_id = p.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT' AND u.status = 'ACTIVE' AND u.is_active
    AND c.status = 'ACTIVE' AND c.is_active AND c.archived_at IS NULL
    AND p.id = p_project_id
    AND pu.status = 'APPROVED' AND pu.client_visible AND pu.published_at IS NOT NULL AND pu.archived_at IS NULL
    AND p_limit BETWEEN 1 AND 100 AND p_offset >= 0
    AND EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
    AND NOT EXISTS (SELECT 1 FROM app.user_roles AS ur INNER JOIN app.roles AS r ON r.code = ur.role_code WHERE ur.user_id = u.id AND ur.is_active AND r.is_staff_role)
  ORDER BY pu.published_at DESC, pu.id DESC
  LIMIT p_limit OFFSET p_offset;
$function$;

CREATE OR REPLACE FUNCTION app.current_client_progress_update_detail_for_authenticated_user(p_progress_update_id uuid)
RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), published_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT pu.*
  FROM app.current_client_progress_update_list_for_authenticated_user(
    (SELECT project_id FROM app.progress_updates WHERE id = p_progress_update_id AND status = 'APPROVED' AND client_visible AND published_at IS NOT NULL AND archived_at IS NULL),
    100,
    0
  ) AS pu
  WHERE pu.id = p_progress_update_id;
$function$;

CREATE OR REPLACE FUNCTION public.current_client_progress_update_list(p_project_id uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), published_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_client_progress_update_list_for_authenticated_user(p_project_id, p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_progress_update_detail(p_progress_update_id uuid)
RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), published_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_client_progress_update_detail_for_authenticated_user(p_progress_update_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_progress_update(p_verified_owner_auth_subject uuid, p_project_id uuid, p_milestone_id uuid, p_title text, p_summary text, p_reported_completion_percent numeric, p_client_visible boolean DEFAULT false, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, client_visible boolean, version_number integer, created_at timestamptz, created_by uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_progress_update(p_verified_owner_auth_subject,p_project_id,p_milestone_id,p_title,p_summary,p_reported_completion_percent,p_client_visible,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;

CREATE OR REPLACE FUNCTION public.server_owner_update_progress_update_draft(p_verified_owner_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_milestone_id uuid, p_title text, p_summary text, p_reported_completion_percent numeric, p_client_visible boolean, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, client_visible boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_progress_update_draft(p_verified_owner_auth_subject,p_progress_update_id,p_expected_version_number,p_milestone_id,p_title,p_summary,p_reported_completion_percent,p_client_visible,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;

CREATE OR REPLACE FUNCTION public.server_owner_submit_progress_update(p_verified_owner_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_progress_update(p_verified_owner_auth_subject,p_progress_update_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_progress_update(p_verified_owner_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_progress_update(p_verified_owner_auth_subject,p_progress_update_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_progress_update(p_verified_owner_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (progress_update_id uuid, project_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_progress_update(p_verified_owner_auth_subject,p_progress_update_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_set_progress_update_client_visibility(p_verified_owner_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_client_visible boolean, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (progress_update_id uuid, project_id uuid, client_visible boolean, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_set_progress_update_client_visibility(p_verified_owner_auth_subject,p_progress_update_id,p_expected_version_number,p_client_visible,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_publish_progress_update(p_verified_owner_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (progress_update_id uuid, project_id uuid, published_at timestamptz, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_publish_progress_update(p_verified_owner_auth_subject,p_progress_update_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_archive_progress_update(p_verified_owner_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (progress_update_id uuid, project_id uuid, archived_at timestamptz, archived_by uuid, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_archive_progress_update(p_verified_owner_auth_subject,p_progress_update_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_progress_update_list(p_verified_owner_auth_subject uuid, p_project_id uuid DEFAULT NULL, p_status app.progress_update_status DEFAULT NULL, p_include_archived boolean DEFAULT true, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), status text, client_visible boolean, submitted_at timestamptz, submitted_by uuid, approved_at timestamptz, approved_by uuid, rejected_at timestamptz, rejected_by uuid, rejection_reason text, published_at timestamptz, archived_at timestamptz, archived_by uuid, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_progress_update_list(p_verified_owner_auth_subject,p_project_id,p_status,p_include_archived,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_progress_update_detail(p_verified_owner_auth_subject uuid, p_progress_update_id uuid) RETURNS TABLE (id uuid, project_id uuid, milestone_id uuid, title text, summary text, reported_completion_percent numeric(5,2), status text, client_visible boolean, submitted_at timestamptz, submitted_by uuid, approved_at timestamptz, approved_by uuid, rejected_at timestamptz, rejected_by uuid, rejection_reason text, published_at timestamptz, archived_at timestamptz, archived_by uuid, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_progress_update_detail(p_verified_owner_auth_subject,p_progress_update_id); $function$;

COMMIT;
