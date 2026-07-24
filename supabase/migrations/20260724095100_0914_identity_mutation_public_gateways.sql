BEGIN;

CREATE OR REPLACE FUNCTION public.server_create_client_invitation(p_verified_owner_auth_subject uuid, p_invited_auth_subject uuid, p_normalized_email citext, p_token_hash bytea, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (invited_user_id uuid, invitation_id uuid, expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.create_client_invitation(p_verified_owner_auth_subject, p_invited_auth_subject, p_normalized_email, p_token_hash, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_resend_client_invitation(p_verified_owner_auth_subject uuid, p_invited_user_id uuid, p_token_hash bytea, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (invitation_id uuid, resent_from_invitation_id uuid, expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.resend_client_invitation(p_verified_owner_auth_subject, p_invited_user_id, p_token_hash, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_revoke_client_invitation(p_verified_owner_auth_subject uuid, p_invitation_id uuid, p_revoke_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.revoke_client_invitation(p_verified_owner_auth_subject, p_invitation_id, p_revoke_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_accept_client_invitation(p_verified_invited_auth_subject uuid, p_token_hash bytea, p_full_name text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.accept_client_invitation(p_verified_invited_auth_subject, p_token_hash, p_full_name, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_suspend_client_account(p_verified_owner_auth_subject uuid, p_client_user_id uuid, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.suspend_client_account(p_verified_owner_auth_subject, p_client_user_id, p_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_reactivate_client_account(p_verified_owner_auth_subject uuid, p_client_user_id uuid, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.reactivate_client_account(p_verified_owner_auth_subject, p_client_user_id, p_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_disable_client_account(p_verified_owner_auth_subject uuid, p_client_user_id uuid, p_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.disable_client_account(p_verified_owner_auth_subject, p_client_user_id, p_reason, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
$function$;

CREATE OR REPLACE FUNCTION public.server_bootstrap_first_owner(p_owner_auth_subject uuid, p_normalized_email citext, p_owner_full_name text, p_token_hash bytea, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL)
RETURNS TABLE (owner_user_id uuid, invitation_id uuid, expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.bootstrap_first_owner(p_owner_auth_subject, p_normalized_email, p_owner_full_name, p_token_hash, p_request_identifier, p_correlation_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_record_denied_privileged_operation(p_actor_auth_subject uuid, p_action varchar(120), p_entity_type varchar(80), p_entity_id uuid DEFAULT NULL, p_reason_code varchar(40) DEFAULT 'authorization_denied', p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL, p_metadata jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.record_denied_privileged_operation(p_actor_auth_subject, p_action, p_entity_type, p_entity_id, p_reason_code, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address, p_metadata);
$function$;

CREATE OR REPLACE FUNCTION public.activate_current_invited_owner()
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT app.activate_current_invited_owner(auth.uid());
$function$;

COMMIT;
