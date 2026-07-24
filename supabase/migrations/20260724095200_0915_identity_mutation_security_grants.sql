BEGIN;

REVOKE ALL ON FUNCTION app.require_active_owner_admin(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.record_denied_privileged_operation(uuid, varchar, varchar, uuid, varchar, text, text, text, inet, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.expire_elapsed_client_invitations(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_client_invitation(uuid, uuid, citext, bytea, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.resend_client_invitation(uuid, uuid, bytea, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.revoke_client_invitation(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.accept_client_invitation(uuid, bytea, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.suspend_client_account(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.reactivate_client_account(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.disable_client_account(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.bootstrap_first_owner(uuid, citext, text, bytea, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.activate_current_invited_owner(uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_create_client_invitation(uuid, uuid, citext, bytea, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_resend_client_invitation(uuid, uuid, bytea, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_revoke_client_invitation(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_accept_client_invitation(uuid, bytea, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_suspend_client_account(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_reactivate_client_account(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_disable_client_account(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_bootstrap_first_owner(uuid, citext, text, bytea, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_record_denied_privileged_operation(uuid, varchar, varchar, uuid, varchar, text, text, text, inet, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.activate_current_invited_owner() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.server_create_client_invitation(uuid, uuid, citext, bytea, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_resend_client_invitation(uuid, uuid, bytea, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_revoke_client_invitation(uuid, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_accept_client_invitation(uuid, bytea, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_suspend_client_account(uuid, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_reactivate_client_account(uuid, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_disable_client_account(uuid, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_bootstrap_first_owner(uuid, citext, text, bytea, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_record_denied_privileged_operation(uuid, varchar, varchar, uuid, varchar, text, text, text, inet, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.activate_current_invited_owner() TO authenticated;

COMMIT;
