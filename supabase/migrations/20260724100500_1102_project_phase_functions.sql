BEGIN;

CREATE OR REPLACE FUNCTION app.assert_project_phase_dates(
  p_project app.projects,
  p_start_date date,
  p_end_date date
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_start_date > p_end_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase dates.';
  END IF;
  IF p_project.start_date IS NOT NULL AND p_start_date IS NOT NULL AND p_start_date < p_project.start_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase dates must fit inside Project dates.';
  END IF;
  IF p_project.end_date IS NOT NULL AND p_end_date IS NOT NULL AND p_end_date > p_project.end_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase dates must fit inside Project dates.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.assert_project_phase_editable(p_project app.projects)
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
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase changes are not allowed in this Project status.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.create_project_phase(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_name text,
  p_description text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_client_visible boolean DEFAULT true,
  p_insert_position integer DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  phase_id uuid,
  project_id uuid,
  sequence_no integer,
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
  active_count integer;
  insert_position integer;
  normalized_name text := btrim(coalesce(p_name, ''));
  normalized_description text := app.normalize_project_optional_text(p_description, 4000);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF normalized_name = '' OR length(normalized_name) > 160 OR p_client_visible IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase.';
  END IF;

  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  PERFORM app.assert_project_phase_editable(project_row);
  PERFORM app.assert_project_phase_dates(project_row, p_start_date, p_end_date);
  SET CONSTRAINTS app.project_phases_project_sequence_uk DEFERRED;

  PERFORM 1 FROM app.project_phases AS pp WHERE pp.project_id = p_project_id FOR UPDATE;
  SELECT count(*)::integer INTO active_count FROM app.project_phases AS pp WHERE pp.project_id = p_project_id AND pp.is_active;
  insert_position := coalesce(p_insert_position, active_count + 1);
  IF insert_position < 1 OR insert_position > active_count + 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase insertion position.';
  END IF;

  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'on', true);
  UPDATE app.project_phases AS pp
  SET sequence_no = pp.sequence_no + 1,
      updated_by = actor_row.actor_user_id
  WHERE pp.project_id = p_project_id
    AND pp.sequence_no >= insert_position;

  INSERT INTO app.project_phases (
    project_id,
    name,
    description,
    sequence_no,
    start_date,
    end_date,
    client_visible,
    created_by,
    updated_by
  )
  VALUES (
    p_project_id,
    normalized_name,
    normalized_description,
    insert_position,
    p_start_date,
    p_end_date,
    p_client_visible,
    actor_row.actor_user_id,
    actor_row.actor_user_id
  )
  RETURNING id, app.project_phases.project_id, app.project_phases.sequence_no, app.project_phases.is_active, app.project_phases.version_number
  INTO phase_id, project_id, sequence_no, is_active, version_number;
  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'off', true);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_phase_created', 'project_phase', phase_id, project_id, 'success',
    '{}'::jsonb,
    jsonb_build_object('project_id', project_id, 'phase_id', phase_id, 'sequence_no', sequence_no, 'client_visible', p_client_visible),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('changed_fields', ARRAY['name','description','dates','client_visible','sequence_no'])
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.update_project_phase(
  p_actor_auth_subject uuid,
  p_phase_id uuid,
  p_expected_version_number integer,
  p_name text,
  p_description text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_client_visible boolean DEFAULT true,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  phase_id uuid,
  project_id uuid,
  sequence_no integer,
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
  existing_row app.project_phases%ROWTYPE;
  project_row app.projects%ROWTYPE;
  normalized_name text := btrim(coalesce(p_name, ''));
  normalized_description text := app.normalize_project_optional_text(p_description, 4000);
  changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF normalized_name = '' OR length(normalized_name) > 160 OR p_client_visible IS NULL OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase.';
  END IF;

  SELECT * INTO existing_row FROM app.project_phases AS pp WHERE pp.id = p_phase_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase cannot be updated.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project phase version conflict.';
  END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  PERFORM app.assert_project_phase_editable(project_row);
  PERFORM app.assert_project_phase_dates(project_row, p_start_date, p_end_date);

  IF existing_row.name IS DISTINCT FROM normalized_name THEN changed_fields := changed_fields || ARRAY['name']; END IF;
  IF existing_row.description IS DISTINCT FROM normalized_description THEN changed_fields := changed_fields || ARRAY['description']; END IF;
  IF existing_row.start_date IS DISTINCT FROM p_start_date OR existing_row.end_date IS DISTINCT FROM p_end_date THEN changed_fields := changed_fields || ARRAY['dates']; END IF;
  IF existing_row.client_visible IS DISTINCT FROM p_client_visible THEN changed_fields := changed_fields || ARRAY['client_visible']; END IF;

  IF array_length(changed_fields, 1) IS NULL THEN
    phase_id := existing_row.id;
    project_id := existing_row.project_id;
    sequence_no := existing_row.sequence_no;
    is_active := existing_row.is_active;
    version_number := existing_row.version_number;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE app.project_phases AS pp
  SET name = normalized_name,
      description = normalized_description,
      start_date = p_start_date,
      end_date = p_end_date,
      client_visible = p_client_visible,
      updated_by = actor_row.actor_user_id
  WHERE pp.id = p_phase_id
  RETURNING pp.id, pp.project_id, pp.sequence_no, pp.is_active, pp.version_number
  INTO phase_id, project_id, sequence_no, is_active, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_phase_updated', 'project_phase', phase_id, project_id, 'success',
    jsonb_build_object('version_number', existing_row.version_number),
    jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields, 'client_visibility_changed', existing_row.client_visible IS DISTINCT FROM p_client_visible),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb
  );
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.reorder_project_phases(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_ordered_phase_ids uuid[],
  p_expected_version_numbers integer[],
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  project_id uuid,
  reordered_count integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  project_row app.projects%ROWTYPE;
  active_count integer;
  affected_count integer;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_ordered_phase_ids IS NULL
     OR p_expected_version_numbers IS NULL
     OR array_length(p_ordered_phase_ids, 1) IS DISTINCT FROM array_length(p_expected_version_numbers, 1) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase order.';
  END IF;

  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  PERFORM app.assert_project_phase_editable(project_row);
  SET CONSTRAINTS app.project_phases_project_sequence_uk DEFERRED;
  PERFORM 1 FROM app.project_phases AS pp WHERE pp.project_id = p_project_id FOR UPDATE;

  SELECT count(*)::integer INTO active_count FROM app.project_phases AS pp WHERE pp.project_id = p_project_id AND pp.is_active;
  IF active_count <> coalesce(array_length(p_ordered_phase_ids, 1), 0) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase order.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(p_ordered_phase_ids) AS ids(phase_id)
    WHERE ids.phase_id IS NULL
    GROUP BY ids.phase_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase order.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(p_expected_version_numbers) AS versions(version_number)
    WHERE versions.version_number IS NULL OR versions.version_number < 1
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase order.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(p_ordered_phase_ids, p_expected_version_numbers) WITH ORDINALITY AS requested(phase_id, expected_version, target_sequence)
    LEFT JOIN app.project_phases AS pp
      ON pp.id = requested.phase_id
     AND pp.project_id = p_project_id
     AND pp.is_active
     AND pp.version_number = requested.expected_version
    WHERE pp.id IS NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project phase order version conflict.';
  END IF;

  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'on', true);
  WITH requested AS (
    SELECT phase_id, target_sequence::integer
    FROM unnest(p_ordered_phase_ids) WITH ORDINALITY AS ordered(phase_id, target_sequence)
  ),
  inactive_requested AS (
    SELECT pp.id AS phase_id, (active_count + row_number() OVER (ORDER BY pp.sequence_no, pp.id))::integer AS target_sequence
    FROM app.project_phases AS pp
    WHERE pp.project_id = p_project_id
      AND NOT pp.is_active
  ),
  targets AS (
    SELECT * FROM requested
    UNION ALL
    SELECT * FROM inactive_requested
  ),
  changed AS (
    SELECT pp.id, targets.target_sequence
    FROM app.project_phases AS pp
    INNER JOIN targets ON targets.phase_id = pp.id
    WHERE pp.project_id = p_project_id
      AND pp.sequence_no IS DISTINCT FROM targets.target_sequence
  )
  UPDATE app.project_phases AS pp
  SET sequence_no = changed.target_sequence,
      updated_by = actor_row.actor_user_id
  FROM changed
  WHERE pp.id = changed.id;

  GET DIAGNOSTICS affected_count = ROW_COUNT;
  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'off', true);

  IF affected_count > 0 THEN
    PERFORM app.write_activity_log(
      actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
      'project_phases_reordered', 'project_record', p_project_id, p_project_id, 'success',
      '{}'::jsonb,
      jsonb_build_object('affected_phase_count', affected_count),
      NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
      jsonb_build_object('active_phase_count', active_count)
    );
  END IF;

  project_id := p_project_id;
  reordered_count := affected_count;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.archive_project_phase(
  p_actor_auth_subject uuid,
  p_phase_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  phase_id uuid,
  project_id uuid,
  sequence_no integer,
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
  existing_row app.project_phases%ROWTYPE;
  project_row app.projects%ROWTYPE;
  active_count integer;
  total_count integer;
  shifted_count integer;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project phase archival.';
  END IF;

  SELECT * INTO existing_row FROM app.project_phases AS pp WHERE pp.id = p_phase_id FOR UPDATE;
  IF existing_row.id IS NULL OR NOT existing_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase cannot be archived.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project phase version conflict.';
  END IF;
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = existing_row.project_id FOR UPDATE;
  IF project_row.id IS NULL OR project_row.status = 'ARCHIVED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase archival is not allowed in this Project status.';
  END IF;

  SET CONSTRAINTS app.project_phases_project_sequence_uk DEFERRED;
  PERFORM 1 FROM app.project_phases AS pp WHERE pp.project_id = existing_row.project_id FOR UPDATE;
  SELECT count(*)::integer INTO active_count FROM app.project_phases AS pp WHERE pp.project_id = existing_row.project_id AND pp.is_active;
  SELECT count(*)::integer INTO total_count FROM app.project_phases AS pp WHERE pp.project_id = existing_row.project_id;

  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'on', true);
  UPDATE app.project_phases AS pp
  SET sequence_no = pp.sequence_no - 1,
      updated_by = actor_row.actor_user_id
  WHERE pp.project_id = existing_row.project_id
    AND pp.sequence_no > existing_row.sequence_no;
  GET DIAGNOSTICS shifted_count = ROW_COUNT;

  PERFORM set_config('app.allow_project_phase_archive', 'on', true);
  UPDATE app.project_phases AS pp
  SET is_active = false,
      sequence_no = total_count,
      updated_by = actor_row.actor_user_id
  WHERE pp.id = p_phase_id
  RETURNING pp.id, pp.project_id, pp.sequence_no, pp.is_active, pp.version_number
  INTO phase_id, project_id, sequence_no, is_active, version_number;
  PERFORM set_config('app.allow_project_phase_archive', 'off', true);
  PERFORM set_config('app.allow_project_phase_ordering_maintenance', 'off', true);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'project_phase_archived', 'project_phase', phase_id, project_id, 'success',
    jsonb_build_object('sequence_no', existing_row.sequence_no, 'is_active', true, 'version_number', existing_row.version_number),
    jsonb_build_object('sequence_no', sequence_no, 'is_active', false, 'version_number', version_number),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('affected_phase_count', shifted_count + 1)
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_phase_list(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_include_inactive boolean DEFAULT true
)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  name text,
  description text,
  sequence_no integer,
  start_date date,
  end_date date,
  client_visible boolean,
  is_active boolean,
  created_at timestamptz,
  created_by uuid,
  updated_at timestamptz,
  updated_by uuid,
  version_number integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT pp.id, pp.project_id, pp.name::text, pp.description, pp.sequence_no, pp.start_date, pp.end_date,
         pp.client_visible, pp.is_active, pp.created_at, pp.created_by, pp.updated_at, pp.updated_by, pp.version_number
  FROM app.project_phases AS pp
  WHERE pp.project_id = p_project_id
    AND (coalesce(p_include_inactive, true) OR pp.is_active)
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject))
  ORDER BY pp.sequence_no, pp.id;
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_phase_detail(
  p_actor_auth_subject uuid,
  p_phase_id uuid
)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  name text,
  description text,
  sequence_no integer,
  start_date date,
  end_date date,
  client_visible boolean,
  is_active boolean,
  created_at timestamptz,
  created_by uuid,
  updated_at timestamptz,
  updated_by uuid,
  version_number integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT pp.id, pp.project_id, pp.name::text, pp.description, pp.sequence_no, pp.start_date, pp.end_date,
         pp.client_visible, pp.is_active, pp.created_at, pp.created_by, pp.updated_at, pp.updated_by, pp.version_number
  FROM app.project_phases AS pp
  WHERE pp.id = p_phase_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION app.current_client_project_phases_for_authenticated_user(p_project_id uuid)
