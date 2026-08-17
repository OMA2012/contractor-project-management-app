BEGIN;

CREATE TABLE app.client_invitation_links (
  invitation_id uuid PRIMARY KEY REFERENCES app.user_invitations(id) ON DELETE RESTRICT,
  client_id uuid NOT NULL REFERENCES app.clients(id) ON DELETE RESTRICT,
  invited_user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT
);

ALTER TABLE app.client_invitation_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.client_invitation_links FORCE ROW LEVEL SECURITY;
REVOKE ALL ON app.client_invitation_links FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION app.create_client_record_invitation(
  p_actor_auth_subject uuid,
  p_client_id uuid,
  p_invited_auth_subject uuid,
  p_token_hash bytea,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (invited_user_id uuid, invitation_id uuid, expires_at timestamptz)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  client_row app.clients%ROWTYPE;
  invite_row record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO client_row FROM app.clients AS c WHERE c.id = p_client_id FOR UPDATE;
  IF client_row.id IS NULL
     OR client_row.status <> 'ACTIVE'
     OR NOT client_row.is_active
     OR client_row.archived_at IS NOT NULL
     OR client_row.portal_user_id IS NOT NULL
     OR client_row.email IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client invitation cannot be created.';
  END IF;

  SELECT * INTO invite_row
  FROM app.create_client_invitation(
    p_actor_auth_subject,
    p_invited_auth_subject,
    client_row.email,
    p_token_hash,
    p_request_identifier,
    p_correlation_identifier,
    p_session_identifier,
    p_ip_address
  );

  INSERT INTO app.client_invitation_links (invitation_id, client_id, invited_user_id, created_by)
  VALUES (invite_row.invitation_id, p_client_id, invite_row.invited_user_id, actor_row.actor_user_id);

  invited_user_id := invite_row.invited_user_id;
  invitation_id := invite_row.invitation_id;
  expires_at := invite_row.expires_at;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.accept_client_invitation_and_link_record(
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
  link_row app.client_invitation_links%ROWTYPE;
  client_row app.clients%ROWTYPE;
  accepted_user_id uuid;
BEGIN
  SELECT * INTO invite_row FROM app.user_invitations AS ui WHERE ui.token_hash = p_token_hash;
  IF invite_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation cannot be accepted.';
  END IF;

  SELECT * INTO link_row
  FROM app.client_invitation_links AS cil
  WHERE cil.invitation_id = invite_row.id
  FOR UPDATE;
  IF link_row.invitation_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation cannot be accepted.';
  END IF;

  SELECT * INTO client_row FROM app.clients AS c WHERE c.id = link_row.client_id FOR UPDATE;
  IF client_row.id IS NULL
     OR client_row.portal_user_id IS NOT NULL
     OR client_row.archived_at IS NOT NULL
     OR client_row.status <> 'ACTIVE'
     OR NOT client_row.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invitation cannot be accepted.';
  END IF;

  accepted_user_id := app.accept_client_invitation(
    p_invited_auth_subject,
    p_token_hash,
    p_full_name,
    p_request_identifier,
    p_correlation_identifier,
    p_session_identifier,
    p_ip_address
  );

  UPDATE app.clients AS c
  SET portal_user_id = accepted_user_id,
      updated_by = link_row.created_by
  WHERE c.id = link_row.client_id
    AND c.version_number = client_row.version_number
    AND c.portal_user_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Client record version conflict.';
  END IF;

  PERFORM app.write_activity_log(
    link_row.created_by,
    NULL,
    'owner_admin',
    'client_portal_user_linked',
    'client_record',
    link_row.client_id,
    NULL,
    'success',
    jsonb_build_object('portal_user', NULL, 'version_number', client_row.version_number),
    jsonb_build_object('portal_user', '[masked]'),
    NULL,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    jsonb_build_object('source', 'client_invitation_acceptance')
  );

  RETURN accepted_user_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_client_invitation_status(
  p_actor_auth_subject uuid,
  p_client_id uuid
)
RETURNS TABLE (
  invited_user_id uuid,
  invitation_id uuid,
  status text,
  expires_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  RETURN QUERY
  SELECT cil.invited_user_id, ui.id, ui.status::text, ui.expires_at
  FROM app.client_invitation_links AS cil
  INNER JOIN app.user_invitations AS ui
    ON ui.id = cil.invitation_id
  WHERE cil.client_id = p_client_id
  ORDER BY ui.created_at DESC, ui.id DESC
  LIMIT 1;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_create_client_record_invitation(
  p_verified_owner_auth_subject uuid,
  p_client_id uuid,
  p_invited_auth_subject uuid,
  p_token_hash bytea,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (invited_user_id uuid, invitation_id uuid, expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.create_client_record_invitation(p_verified_owner_auth_subject, p_client_id, p_invited_auth_subject, p_token_hash, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_accept_client_invitation(
  p_verified_invited_auth_subject uuid,
  p_token_hash bytea,
  p_full_name text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.accept_client_invitation_and_link_record(p_verified_invited_auth_subject, p_token_hash, p_full_name, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_client_invitation_status(
  p_verified_owner_auth_subject uuid,
  p_client_id uuid
)
RETURNS TABLE (invited_user_id uuid, invitation_id uuid, status text, expires_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.owner_client_invitation_status(p_verified_owner_auth_subject, p_client_id);
$function$;

REVOKE ALL ON FUNCTION app.create_client_record_invitation(uuid, uuid, uuid, bytea, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.accept_client_invitation_and_link_record(uuid, bytea, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_client_invitation_status(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_create_client_record_invitation(uuid, uuid, uuid, bytea, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_client_invitation_status(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_create_client_record_invitation(uuid, uuid, uuid, bytea, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_accept_client_invitation(uuid, bytea, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_client_invitation_status(uuid, uuid) TO service_role;

COMMIT;
