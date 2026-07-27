BEGIN;

CREATE OR REPLACE FUNCTION app.derive_project_completion_override_state(
  p_approved_at timestamptz,
  p_approved_by uuid,
  p_revoked_at timestamptz,
  p_revoked_by uuid
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_approved_at IS NULL
     AND p_approved_by IS NULL
     AND p_revoked_at IS NULL
     AND p_revoked_by IS NULL THEN
    RETURN 'PENDING';
  END IF;

  IF p_approved_at IS NOT NULL
     AND p_approved_by IS NOT NULL
     AND p_revoked_at IS NULL
     AND p_revoked_by IS NULL THEN
    RETURN 'ACTIVE';
  END IF;

  IF p_approved_at IS NOT NULL
     AND p_approved_by IS NOT NULL
     AND p_revoked_at IS NOT NULL
     AND p_revoked_by IS NOT NULL THEN
    RETURN 'SUPERSEDED_OR_REVOKED';
  END IF;

  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override state is invalid.';
END
$function$;

CREATE OR REPLACE FUNCTION app.current_project_official_completion(
  p_project_id uuid
)
RETURNS TABLE (
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2),
  is_overridden boolean,
  active_override_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH calculated AS (
    SELECT app.calculate_project_completion(p_project_id) AS value
  ),
  active_override AS (
    SELECT pco.id, pco.override_percent
    FROM app.project_completion_overrides AS pco
    WHERE pco.project_id = p_project_id
      AND pco.approved_at IS NOT NULL
      AND pco.approved_by IS NOT NULL
      AND pco.revoked_at IS NULL
      AND pco.revoked_by IS NULL
    ORDER BY pco.approved_at DESC, pco.id DESC
    LIMIT 1
  )
  SELECT
    calculated.value,
    COALESCE(active_override.override_percent, calculated.value)::numeric(5,2),
    (active_override.id IS NOT NULL),
    active_override.id
  FROM calculated
  LEFT JOIN active_override ON true;
$function$;

CREATE OR REPLACE FUNCTION app.owner_request_project_completion_override(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_override_percent numeric,
  p_reason text,
  p_effective_at timestamptz,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  override_id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  effective_at timestamptz,
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
  reason_text text := btrim(coalesce(p_reason, ''));
  workflow_at timestamptz := transaction_timestamp();
  calculated_before numeric(5,2);
  official_before numeric(5,2);
  inserted_row app.project_completion_overrides%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  IF p_override_percent IS NULL OR p_override_percent < 0 OR p_override_percent > 100 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override percentage is invalid.';
  END IF;
  IF reason_text = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override reason is required.';
  END IF;
  IF p_effective_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override effective timestamp is required.';
  END IF;
  IF p_effective_at > workflow_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Future Project completion overrides are not supported.';
  END IF;

  SELECT * INTO project_row
  FROM app.projects AS p
  WHERE p.id = p_project_id;

  IF project_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record is not available.';
  END IF;

  SELECT o.calculated_completion_percent, o.official_completion_percent
  INTO calculated_before, official_before
  FROM app.current_project_official_completion(project_row.id) AS o;

  INSERT INTO app.project_completion_overrides (
    project_id,
    override_percent,
    reason,
    effective_at,
    created_at,
    created_by
  )
  VALUES (
    project_row.id,
    p_override_percent::numeric(5,2),
    reason_text,
    p_effective_at,
    workflow_at,
    actor_row.actor_user_id
  )
  RETURNING * INTO inserted_row;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'project_completion_override_requested',
    'project_completion_override',
    inserted_row.id,
    project_row.id,
    'success',
    jsonb_build_object('calculated_completion_percent', calculated_before, 'official_completion_percent', official_before),
    jsonb_build_object('override_percent', inserted_row.override_percent, 'effective_at', inserted_row.effective_at),
    reason_text,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    jsonb_build_object(
      'project_id', project_row.id,
      'override_id', inserted_row.id,
      'calculated_completion_percent', calculated_before,
      'official_completion_before_request', official_before,
      'proposed_override_percent', inserted_row.override_percent,
      'effective_at', inserted_row.effective_at,
      'effective_role_code', actor_row.effective_role_code
    )
  );

  override_id := inserted_row.id;
  project_id := inserted_row.project_id;
  override_percent := inserted_row.override_percent;
  effective_at := inserted_row.effective_at;
  created_at := inserted_row.created_at;
  created_by := inserted_row.created_by;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_approve_project_completion_override(
  p_actor_auth_subject uuid,
  p_override_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  override_id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  effective_at timestamptz,
  approved_at timestamptz,
  approved_by uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2)
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  target_project_id uuid;
  project_row app.projects%ROWTYPE;
  request_row app.project_completion_overrides%ROWTYPE;
  active_row app.project_completion_overrides%ROWTYPE;
  workflow_at timestamptz := transaction_timestamp();
  official_before numeric(5,2);
  calculated_now numeric(5,2);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT pco.project_id INTO target_project_id
  FROM app.project_completion_overrides AS pco
  WHERE pco.id = p_override_id;

  IF target_project_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override is not available.';
  END IF;

  SELECT * INTO project_row
  FROM app.projects AS p
  WHERE p.id = target_project_id
  FOR UPDATE;

  IF project_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record is not available.';
  END IF;

  SELECT * INTO request_row
  FROM app.project_completion_overrides AS pco
  WHERE pco.id = p_override_id
  FOR UPDATE;

  IF request_row.id IS NULL
     OR request_row.approved_at IS NOT NULL
     OR request_row.approved_by IS NOT NULL
     OR request_row.revoked_at IS NOT NULL
     OR request_row.revoked_by IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override cannot be approved.';
  END IF;
  IF request_row.created_by = actor_row.actor_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Project completion override requires different Owner approval.';
  END IF;

  SELECT o.official_completion_percent
  INTO official_before
  FROM app.current_project_official_completion(project_row.id) AS o;
  calculated_now := app.calculate_project_completion(project_row.id);

  SELECT * INTO active_row
  FROM app.project_completion_overrides AS pco
  WHERE pco.project_id = project_row.id
    AND pco.approved_at IS NOT NULL
    AND pco.approved_by IS NOT NULL
    AND pco.revoked_at IS NULL
    AND pco.revoked_by IS NULL
  FOR UPDATE;

  IF active_row.id IS NOT NULL THEN
    PERFORM set_config('app.allow_project_completion_override_revocation', 'on', true);
    UPDATE app.project_completion_overrides AS pco
    SET revoked_at = workflow_at,
        revoked_by = actor_row.actor_user_id
    WHERE pco.id = active_row.id;
    PERFORM set_config('app.allow_project_completion_override_revocation', 'off', true);

    PERFORM app.write_activity_log(
      actor_row.actor_user_id,
      actor_row.actor_auth_subject,
      actor_row.effective_role_code,
      'project_completion_override_superseded',
      'project_completion_override',
      active_row.id,
      project_row.id,
      'success',
      jsonb_build_object('official_completion_percent', official_before, 'active_override_id', active_row.id),
      jsonb_build_object('superseded_by_override_id', request_row.id, 'revoked_at', workflow_at),
      NULL,
      p_ip_address,
      p_session_identifier,
      p_request_identifier,
      p_correlation_identifier,
      jsonb_build_object('project_id', project_row.id, 'override_id', active_row.id, 'superseded_by_override_id', request_row.id)
    );
  END IF;

  PERFORM set_config('app.allow_project_completion_override_approval', 'on', true);
  UPDATE app.project_completion_overrides AS pco
  SET approved_at = workflow_at,
      approved_by = actor_row.actor_user_id
  WHERE pco.id = request_row.id
  RETURNING * INTO request_row;
  PERFORM set_config('app.allow_project_completion_override_approval', 'off', true);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'project_completion_override_approved',
    'project_completion_override',
    request_row.id,
    project_row.id,
    'success',
    jsonb_build_object('official_completion_percent', official_before),
    jsonb_build_object('official_completion_percent', request_row.override_percent, 'approved_at', request_row.approved_at),
    request_row.reason,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    jsonb_build_object(
      'project_id', project_row.id,
      'override_id', request_row.id,
      'calculated_completion_percent', calculated_now,
      'official_completion_before_approval', official_before,
      'official_completion_after_approval', request_row.override_percent
    )
  );

  override_id := request_row.id;
  project_id := request_row.project_id;
  override_percent := request_row.override_percent;
  effective_at := request_row.effective_at;
  approved_at := request_row.approved_at;
  approved_by := request_row.approved_by;
  calculated_completion_percent := calculated_now;
  official_completion_percent := request_row.override_percent;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_revoke_project_completion_override(
  p_actor_auth_subject uuid,
  p_override_id uuid,
  p_revocation_reason text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  override_id uuid,
  project_id uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2)
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  target_project_id uuid;
  project_row app.projects%ROWTYPE;
  override_row app.project_completion_overrides%ROWTYPE;
  reason_text text := btrim(coalesce(p_revocation_reason, ''));
  workflow_at timestamptz := transaction_timestamp();
  official_before numeric(5,2);
  calculated_now numeric(5,2);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF reason_text = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override revocation reason is required.';
  END IF;

  SELECT pco.project_id INTO target_project_id
  FROM app.project_completion_overrides AS pco
  WHERE pco.id = p_override_id;

  IF target_project_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override is not available.';
  END IF;

  SELECT * INTO project_row
  FROM app.projects AS p
  WHERE p.id = target_project_id
  FOR UPDATE;

  SELECT * INTO override_row
  FROM app.project_completion_overrides AS pco
  WHERE pco.id = p_override_id
  FOR UPDATE;

  IF project_row.id IS NULL
     OR override_row.id IS NULL
     OR override_row.approved_at IS NULL
     OR override_row.approved_by IS NULL
     OR override_row.revoked_at IS NOT NULL
     OR override_row.revoked_by IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override cannot be revoked.';
  END IF;

  SELECT o.official_completion_percent
  INTO official_before
  FROM app.current_project_official_completion(project_row.id) AS o;

  PERFORM set_config('app.allow_project_completion_override_revocation', 'on', true);
  UPDATE app.project_completion_overrides AS pco
  SET revoked_at = workflow_at,
      revoked_by = actor_row.actor_user_id
  WHERE pco.id = override_row.id
  RETURNING * INTO override_row;
  PERFORM set_config('app.allow_project_completion_override_revocation', 'off', true);

  calculated_now := app.calculate_project_completion(project_row.id);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'project_completion_override_revoked',
    'project_completion_override',
    override_row.id,
    project_row.id,
    'success',
    jsonb_build_object('official_completion_percent', official_before),
    jsonb_build_object('official_completion_percent', calculated_now, 'revoked_at', override_row.revoked_at),
    reason_text,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    jsonb_build_object('project_id', project_row.id, 'override_id', override_row.id, 'calculated_completion_percent', calculated_now)
  );

  override_id := override_row.id;
  project_id := override_row.project_id;
  revoked_at := override_row.revoked_at;
  revoked_by := override_row.revoked_by;
  calculated_completion_percent := calculated_now;
  official_completion_percent := calculated_now;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_official_project_completion(
  p_actor_auth_subject uuid,
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2),
  is_overridden boolean,
  active_override_id uuid,
  override_percent numeric(5,2),
  override_reason text,
  override_effective_at timestamptz,
  override_created_at timestamptz,
  override_created_by uuid,
  override_approved_at timestamptz,
  override_approved_by uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  project_row app.projects%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = p_project_id;
  IF project_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record is not available.';
  END IF;

  RETURN QUERY
  SELECT
    project_row.id,
    official.calculated_completion_percent,
    official.official_completion_percent,
    official.is_overridden,
    official.active_override_id,
    pco.override_percent,
    pco.reason,
    pco.effective_at,
    pco.created_at,
    pco.created_by,
    pco.approved_at,
    pco.approved_by
  FROM app.current_project_official_completion(project_row.id) AS official
  LEFT JOIN app.project_completion_overrides AS pco
    ON pco.id = official.active_override_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_completion_override_list(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  reason text,
  effective_at timestamptz,
  derived_state text,
  approved_at timestamptz,
  approved_by uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  created_at timestamptz,
  created_by uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app.projects AS p WHERE p.id = p_project_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project record is not available.';
  END IF;

  RETURN QUERY
  SELECT
    pco.id,
    pco.project_id,
    pco.override_percent,
    pco.reason,
    pco.effective_at,
    app.derive_project_completion_override_state(pco.approved_at, pco.approved_by, pco.revoked_at, pco.revoked_by),
    pco.approved_at,
    pco.approved_by,
    pco.revoked_at,
    pco.revoked_by,
    pco.created_at,
    pco.created_by
  FROM app.project_completion_overrides AS pco
  WHERE pco.project_id = p_project_id
  ORDER BY pco.created_at DESC, pco.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_completion_override_detail(
  p_actor_auth_subject uuid,
  p_override_id uuid
)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  reason text,
  effective_at timestamptz,
  derived_state text,
  approved_at timestamptz,
  approved_by uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  created_at timestamptz,
  created_by uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  RETURN QUERY
  SELECT
    pco.id,
    pco.project_id,
    pco.override_percent,
    pco.reason,
    pco.effective_at,
    app.derive_project_completion_override_state(pco.approved_at, pco.approved_by, pco.revoked_at, pco.revoked_by),
    pco.approved_at,
    pco.approved_by,
    pco.revoked_at,
    pco.revoked_by,
    pco.created_at,
    pco.created_by
  FROM app.project_completion_overrides AS pco
  WHERE pco.id = p_override_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override is not available.';
  END IF;
END
$function$;

DROP FUNCTION public.current_client_project_completion(uuid);
DROP FUNCTION app.current_client_project_completion_for_authenticated_user(uuid);

CREATE OR REPLACE FUNCTION app.current_client_project_completion_for_authenticated_user(
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2),
  is_overridden boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    p.id,
    official.calculated_completion_percent,
    official.official_completion_percent,
    official.is_overridden
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  CROSS JOIN LATERAL app.current_project_official_completion(p.id) AS official
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

CREATE OR REPLACE FUNCTION public.current_client_project_completion(
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2),
  is_overridden boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_project_completion_for_authenticated_user(p_project_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_request_project_completion_override(
  p_verified_owner_auth_subject uuid,
  p_project_id uuid,
  p_override_percent numeric,
  p_reason text,
  p_effective_at timestamptz,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  override_id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  effective_at timestamptz,
  created_at timestamptz,
  created_by uuid
)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_request_project_completion_override(p_verified_owner_auth_subject, p_project_id, p_override_percent, p_reason, p_effective_at, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_approve_project_completion_override(
  p_verified_owner_auth_subject uuid,
  p_override_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  override_id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  effective_at timestamptz,
  approved_at timestamptz,
  approved_by uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2)
)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_approve_project_completion_override(p_verified_owner_auth_subject, p_override_id, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_revoke_project_completion_override(
  p_verified_owner_auth_subject uuid,
  p_override_id uuid,
  p_revocation_reason text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  override_id uuid,
  project_id uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2)
)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_revoke_project_completion_override(p_verified_owner_auth_subject, p_override_id, p_revocation_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_official_project_completion(
  p_verified_owner_auth_subject uuid,
  p_project_id uuid
)
RETURNS TABLE (
  project_id uuid,
  calculated_completion_percent numeric(5,2),
  official_completion_percent numeric(5,2),
  is_overridden boolean,
  active_override_id uuid,
  override_percent numeric(5,2),
  override_reason text,
  override_effective_at timestamptz,
  override_created_at timestamptz,
  override_created_by uuid,
  override_approved_at timestamptz,
  override_approved_by uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_official_project_completion(p_verified_owner_auth_subject, p_project_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_completion_override_list(
  p_verified_owner_auth_subject uuid,
  p_project_id uuid,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  reason text,
  effective_at timestamptz,
  derived_state text,
  approved_at timestamptz,
  approved_by uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  created_at timestamptz,
  created_by uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_project_completion_override_list(p_verified_owner_auth_subject, p_project_id, p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_project_completion_override_detail(
  p_verified_owner_auth_subject uuid,
  p_override_id uuid
)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  override_percent numeric(5,2),
  reason text,
  effective_at timestamptz,
  derived_state text,
  approved_at timestamptz,
  approved_by uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  created_at timestamptz,
  created_by uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_project_completion_override_detail(p_verified_owner_auth_subject, p_override_id);
$function$;

COMMIT;