RETURNS TABLE (id uuid, project_id uuid, name text, description text, sequence_no integer, start_date date, end_date date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT pp.id, pp.project_id, pp.name::text, pp.description, pp.sequence_no, pp.start_date, pp.end_date
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  INNER JOIN app.project_phases AS pp ON pp.project_id = p.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT' AND u.status = 'ACTIVE' AND u.is_active
    AND c.status = 'ACTIVE' AND c.is_active AND c.archived_at IS NULL
    AND p.id = p_project_id
    AND pp.is_active AND pp.client_visible
    AND EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
    AND NOT EXISTS (SELECT 1 FROM app.user_roles AS ur INNER JOIN app.roles AS r ON r.code = ur.role_code WHERE ur.user_id = u.id AND ur.is_active AND r.is_staff_role)
  ORDER BY pp.sequence_no, pp.id;
$function$;

CREATE OR REPLACE FUNCTION app.current_client_project_phase_for_authenticated_user(p_phase_id uuid)
RETURNS TABLE (id uuid, project_id uuid, name text, description text, sequence_no integer, start_date date, end_date date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT pp.id, pp.project_id, pp.name, pp.description, pp.sequence_no, pp.start_date, pp.end_date
  FROM app.current_client_project_phases_for_authenticated_user(
    (SELECT project_id FROM app.project_phases WHERE id = p_phase_id AND is_active AND client_visible)
  ) AS pp
  WHERE pp.id = p_phase_id;
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_phases(p_project_id uuid)
RETURNS TABLE (id uuid, project_id uuid, name text, description text, sequence_no integer, start_date date, end_date date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_project_phases_for_authenticated_user(p_project_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_phase(p_phase_id uuid)
RETURNS TABLE (id uuid, project_id uuid, name text, description text, sequence_no integer, start_date date, end_date date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_project_phase_for_authenticated_user(p_phase_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_create_project_phase(p_verified_owner_auth_subject uuid, p_project_id uuid, p_name text, p_description text DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_client_visible boolean DEFAULT true, p_insert_position integer DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (phase_id uuid, project_id uuid, sequence_no integer, is_active boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.create_project_phase(p_verified_owner_auth_subject, p_project_id, p_name, p_description, p_start_date, p_end_date, p_client_visible, p_insert_position, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_update_project_phase(p_verified_owner_auth_subject uuid, p_phase_id uuid, p_expected_version_number integer, p_name text, p_description text DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_client_visible boolean DEFAULT true, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (phase_id uuid, project_id uuid, sequence_no integer, is_active boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.update_project_phase(p_verified_owner_auth_subject, p_phase_id, p_expected_version_number, p_name, p_description, p_start_date, p_end_date, p_client_visible, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_reorder_project_phases(p_verified_owner_auth_subject uuid, p_project_id uuid, p_ordered_phase_ids uuid[], p_expected_version_numbers integer[], p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (project_id uuid, reordered_count integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.reorder_project_phases(p_verified_owner_auth_subject, p_project_id, p_ordered_phase_ids, p_expected_version_numbers, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_archive_project_phase(p_verified_owner_auth_subject uuid, p_phase_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (phase_id uuid, project_id uuid, sequence_no integer, is_active boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.archive_project_phase(p_verified_owner_auth_subject, p_phase_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_phase_list(p_verified_owner_auth_subject uuid, p_project_id uuid, p_include_inactive boolean DEFAULT true)
RETURNS TABLE (id uuid, project_id uuid, name text, description text, sequence_no integer, start_date date, end_date date, client_visible boolean, is_active boolean, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_phase_list(p_verified_owner_auth_subject, p_project_id, p_include_inactive);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_phase_detail(p_verified_owner_auth_subject uuid, p_phase_id uuid)
RETURNS TABLE (id uuid, project_id uuid, name text, description text, sequence_no integer, start_date date, end_date date, client_visible boolean, is_active boolean, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_project_phase_detail(p_verified_owner_auth_subject, p_phase_id);
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
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project Client reassignment.';
  END IF;
  PERFORM app.require_active_client_record(p_new_client_id);
  SELECT * INTO existing_row FROM app.projects AS p WHERE p.id = p_project_id FOR UPDATE;
  IF existing_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record not available.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Project record version conflict.'; END IF;
  IF existing_row.status NOT IN ('DRAFT', 'QUOTATION', 'APPROVED') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed in this status.';
  END IF;
  IF EXISTS (SELECT 1 FROM app.project_staff_assignments AS psa WHERE psa.project_id = p_project_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed after staff assignment history exists.';
  END IF;
  IF EXISTS (SELECT 1 FROM app.project_phases AS pp WHERE pp.project_id = p_project_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client cannot be changed after phase history exists.';
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
    jsonb_build_object('dependent_record_guard', 'project_staff_assignments,project_phases')
  );
  RETURN NEXT;
END
$function$;

COMMIT;
