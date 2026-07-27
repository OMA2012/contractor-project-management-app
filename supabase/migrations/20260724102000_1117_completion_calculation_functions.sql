BEGIN;

CREATE OR REPLACE FUNCTION app.calculate_project_phase_completion(
  p_phase_id uuid
)
RETURNS numeric(5,2)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE(
    round(
      sum(t.weight_percent * t.completion_percent)
      / NULLIF(sum(t.weight_percent), 0),
      2
    ),
    0.00
  )::numeric(5,2)
  FROM app.tasks AS t
  WHERE t.phase_id = p_phase_id
    AND t.is_active = true
    AND t.counts_toward_completion = true
    AND t.status <> 'CANCELLED'
    AND t.weight_percent IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION app.calculate_project_completion(
  p_project_id uuid
)
RETURNS numeric(5,2)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE(
    round(
      sum(t.weight_percent * t.completion_percent)
      / NULLIF(sum(t.weight_percent), 0),
      2
    ),
    0.00
  )::numeric(5,2)
  FROM app.tasks AS t
  WHERE t.project_id = p_project_id
    AND t.is_active = true
    AND t.counts_toward_completion = true
    AND t.status <> 'CANCELLED'
    AND t.weight_percent IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_phase_completion(
  p_actor_auth_subject uuid,
  p_phase_id uuid
)
RETURNS TABLE (
  project_id uuid,
  phase_id uuid,
  calculated_completion_percent numeric(5,2),
  counted_task_count integer,
  total_weight numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  phase_row app.project_phases%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO phase_row
  FROM app.project_phases AS pp
  WHERE pp.id = p_phase_id;

  IF phase_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase is not available.';
  END IF;

  RETURN QUERY
  SELECT
    phase_row.project_id,
    phase_row.id,
    app.calculate_project_phase_completion(phase_row.id),
    count(t.id)::integer,
    COALESCE(sum(t.weight_percent), 0)::numeric
  FROM app.tasks AS t
  WHERE t.phase_id = phase_row.id
    AND t.is_active = true
    AND t.counts_toward_completion = true
    AND t.status <> 'CANCELLED'
    AND t.weight_percent IS NOT NULL;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_completion(
  p_actor_auth_subject uuid,
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2),
  counted_task_count integer,
  total_weight numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  project_row app.projects%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO project_row
  FROM app.projects AS p
  WHERE p.id = p_project_id;

  IF project_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record is not available.';
  END IF;

  RETURN QUERY
  SELECT
    project_row.id,
    app.calculate_project_completion(project_row.id),
    count(t.id)::integer,
    COALESCE(sum(t.weight_percent), 0)::numeric
  FROM app.tasks AS t
  WHERE t.project_id = project_row.id
    AND t.is_active = true
    AND t.counts_toward_completion = true
    AND t.status <> 'CANCELLED'
    AND t.weight_percent IS NOT NULL;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_project_phase_completion_for_authenticated_user(
  p_phase_id uuid
)
RETURNS TABLE (
  project_id uuid,
  phase_id uuid,
  calculated_completion_percent numeric(5,2)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    pp.project_id,
    pp.id,
    app.calculate_project_phase_completion(pp.id)
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  INNER JOIN app.project_phases AS pp ON pp.project_id = p.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND pp.id = p_phase_id
    AND pp.is_active
    AND pp.client_visible
    AND EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
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
    );
$function$;

CREATE OR REPLACE FUNCTION app.current_client_project_completion_for_authenticated_user(
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    p.id,
    app.calculate_project_completion(p.id)
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND p.id = p_project_id
    AND EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
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
    );
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_phase_completion(
  p_phase_id uuid
)
RETURNS TABLE (
  project_id uuid,
  phase_id uuid,
  calculated_completion_percent numeric(5,2)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_project_phase_completion_for_authenticated_user(p_phase_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_project_completion(
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_project_completion_for_authenticated_user(p_project_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_phase_completion(
  p_verified_owner_auth_subject uuid,
  p_phase_id uuid
)
RETURNS TABLE (
  project_id uuid,
  phase_id uuid,
  calculated_completion_percent numeric(5,2),
  counted_task_count integer,
  total_weight numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_project_phase_completion(p_verified_owner_auth_subject, p_phase_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_completion(
  p_verified_owner_auth_subject uuid,
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2),
  counted_task_count integer,
  total_weight numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_project_completion(p_verified_owner_auth_subject, p_project_id);
$function$;

COMMIT;
