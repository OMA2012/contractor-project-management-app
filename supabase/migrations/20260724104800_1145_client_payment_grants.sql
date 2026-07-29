BEGIN;

REVOKE ALL ON app.client_payments FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.normalize_client_payment_reference(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.client_payment_duplicate_fingerprint(uuid, uuid, char, date, numeric, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.ensure_client_payment_control_ledger_account(char) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_client_payment(uuid, uuid, numeric, char, date, uuid, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_update_client_payment(uuid, uuid, integer, numeric, char, date, uuid, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_verify_client_submitted_payment(uuid, uuid, integer, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_submit_client_payment(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_reject_client_payment(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_approve_client_payment(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_client_payment_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_client_payment_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_client_payment_totals(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_submit_payment(uuid, numeric, char, date, text, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_approved_payment_list(integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_approved_payment_detail(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_client_payment(uuid, uuid, numeric, char, date, uuid, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_client_payment(uuid, uuid, integer, numeric, char, date, uuid, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_verify_client_submitted_payment(uuid, uuid, integer, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_submit_client_payment(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_reject_client_payment(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_approve_client_payment(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_client_payment_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_client_payment_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_client_payment_totals(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_client_payment(uuid, uuid, numeric, char, date, uuid, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_client_payment(uuid, uuid, integer, numeric, char, date, uuid, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_verify_client_submitted_payment(uuid, uuid, integer, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_submit_client_payment(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_reject_client_payment(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_approve_client_payment(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_client_payment_list(uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_client_payment_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_client_payment_totals(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.current_client_submit_payment(uuid, numeric, char, date, text, text, text, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_approved_payment_list(integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_approved_payment_detail(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.current_client_submit_payment(uuid, numeric, char, date, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_approved_payment_list(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_approved_payment_detail(uuid) TO authenticated;

COMMIT;
