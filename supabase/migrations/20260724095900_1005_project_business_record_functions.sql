BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_project_optional_text(p_value text, p_max_length integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN NULLIF(btrim(p_value), '') IS NULL THEN NULL
    WHEN length(btrim(p_value)) > p_max_length THEN
      trim(substring(btrim(p_value) FROM 1 FOR p_max_length))
    ELSE btrim(p_value)
  END;
$function$;

CREATE OR REPLACE FUNCTION app.require_active_client_record(p_client_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app.clients AS c
    WHERE c.id = p_client_id
      AND c.status = 'ACTIVE'
      AND c.is_active
      AND c.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project requires an active Client record.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.assert_project_updateable(p_project app.projects)
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
  IF p_project.status IN ('COMPLETED', 'CANCELLED', 'ARCHIVED') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record is read-only.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.is_allowed_project_transition(
  p_from app.project_record_status,
  p_to app.project_record_status
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT (p_from, p_to) IN (
    ('DRAFT'::app.project_record_status, 'QUOTATION'::app.project_record_status),
    ('DRAFT'::app.project_record_status, 'APPROVED'::app.project_record_status),
    ('DRAFT'::app.project_record_status, 'CANCELLED'::app.project_record_status),
    ('QUOTATION'::app.project_record_status, 'DRAFT'::app.project_record_status),
    ('QUOTATION'::app.project_record_status, 'APPROVED'::app.project_record_status),
    ('QUOTATION'::app.project_record_status, 'CANCELLED'::app.project_record_status),
    ('APPROVED'::app.project_record_status, 'ACTIVE'::app.project_record_status),
    ('APPROVED'::app.project_record_status, 'CANCELLED'::app.project_record_status),
    ('ACTIVE'::app.project_record_status, 'ON_HOLD'::app.project_record_status),
    ('ACTIVE'::app.project_record_status, 'COMPLETED'::app.project_record_status),
    ('ACTIVE'::app.project_record_status, 'CANCELLED'::app.project_record_status),
    ('ON_HOLD'::app.project_record_status, 'ACTIVE'::app.project_record_status),
    ('ON_HOLD'::app.project_record_status, 'CANCELLED'::app.project_record_status),
    ('COMPLETED'::app.project_record_status, 'ARCHIVED'::app.project_record_status),
    ('CANCELLED'::app.project_record_status, 'ARCHIVED'::app.project_record_status)
  );
$function$;

CREATE OR REPLACE FUNCTION app.create_project_record(
  p_actor_auth_subject uuid,
  p_client_id uuid,
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
RETURNS TABLE (
  project_id uuid,
  project_number text,
  status text,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  normalized_name text := btrim(coalesce(p_name, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF normalized_name = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project record.';
  END IF;
  PERFORM app.require_active_client_record(p_client_id);

  INSERT INTO app.projects (
    client_id,
    name,
    project_type,
    location,
    start_date,
    end_date,
    contract_amount,
    contract_currency_code,
    budget_amount,
    budget_currency_code,
    reporting_currency_code,
    client_visible_summary,
    internal_notes,
    created_by,
    updated_by
  )
  VALUES (
    p_client_id,
    normalized_name,
    app.normalize_project_optional_text(p_project_type, 80),
    app.normalize_project_optional_text(p_location, 500),
    p_start_date,
    p_end_date,
    p_contract_amount,
    p_contract_currency_code,
    p_budget_amount,
    p_budget_currency_code,
    p_reporting_currency_code,
    app.normalize_project_optional_text(p_client_visible_summary, 1200),
    app.normalize_project_optional_text(p_internal_notes, 4000),
    actor_row.actor_user_id,
    actor_row.actor_user_id
  )
  RETURNING id, app.projects.project_number::text, app.projects.status::text, app.projects.version_number
  INTO project_id, project_number, status, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_record_created', 'project_record', project_id, NULL, 'success',
    '{}'::jsonb,
    jsonb_build_object('project_number', project_number, 'changed_fields', ARRAY['name','client_id','project_type','location','dates','monetary_metadata','client_visible_summary','internal_notes']),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb
  );

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
RETURNS TABLE (
  project_id uuid,
  project_number text,
  status text,
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
  normalized_name text := btrim(coalesce(p_name, ''));
  changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF normalized_name = '' OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project record.';
  END IF;
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  PERFORM app.assert_project_updateable(existing_row);
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.';
  END IF;

  IF existing_row.name IS DISTINCT FROM normalized_name THEN changed_fields := changed_fields || ARRAY['name']; END IF;
  IF existing_row.project_type IS DISTINCT FROM app.normalize_project_optional_text(p_project_type, 80) THEN changed_fields := changed_fields || ARRAY['project_type']; END IF;
  IF existing_row.location IS DISTINCT FROM app.normalize_project_optional_text(p_location, 500) THEN changed_fields := changed_fields || ARRAY['location']; END IF;
  IF existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date THEN changed_fields := changed_fields || ARRAY['dates']; END IF;
  IF existing_row.contract_amount IS DISTINCT FROM p_contract_amount OR existing_row.contract_currency_code IS DISTINCT FROM p_contract_currency_code OR existing_row.budget_amount IS DISTINCT FROM p_budget_amount OR existing_row.budget_currency_code IS DISTINCT FROM p_budget_currency_code OR existing_row.reporting_currency_code IS DISTINCT FROM p_reporting_currency_code THEN changed_fields := changed_fields || ARRAY['monetary_metadata']; END IF;
  IF existing_row.client_visible_summary IS DISTINCT FROM app.normalize_project_optional_text(p_client_visible_summary, 1200) THEN changed_fields := changed_fields || ARRAY['client_visible_summary']; END IF;
  IF existing_row.internal_notes IS DISTINCT FROM app.normalize_project_optional_text(p_internal_notes, 4000) THEN changed_fields := changed_fields || ARRAY['internal_notes']; END IF;

  UPDATE app.projects AS p
  SET name = normalized_name,
      project_type = app.normalize_project_optional_text(p_project_type, 80),
      location = app.normalize_project_optional_text(p_location, 500),
      start_date = p_start_date,
      end_date = p_end_date,
      contract_amount = p_contract_amount,
      contract_currency_code = p_contract_currency_code,
      budget_amount = p_budget_amount,
      budget_currency_code = p_budget_currency_code,
      reporting_currency_code = p_reporting_currency_code,
      client_visible_summary = app.normalize_project_optional_text(p_client_visible_summary, 1200),
      internal_notes = app.normalize_project_optional_text(p_internal_notes, 4000),
      updated_by = actor_row.actor_user_id
  WHERE p.id = p_project_id
  RETURNING p.id, p.project_number::text, p.status::text, p.version_number
  INTO project_id, project_number, status, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_record_updated', 'project_record', project_id, NULL, 'success',
    jsonb_build_object('version_number', existing_row.version_number),
    jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb
  );
  RETURN NEXT;
END
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
    jsonb_build_object('future_dependent_record_guard_required', true)
  );
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.change_project_status(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_expected_version_number integer,
  p_new_status app.project_record_status,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (project_id uuid, status text, version_number integer)
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
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  IF existing_row.id IS NULL OR p_expected_version_number IS NULL OR existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.';
  END IF;
  IF p_new_status IN ('COMPLETED', 'CANCELLED', 'ARCHIVED') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project terminal transitions require dedicated functions.';
  END IF;
  IF NOT app.is_allowed_project_transition(existing_row.status, p_new_status) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project status transition is not allowed.';
  END IF;
  PERFORM set_config('app.allow_project_status_change', 'on', true);
  UPDATE app.projects AS p SET status = p_new_status, updated_by = actor_row.actor_user_id WHERE p.id = p_project_id
  RETURNING p.id, p.status::text, p.version_number INTO project_id, status, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_status_changed', 'project_record', project_id, NULL, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.complete_project_record(p_actor_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, status text, completed_at timestamptz, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  IF existing_row.id IS NULL OR p_expected_version_number IS NULL OR existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.'; END IF;
  IF existing_row.status <> 'ACTIVE' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project status transition is not allowed.'; END IF;
  PERFORM set_config('app.allow_project_status_change', 'on', true);
  PERFORM set_config('app.allow_project_lifecycle_fields', 'on', true);
  UPDATE app.projects AS p SET status = 'COMPLETED', completed_at = now(), updated_by = actor_row.actor_user_id WHERE p.id = p_project_id RETURNING p.id, p.status::text, p.completed_at, p.version_number INTO project_id, status, completed_at, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_completed', 'project_record', project_id, NULL, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.cancel_project_record(p_actor_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_cancellation_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, status text, cancelled_at timestamptz, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; existing_row app.projects%ROWTYPE; reason_text text := btrim(coalesce(p_cancellation_reason, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF reason_text = '' OR length(reason_text) > 500 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project cancellation requires a reason.'; END IF;
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  IF existing_row.id IS NULL OR p_expected_version_number IS NULL OR existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.'; END IF;
  IF existing_row.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED', 'ACTIVE', 'ON_HOLD') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project status transition is not allowed.'; END IF;
  PERFORM set_config('app.allow_project_status_change', 'on', true);
  PERFORM set_config('app.allow_project_lifecycle_fields', 'on', true);
  UPDATE app.projects AS p SET status = 'CANCELLED', cancelled_at = now(), cancellation_reason = reason_text, updated_by = actor_row.actor_user_id WHERE p.id = p_project_id RETURNING p.id, p.status::text, p.cancelled_at, p.version_number INTO project_id, status, cancelled_at, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_cancelled', 'project_record', project_id, NULL, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', status, 'version_number', version_number, 'cancellation_reason', '[masked]'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

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
  PERFORM set_config('app.allow_project_status_change', 'on', true);
  PERFORM set_config('app.allow_project_lifecycle_fields', 'on', true);
  UPDATE app.projects AS p SET status = 'ARCHIVED', archived_at = now(), archived_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE p.id = p_project_id RETURNING p.id, p.status::text, p.archived_at, p.version_number INTO project_id, status, archived_at, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_archived', 'project_record', project_id, NULL, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_project_record_detail(p_actor_auth_subject uuid, p_project_id uuid)
RETURNS SETOF app.projects
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT p.* FROM app.projects AS p
  WHERE p.id = p_project_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_record_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS SETOF app.projects
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100); safe_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY SELECT p.* FROM app.projects AS p ORDER BY p.created_at DESC, p.id DESC LIMIT safe_limit OFFSET safe_offset;
END $function$;

CREATE OR REPLACE FUNCTION app.current_client_project_records_for_authenticated_user(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, project_number text, name text, project_type text, location text, status text, start_date date, end_date date, reporting_currency_code char(3), client_visible_summary text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100); safe_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  RETURN QUERY
  SELECT p.id, p.project_number::text, p.name::text, p.project_type::text, p.location, p.status::text, p.start_date, p.end_date, p.reporting_currency_code, p.client_visible_summary
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT' AND u.status = 'ACTIVE' AND u.is_active
    AND c.status = 'ACTIVE' AND c.is_active AND c.archived_at IS NULL
    AND EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
    AND NOT EXISTS (SELECT 1 FROM app.user_roles AS ur INNER JOIN app.roles AS r ON r.code = ur.role_code WHERE ur.user_id = u.id AND ur.is_active AND r.is_staff_role)
  ORDER BY p.created_at DESC, p.id DESC
  LIMIT safe_limit OFFSET safe_offset;
END $function$;

CREATE OR REPLACE FUNCTION app.current_client_project_record_for_authenticated_user(p_project_id uuid)
RETURNS TABLE (id uuid, project_number text, name text, project_type text, location text, status text, start_date date, end_date date, reporting_currency_code char(3), client_visible_summary text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT p.id, p.project_number, p.name, p.project_type, p.location, p.status, p.start_date, p.end_date, p.reporting_currency_code, p.client_visible_summary
  FROM app.current_client_project_records_for_authenticated_user(100, 0) AS p
  WHERE p.id = p_project_id;
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_records(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, project_number text, name text, project_type text, location text, status text, start_date date, end_date date, reporting_currency_code char(3), client_visible_summary text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_client_project_records_for_authenticated_user(p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_record(p_project_id uuid)
RETURNS TABLE (id uuid, project_number text, name text, project_type text, location text, status text, start_date date, end_date date, reporting_currency_code char(3), client_visible_summary text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_client_project_record_for_authenticated_user(p_project_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_create_project_record(p_verified_owner_auth_subject uuid, p_client_id uuid, p_name text, p_reporting_currency_code char(3), p_project_type text DEFAULT NULL, p_location text DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_contract_amount numeric DEFAULT NULL, p_contract_currency_code char(3) DEFAULT NULL, p_budget_amount numeric DEFAULT NULL, p_budget_currency_code char(3) DEFAULT NULL, p_client_visible_summary text DEFAULT NULL, p_internal_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, project_number text, status text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.create_project_record(p_verified_owner_auth_subject, p_client_id, p_name, p_reporting_currency_code, p_project_type, p_location, p_start_date, p_end_date, p_contract_amount, p_contract_currency_code, p_budget_amount, p_budget_currency_code, p_client_visible_summary, p_internal_notes, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_update_project_record(p_verified_owner_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_name text, p_reporting_currency_code char(3), p_project_type text DEFAULT NULL, p_location text DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_contract_amount numeric DEFAULT NULL, p_contract_currency_code char(3) DEFAULT NULL, p_budget_amount numeric DEFAULT NULL, p_budget_currency_code char(3) DEFAULT NULL, p_client_visible_summary text DEFAULT NULL, p_internal_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, project_number text, status text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.update_project_record(p_verified_owner_auth_subject, p_project_id, p_expected_version_number, p_name, p_reporting_currency_code, p_project_type, p_location, p_start_date, p_end_date, p_contract_amount, p_contract_currency_code, p_budget_amount, p_budget_currency_code, p_client_visible_summary, p_internal_notes, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_change_project_client(p_verified_owner_auth_subject uuid, p_project_id uuid, p_new_client_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, old_client_id uuid, new_client_id uuid, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.change_project_client(p_verified_owner_auth_subject, p_project_id, p_new_client_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_change_project_status(p_verified_owner_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_new_status app.project_record_status, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, status text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.change_project_status(p_verified_owner_auth_subject, p_project_id, p_expected_version_number, p_new_status, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_complete_project_record(p_verified_owner_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, status text, completed_at timestamptz, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.complete_project_record(p_verified_owner_auth_subject, p_project_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_cancel_project_record(p_verified_owner_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_cancellation_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, status text, cancelled_at timestamptz, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.cancel_project_record(p_verified_owner_auth_subject, p_project_id, p_expected_version_number, p_cancellation_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_archive_project_record(p_verified_owner_auth_subject uuid, p_project_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, status text, archived_at timestamptz, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.archive_project_record(p_verified_owner_auth_subject, p_project_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_record_detail(p_verified_owner_auth_subject uuid, p_project_id uuid)
RETURNS SETOF app.projects
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_record_detail(p_verified_owner_auth_subject, p_project_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_record_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS SETOF app.projects
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_record_list(p_verified_owner_auth_subject, p_limit, p_offset);
$function$;

COMMIT;
