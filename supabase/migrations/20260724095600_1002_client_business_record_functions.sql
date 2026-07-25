BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_optional_text(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT NULLIF(btrim(p_value), '');
$function$;

CREATE OR REPLACE FUNCTION app.assert_portal_client_link_target(p_portal_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app.users AS u
    WHERE u.id = p_portal_user_id
      AND u.user_type = 'CLIENT'
      AND u.status = 'ACTIVE'
      AND u.is_active
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
        INNER JOIN app.roles AS r
          ON r.code = ur.role_code
        WHERE ur.user_id = u.id
          AND ur.is_active
          AND r.is_staff_role
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.create_client_record(
  p_actor_auth_subject uuid,
  p_display_name text,
  p_legal_name text DEFAULT NULL,
  p_email citext DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_internal_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  client_number text,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  normalized_display_name text := btrim(coalesce(p_display_name, ''));
  normalized_legal_name text := app.normalize_optional_text(p_legal_name);
  normalized_email public.citext := NULLIF(lower(btrim(coalesce(p_email::text, ''))), '')::public.citext;
  normalized_phone text := app.normalize_optional_text(p_phone);
  normalized_address text := app.normalize_optional_text(p_address);
  normalized_internal_notes text := app.normalize_optional_text(p_internal_notes);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF normalized_display_name = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Client record.';
  END IF;

  INSERT INTO app.clients (
    display_name,
    legal_name,
    email,
    phone,
    address,
    internal_notes,
    created_by,
    updated_by
  )
  VALUES (
    normalized_display_name,
    normalized_legal_name,
    normalized_email,
    normalized_phone,
    normalized_address,
    normalized_internal_notes,
    actor_row.actor_user_id,
    actor_row.actor_user_id
  )
  RETURNING id, app.clients.client_number, app.clients.version_number
  INTO client_id, client_number, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'client_record_created',
    'client_record',
    client_id,
    NULL,
    'success',
    '{}'::jsonb,
    jsonb_build_object(
      'client_number', client_number,
      'changed_fields', ARRAY['display_name', 'legal_name', 'email', 'phone', 'address', 'internal_notes']
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

CREATE OR REPLACE FUNCTION app.update_client_record(
  p_actor_auth_subject uuid,
  p_client_id uuid,
  p_expected_version_number integer,
  p_display_name text,
  p_legal_name text DEFAULT NULL,
  p_email citext DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_internal_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  client_number text,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.clients%ROWTYPE;
  normalized_display_name text := btrim(coalesce(p_display_name, ''));
  normalized_legal_name text := app.normalize_optional_text(p_legal_name);
  normalized_email public.citext := NULLIF(lower(btrim(coalesce(p_email::text, ''))), '')::public.citext;
  normalized_phone text := app.normalize_optional_text(p_phone);
  normalized_address text := app.normalize_optional_text(p_address);
  normalized_internal_notes text := app.normalize_optional_text(p_internal_notes);
  changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF normalized_display_name = '' OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Client record.';
  END IF;

  SELECT * INTO existing_row FROM app.clients AS c WHERE c.id = p_client_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client record cannot be updated.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Client record version conflict.';
  END IF;

  IF existing_row.display_name IS DISTINCT FROM normalized_display_name THEN changed_fields := changed_fields || ARRAY['display_name']; END IF;
  IF existing_row.legal_name IS DISTINCT FROM normalized_legal_name THEN changed_fields := changed_fields || ARRAY['legal_name']; END IF;
  IF existing_row.email IS DISTINCT FROM normalized_email THEN changed_fields := changed_fields || ARRAY['email']; END IF;
  IF existing_row.phone IS DISTINCT FROM normalized_phone THEN changed_fields := changed_fields || ARRAY['phone']; END IF;
  IF existing_row.address IS DISTINCT FROM normalized_address THEN changed_fields := changed_fields || ARRAY['address']; END IF;
  IF existing_row.internal_notes IS DISTINCT FROM normalized_internal_notes THEN changed_fields := changed_fields || ARRAY['internal_notes']; END IF;

  UPDATE app.clients AS c
  SET display_name = normalized_display_name,
      legal_name = normalized_legal_name,
      email = normalized_email,
      phone = normalized_phone,
      address = normalized_address,
      internal_notes = normalized_internal_notes,
      updated_by = actor_row.actor_user_id
  WHERE c.id = p_client_id
  RETURNING c.id, c.client_number, c.version_number
  INTO client_id, client_number, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'client_record_updated',
    'client_record',
    client_id,
    NULL,
    'success',
    jsonb_build_object('version_number', existing_row.version_number),
    jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields),
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

CREATE OR REPLACE FUNCTION app.link_client_portal_user(
  p_actor_auth_subject uuid,
  p_client_id uuid,
  p_portal_user_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  portal_user_id uuid,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.clients%ROWTYPE;
  action_code varchar(120);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_portal_user_id IS NULL OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Client portal link.';
  END IF;
  PERFORM app.assert_portal_client_link_target(p_portal_user_id);

  SELECT * INTO existing_row FROM app.clients AS c WHERE c.id = p_client_id FOR UPDATE;
  IF existing_row.id IS NULL
     OR existing_row.status <> 'ACTIVE'
     OR NOT existing_row.is_active
     OR existing_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client record cannot be linked.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Client record version conflict.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app.clients AS c
    WHERE c.portal_user_id = p_portal_user_id
      AND c.id <> p_client_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Client portal user already linked.';
  END IF;

  IF existing_row.portal_user_id = p_portal_user_id THEN
    client_id := existing_row.id;
    portal_user_id := existing_row.portal_user_id;
    version_number := existing_row.version_number;
    RETURN NEXT;
    RETURN;
  END IF;

  action_code := CASE
    WHEN existing_row.portal_user_id IS NULL THEN 'client_portal_user_linked'
    ELSE 'client_portal_user_replaced'
  END;

  UPDATE app.clients AS c
  SET portal_user_id = p_portal_user_id,
      updated_by = actor_row.actor_user_id
  WHERE c.id = p_client_id
  RETURNING c.id, c.portal_user_id, c.version_number
  INTO client_id, portal_user_id, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    action_code,
    'client_record',
    client_id,
    NULL,
    'success',
    jsonb_build_object('portal_user', CASE WHEN existing_row.portal_user_id IS NULL THEN NULL ELSE '[masked]' END),
    jsonb_build_object('portal_user', '[masked]', 'version_number', version_number),
    NULL,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    jsonb_build_object('portal_link_changed', true)
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.unlink_client_portal_user(
  p_actor_auth_subject uuid,
  p_client_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  portal_user_id uuid,
  version_number integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.clients%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Client portal link.';
  END IF;

  SELECT * INTO existing_row FROM app.clients AS c WHERE c.id = p_client_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client record cannot be unlinked.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Client record version conflict.';
  END IF;

  IF existing_row.portal_user_id IS NULL THEN
    client_id := existing_row.id;
    portal_user_id := NULL;
    version_number := existing_row.version_number;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE app.clients AS c
  SET portal_user_id = NULL,
      updated_by = actor_row.actor_user_id
  WHERE c.id = p_client_id
  RETURNING c.id, c.portal_user_id, c.version_number
  INTO client_id, portal_user_id, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'client_portal_user_unlinked',
    'client_record',
    client_id,
    NULL,
    'success',
    jsonb_build_object('portal_user', '[masked]'),
    jsonb_build_object('portal_user', NULL, 'version_number', version_number),
    NULL,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    jsonb_build_object('portal_link_changed', true)
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.archive_client_record(
  p_actor_auth_subject uuid,
  p_client_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  status text,
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
  existing_row app.clients%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Client record.';
  END IF;

  SELECT * INTO existing_row FROM app.clients AS c WHERE c.id = p_client_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.archived_at IS NOT NULL OR existing_row.status = 'INACTIVE' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client record cannot be archived.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Client record version conflict.';
  END IF;

  UPDATE app.clients AS c
  SET status = 'INACTIVE',
      is_active = false,
      archived_at = now(),
      archived_by = actor_row.actor_user_id,
      portal_user_id = NULL,
      updated_by = actor_row.actor_user_id
  WHERE c.id = p_client_id
  RETURNING c.id, c.status::text, c.is_active, c.version_number
  INTO client_id, status, is_active, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'client_record_archived',
    'client_record',
    client_id,
    NULL,
    'success',
    jsonb_build_object('status', existing_row.status::text, 'is_active', existing_row.is_active, 'portal_user', CASE WHEN existing_row.portal_user_id IS NULL THEN NULL ELSE '[masked]' END),
    jsonb_build_object('status', status, 'is_active', is_active, 'portal_user', NULL, 'version_number', version_number),
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

CREATE OR REPLACE FUNCTION app.owner_client_record_detail(
  p_actor_auth_subject uuid,
  p_client_id uuid
)
RETURNS TABLE (
  id uuid,
  client_number text,
  portal_user_id uuid,
  display_name text,
  legal_name text,
  email text,
  phone text,
  address text,
  status text,
  internal_notes text,
  is_active boolean,
  archived_at timestamptz,
  archived_by uuid,
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
  SELECT
    c.id,
    c.client_number,
    c.portal_user_id,
    c.display_name::text,
    c.legal_name::text,
    c.email::text,
    c.phone::text,
    c.address,
    c.status::text,
    c.internal_notes,
    c.is_active,
    c.archived_at,
    c.archived_by,
    c.created_at,
    c.created_by,
    c.updated_at,
    c.updated_by,
    c.version_number
  FROM app.clients AS c
  WHERE c.id = p_client_id
    AND EXISTS (
      SELECT 1
      FROM app.require_active_owner_admin(p_actor_auth_subject) AS owner_gate
    );
$function$;

CREATE OR REPLACE FUNCTION app.owner_client_record_list(
  p_actor_auth_subject uuid,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  client_number text,
  display_name text,
  email text,
  phone text,
  status text,
  is_active boolean,
  archived_at timestamptz,
  portal_user_id uuid,
  version_number integer
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

  RETURN QUERY
  SELECT
    c.id,
    c.client_number,
    c.display_name::text,
    c.email::text,
    c.phone::text,
    c.status::text,
    c.is_active,
    c.archived_at,
    c.portal_user_id,
    c.version_number
  FROM app.clients AS c
  ORDER BY c.created_at DESC, c.id DESC
  LIMIT safe_limit
  OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_record_for_authenticated_user()
RETURNS TABLE (
  id uuid,
  client_number text,
  display_name text,
  legal_name text,
  email text,
  phone text,
  address text,
  status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    c.id,
    c.client_number,
    c.display_name::text,
    c.legal_name::text,
    c.email::text,
    c.phone::text,
    c.address,
    c.status::text
  FROM app.users AS u
  INNER JOIN app.clients AS c
    ON c.portal_user_id = u.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
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
      INNER JOIN app.roles AS r
        ON r.code = ur.role_code
      WHERE ur.user_id = u.id
        AND ur.is_active
        AND r.is_staff_role
    )
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.current_client_record()
RETURNS TABLE (
  id uuid,
  client_number text,
  display_name text,
  legal_name text,
  email text,
  phone text,
  address text,
  status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_record_for_authenticated_user();
$function$;

CREATE OR REPLACE FUNCTION public.server_create_client_record(p_verified_owner_auth_subject uuid, p_display_name text, p_legal_name text DEFAULT NULL, p_email citext DEFAULT NULL, p_phone text DEFAULT NULL, p_address text DEFAULT NULL, p_internal_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (client_id uuid, client_number text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.create_client_record(p_verified_owner_auth_subject, p_display_name, p_legal_name, p_email, p_phone, p_address, p_internal_notes, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_update_client_record(p_verified_owner_auth_subject uuid, p_client_id uuid, p_expected_version_number integer, p_display_name text, p_legal_name text DEFAULT NULL, p_email citext DEFAULT NULL, p_phone text DEFAULT NULL, p_address text DEFAULT NULL, p_internal_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (client_id uuid, client_number text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.update_client_record(p_verified_owner_auth_subject, p_client_id, p_expected_version_number, p_display_name, p_legal_name, p_email, p_phone, p_address, p_internal_notes, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_link_client_portal_user(p_verified_owner_auth_subject uuid, p_client_id uuid, p_portal_user_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (client_id uuid, portal_user_id uuid, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.link_client_portal_user(p_verified_owner_auth_subject, p_client_id, p_portal_user_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_unlink_client_portal_user(p_verified_owner_auth_subject uuid, p_client_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (client_id uuid, portal_user_id uuid, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.unlink_client_portal_user(p_verified_owner_auth_subject, p_client_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_archive_client_record(p_verified_owner_auth_subject uuid, p_client_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (client_id uuid, status text, is_active boolean, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.archive_client_record(p_verified_owner_auth_subject, p_client_id, p_expected_version_number, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_client_record_detail(p_verified_owner_auth_subject uuid, p_client_id uuid)
RETURNS TABLE (id uuid, client_number text, portal_user_id uuid, display_name text, legal_name text, email text, phone text, address text, status text, internal_notes text, is_active boolean, archived_at timestamptz, archived_by uuid, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_client_record_detail(p_verified_owner_auth_subject, p_client_id);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_client_record_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, client_number text, display_name text, email text, phone text, status text, is_active boolean, archived_at timestamptz, portal_user_id uuid, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_client_record_list(p_verified_owner_auth_subject, p_limit, p_offset);
$function$;

COMMIT;
