BEGIN;

-- Serializes first-owner bootstrap checks so two operator sessions cannot both
-- observe an empty owner state and create competing bootstrap rows.
CREATE OR REPLACE FUNCTION app.require_active_owner_admin(p_actor_auth_subject uuid)
RETURNS TABLE (
  actor_user_id uuid,
  actor_auth_subject uuid,
  effective_role_code varchar(40)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT u.id, u.auth_subject, 'owner_admin'::varchar(40)
  FROM app.users AS u
  WHERE u.auth_subject = p_actor_auth_subject
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      WHERE ur.user_id = u.id
        AND ur.role_code = 'owner_admin'
        AND ur.is_active
    );
$function$;

CREATE OR REPLACE FUNCTION app.record_denied_privileged_operation(
  p_actor_auth_subject uuid,
  p_action varchar(120),
  p_entity_type varchar(80),
  p_entity_id uuid DEFAULT NULL,
  p_reason_code varchar(40) DEFAULT 'authorization_denied',
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
BEGIN
  IF p_action IS NULL
     OR p_action !~ '^[a-z][a-z0-9_]{0,119}$'
     OR p_action LIKE '%token%'
     OR p_action LIKE '%secret%'
     OR p_action LIKE '%url%'
     OR p_action LIKE 'http%' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Denied-operation action code is invalid.';
  END IF;
  IF p_entity_type IS NULL
     OR p_entity_type !~ '^[a-z][a-z0-9_]{0,79}$'
     OR p_entity_type LIKE '%token%'
     OR p_entity_type LIKE '%secret%'
     OR p_entity_type LIKE '%url%'
     OR p_entity_type LIKE 'http%' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Denied-operation entity type code is invalid.';
  END IF;
  IF p_reason_code NOT IN (
    'authorization_denied',
    'inactive_actor',
    'insufficient_role',
    'invalid_actor_type',
    'invalid_target_state'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Denied-operation reason code is invalid.';
  END IF;

  SELECT
    u.id AS actor_user_id,
    u.auth_subject,
    (
      SELECT ur.role_code
      FROM app.user_roles AS ur
      WHERE ur.user_id = u.id
        AND ur.is_active
        AND ur.role_code IN ('owner_admin', 'client')
      ORDER BY CASE ur.role_code WHEN 'owner_admin' THEN 1 ELSE 2 END
      LIMIT 1
    )::varchar(40) AS effective_role_code
  INTO actor_row
  FROM app.users AS u
  WHERE u.auth_subject = p_actor_auth_subject;

  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  RETURN app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.auth_subject,
    actor_row.effective_role_code,
    'denied_privileged_operation',
    p_entity_type,
    p_entity_id,
    NULL,
    'denied',
    '{}'::jsonb,
    '{}'::jsonb,
    p_reason_code,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('requested_action', p_action)
  );
END
$function$;

CREATE OR REPLACE FUNCTION app.expire_elapsed_client_invitations(p_invited_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  expired_count integer;
BEGIN
  UPDATE app.user_invitations AS ui
  SET status = 'EXPIRED'
  WHERE ui.invited_user_id = p_invited_user_id
    AND ui.status = 'PENDING'
    AND ui.expires_at <= now();

  GET DIAGNOSTICS expired_count = ROW_COUNT;
  RETURN expired_count;
END
$function$;

CREATE OR REPLACE FUNCTION app.create_client_invitation(
  p_actor_auth_subject uuid,
  p_invited_auth_subject uuid,
  p_normalized_email citext,
  p_token_hash bytea,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  invited_user_id uuid,
  invitation_id uuid,
  expires_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  created_invite_at timestamptz := now();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF btrim(p_normalized_email::text) = '' OR p_normalized_email::text <> lower(btrim(p_normalized_email::text)) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid normalized email.';
  END IF;
  IF octet_length(p_token_hash) <> 32 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation token digest must be 32 bytes.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM app.users AS u
    WHERE u.email = p_normalized_email OR u.auth_subject = p_invited_auth_subject
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Application account already exists.';
  END IF;

  INSERT INTO app.users (auth_subject, email, user_type, status, is_active, created_by, updated_by)
  VALUES (p_invited_auth_subject, p_normalized_email, 'CLIENT', 'INVITED', false, actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id INTO invited_user_id;

  INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
  VALUES (invited_user_id, p_token_hash, 'PENDING', created_invite_at, created_invite_at + interval '7 days', actor_row.actor_user_id)
  RETURNING id, app.user_invitations.expires_at INTO invitation_id, expires_at;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'invitation_created', 'user_invitation', invitation_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('invited_user_id', invited_user_id, 'expires_at', expires_at), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.resend_client_invitation(
  p_actor_auth_subject uuid,
  p_invited_user_id uuid,
  p_token_hash bytea,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  invitation_id uuid,
  resent_from_invitation_id uuid,
  expires_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  invited_row app.users%ROWTYPE;
  previous_invite app.user_invitations%ROWTYPE;
  created_invite_at timestamptz := now();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF octet_length(p_token_hash) <> 32 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation token digest must be 32 bytes.';
  END IF;
  SELECT * INTO invited_row FROM app.users AS u WHERE u.id = p_invited_user_id FOR UPDATE;
  IF invited_row.id IS NULL OR invited_row.user_type <> 'CLIENT' OR invited_row.status <> 'INVITED' OR invited_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation resend requires an invited client account.';
  END IF;

  SELECT * INTO previous_invite
  FROM app.user_invitations AS ui
  WHERE ui.invited_user_id = p_invited_user_id
  ORDER BY ui.created_at DESC, ui.id DESC
  LIMIT 1
  FOR UPDATE;

  IF previous_invite.id IS NULL OR previous_invite.status = 'ACCEPTED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation cannot be resent.';
  END IF;

  IF previous_invite.status = 'PENDING' AND previous_invite.expires_at <= now() THEN
    UPDATE app.user_invitations SET status = 'EXPIRED' WHERE id = previous_invite.id;
  ELSIF previous_invite.status = 'PENDING' THEN
    UPDATE app.user_invitations
    SET status = 'REVOKED', revoked_at = now(), revoked_by = actor_row.actor_user_id, revoke_reason = 'Resent invitation.'
    WHERE id = previous_invite.id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM app.user_invitations AS ui
    WHERE ui.invited_user_id = p_invited_user_id AND ui.status = 'PENDING'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Pending invitation remains.';
  END IF;

  resent_from_invitation_id := previous_invite.id;
  INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by, resent_from_invitation_id)
  VALUES (p_invited_user_id, p_token_hash, 'PENDING', created_invite_at, created_invite_at + interval '7 days', actor_row.actor_user_id, resent_from_invitation_id)
  RETURNING id, app.user_invitations.expires_at INTO invitation_id, expires_at;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'invitation_resent', 'user_invitation', invitation_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('resent_from_invitation_id', resent_from_invitation_id), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.revoke_client_invitation(
  p_actor_auth_subject uuid,
  p_invitation_id uuid,
  p_revoke_reason text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  invite_row app.user_invitations%ROWTYPE;
  invited_row app.users%ROWTYPE;
  reason_text text := btrim(coalesce(p_revoke_reason, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF reason_text = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Revocation reason is required.';
  END IF;
  SELECT * INTO invite_row
  FROM app.user_invitations AS i
  WHERE i.id = p_invitation_id
  FOR UPDATE;

  IF invite_row.id IS NOT NULL THEN
    SELECT * INTO invited_row
    FROM app.users AS u
    WHERE u.id = invite_row.invited_user_id
    FOR UPDATE;
  END IF;

  IF invite_row.id IS NULL
     OR invite_row.invited_user_id <> invited_row.id
     OR invited_row.user_type <> 'CLIENT'
     OR invited_row.status <> 'INVITED'
     OR invited_row.is_active
     OR invite_row.status <> 'PENDING'
     OR invite_row.expires_at <= now()
     OR invite_row.accepted_at IS NOT NULL
     OR invite_row.revoked_at IS NOT NULL
     OR invite_row.revoked_by IS NOT NULL
     OR invite_row.revoke_reason IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation cannot be revoked.';
  END IF;
  UPDATE app.user_invitations
  SET status = 'REVOKED', revoked_at = now(), revoked_by = actor_row.actor_user_id, revoke_reason = reason_text
  WHERE id = p_invitation_id;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'invitation_revoked', 'user_invitation', p_invitation_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('status', 'REVOKED'), reason_text, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN p_invitation_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.accept_client_invitation(
  p_invited_auth_subject uuid,
  p_token_hash bytea,
  p_full_name text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  invite_row app.user_invitations%ROWTYPE;
  user_row app.users%ROWTYPE;
  role_id uuid;
  trimmed_name text := btrim(coalesce(p_full_name, ''));
BEGIN
  IF octet_length(p_token_hash) <> 32 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation token digest must be 32 bytes.';
  END IF;
  IF trimmed_name = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Full name is required.';
  END IF;
  SELECT * INTO invite_row FROM app.user_invitations AS ui WHERE ui.token_hash = p_token_hash FOR UPDATE;
  IF invite_row.id IS NULL OR invite_row.status <> 'PENDING' OR invite_row.expires_at <= now() THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation cannot be accepted.';
  END IF;
  SELECT * INTO user_row FROM app.users AS u WHERE u.id = invite_row.invited_user_id FOR UPDATE;
  IF user_row.auth_subject <> p_invited_auth_subject OR user_row.user_type <> 'CLIENT' OR user_row.status <> 'INVITED' OR user_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation cannot be accepted.';
  END IF;
  IF EXISTS (SELECT 1 FROM app.user_profiles AS up WHERE up.user_id = user_row.id)
     OR EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = user_row.id AND ur.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation was already accepted.';
  END IF;
  IF NOT app.is_active_owner(invite_row.invited_by) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
  VALUES (user_row.id, trimmed_name, invite_row.invited_by, invite_row.invited_by);
  INSERT INTO app.user_roles (user_id, role_code, assigned_by)
  VALUES (user_row.id, 'client', invite_row.invited_by)
  RETURNING id INTO role_id;
  UPDATE app.users SET status = 'ACTIVE', is_active = true, updated_by = invite_row.invited_by WHERE id = user_row.id;
  UPDATE app.user_invitations SET status = 'ACCEPTED', accepted_at = now() WHERE id = invite_row.id;

  PERFORM app.write_activity_log(user_row.id, user_row.auth_subject, NULL, 'invitation_accepted', 'user_invitation', invite_row.id, NULL, 'success', '{}'::jsonb, jsonb_build_object('status', 'ACCEPTED'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(user_row.id, user_row.auth_subject, NULL, 'role_assigned', 'user_role', role_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('role_code', 'client'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(user_row.id, user_row.auth_subject, 'client', 'account_activated', 'user', user_row.id, NULL, 'success', jsonb_build_object('status', 'INVITED', 'is_active', false), jsonb_build_object('status', 'ACTIVE', 'is_active', true), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN user_row.id;
END
$function$;

CREATE OR REPLACE FUNCTION app.suspend_client_account(p_actor_auth_subject uuid, p_client_user_id uuid, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; target_row app.users%ROWTYPE; reason_text text := btrim(coalesce(p_reason, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Reason is required.'; END IF;
  SELECT * INTO target_row FROM app.users AS u WHERE u.id = p_client_user_id FOR UPDATE;
  IF target_row.user_type <> 'CLIENT' OR target_row.status <> 'ACTIVE' OR NOT target_row.is_active THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client account cannot transition.'; END IF;
  UPDATE app.users SET status = 'SUSPENDED', is_active = false, updated_by = actor_row.actor_user_id WHERE id = p_client_user_id;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'account_suspended', 'user', p_client_user_id, NULL, 'success', jsonb_build_object('status','ACTIVE','is_active',true), jsonb_build_object('status','SUSPENDED','is_active',false), reason_text, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN p_client_user_id;
END $function$;

CREATE OR REPLACE FUNCTION app.reactivate_client_account(p_actor_auth_subject uuid, p_client_user_id uuid, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; target_row app.users%ROWTYPE; reason_text text := btrim(coalesce(p_reason, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Reason is required.'; END IF;
  SELECT * INTO target_row FROM app.users AS u WHERE u.id = p_client_user_id FOR UPDATE;
  IF target_row.user_type <> 'CLIENT' OR target_row.status <> 'SUSPENDED' OR target_row.is_active THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client account cannot transition.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = p_client_user_id AND ur.role_code = 'client' AND ur.is_active)
     OR EXISTS (SELECT 1 FROM app.user_roles AS ur JOIN app.roles AS r ON r.code = ur.role_code WHERE ur.user_id = p_client_user_id AND ur.is_active AND r.is_staff_role) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client account cannot transition.';
  END IF;
  UPDATE app.users SET status = 'ACTIVE', is_active = true, updated_by = actor_row.actor_user_id WHERE id = p_client_user_id;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'account_reactivated', 'user', p_client_user_id, NULL, 'success', jsonb_build_object('status','SUSPENDED','is_active',false), jsonb_build_object('status','ACTIVE','is_active',true), reason_text, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN p_client_user_id;
END $function$;

CREATE OR REPLACE FUNCTION app.disable_client_account(p_actor_auth_subject uuid, p_client_user_id uuid, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; target_row app.users%ROWTYPE; reason_text text := btrim(coalesce(p_reason, ''));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Reason is required.'; END IF;
  SELECT * INTO target_row FROM app.users AS u WHERE u.id = p_client_user_id FOR UPDATE;
  IF target_row.user_type <> 'CLIENT' OR target_row.status NOT IN ('ACTIVE','SUSPENDED') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client account cannot transition.'; END IF;
  UPDATE app.users SET status = 'DISABLED', is_active = false, deactivated_at = now(), deactivated_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE id = p_client_user_id;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'account_disabled', 'user', p_client_user_id, NULL, 'success', jsonb_build_object('status',target_row.status::text,'is_active',target_row.is_active), jsonb_build_object('status','DISABLED','is_active',false), reason_text, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN p_client_user_id;
END $function$;

CREATE OR REPLACE FUNCTION app.bootstrap_first_owner(p_owner_auth_subject uuid, p_normalized_email citext, p_owner_full_name text, p_token_hash bytea, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL)
RETURNS TABLE (owner_user_id uuid, invitation_id uuid, expires_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE name_text text := btrim(coalesce(p_owner_full_name,'')); created_invite_at timestamptz := now(); role_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('app.first_owner_bootstrap', 0));
  IF name_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Owner name is required.'; END IF;
  IF octet_length(p_token_hash) <> 32 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation token digest must be 32 bytes.'; END IF;
  IF EXISTS (SELECT 1 FROM app.user_roles WHERE role_code = 'owner_admin')
     OR EXISTS (SELECT 1 FROM app.users AS u JOIN app.user_roles AS ur ON ur.user_id = u.id WHERE ur.role_code = 'owner_admin' AND u.status IN ('INVITED','ACTIVE'))
     OR EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'first_owner_bootstrap' AND outcome = 'success') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  INSERT INTO app.users (auth_subject, email, user_type, status, is_active)
  VALUES (p_owner_auth_subject, p_normalized_email, 'STAFF', 'INVITED', false)
  RETURNING id INTO owner_user_id;
  INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
  VALUES (owner_user_id, name_text, owner_user_id, owner_user_id);
  PERFORM set_config('app.allow_owner_bootstrap', 'on', true);
  INSERT INTO app.user_roles (user_id, role_code, assigned_by) VALUES (owner_user_id, 'owner_admin', owner_user_id) RETURNING id INTO role_id;
  PERFORM set_config('app.allow_owner_bootstrap', 'off', true);
  INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
  VALUES (owner_user_id, p_token_hash, 'PENDING', created_invite_at, created_invite_at + interval '7 days', owner_user_id)
  RETURNING id, app.user_invitations.expires_at INTO invitation_id, expires_at;
  PERFORM app.write_activity_log(NULL, NULL, NULL, 'first_owner_bootstrap', 'user', owner_user_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('status','INVITED'), NULL, NULL, NULL, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(NULL, NULL, NULL, 'role_assigned', 'user_role', role_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('role_code','owner_admin'), NULL, NULL, NULL, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(NULL, NULL, NULL, 'invitation_created', 'user_invitation', invitation_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('owner_user_id', owner_user_id, 'expires_at', expires_at), NULL, NULL, NULL, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.activate_current_invited_owner(p_owner_auth_subject uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE owner_row app.users%ROWTYPE; invite_row app.user_invitations%ROWTYPE;
BEGIN
  SELECT * INTO owner_row FROM app.users AS u WHERE u.auth_subject = p_owner_auth_subject FOR UPDATE;
  IF owner_row.id IS NULL OR owner_row.user_type <> 'STAFF' OR owner_row.status <> 'INVITED' OR owner_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Owner invitation cannot be activated.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app.user_profiles AS up WHERE up.user_id = owner_row.id AND btrim(up.full_name) <> '')
     OR NOT EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = owner_row.id AND ur.role_code = 'owner_admin' AND ur.is_active)
     OR EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = owner_row.id AND ur.role_code = 'client' AND ur.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Owner invitation cannot be activated.';
  END IF;
  SELECT * INTO invite_row FROM app.user_invitations AS ui WHERE ui.invited_user_id = owner_row.id AND ui.status = 'PENDING' ORDER BY ui.created_at DESC LIMIT 1 FOR UPDATE;
  IF invite_row.id IS NULL OR invite_row.expires_at <= now() THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Owner invitation cannot be activated.';
  END IF;
  UPDATE app.user_invitations SET status = 'ACCEPTED', accepted_at = now() WHERE id = invite_row.id;
  UPDATE app.users SET status = 'ACTIVE', is_active = true, updated_by = owner_row.id WHERE id = owner_row.id;
  PERFORM app.write_activity_log(owner_row.id, owner_row.auth_subject, NULL, 'invitation_accepted', 'user_invitation', invite_row.id, NULL, 'success', '{}'::jsonb, jsonb_build_object('status','ACCEPTED'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(owner_row.id, owner_row.auth_subject, 'owner_admin', 'account_activated', 'user', owner_row.id, NULL, 'success', jsonb_build_object('status','INVITED','is_active',false), jsonb_build_object('status','ACTIVE','is_active',true), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN owner_row.id;
END $function$;

COMMIT;
