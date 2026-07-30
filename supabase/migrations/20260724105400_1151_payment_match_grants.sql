BEGIN;

REVOKE ALL ON app.payment_matches FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.client_payment_transaction_id(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.client_payment_economically_active(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.lock_payment_economic_chain(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.payment_request_amounts(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.payment_request_effective_status(app.payment_request_status, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.payment_request_calculated_status(app.payment_request_status, numeric, date, timestamptz, numeric, numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.sync_payment_request_status_from_matches(uuid, uuid, text, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.validate_payment_match_relationship(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_payment_match(uuid, uuid, uuid, numeric, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_update_payment_match(uuid, uuid, uuid, uuid, numeric, uuid, uuid, numeric, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_approve_payment_match(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_void_payment_match(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_payment_match_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_payment_match_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_client_payment_availability(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_payment_request_balance(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_payment_match(uuid, uuid, uuid, numeric, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_payment_match(uuid, uuid, uuid, uuid, numeric, uuid, uuid, numeric, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_approve_payment_match(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_void_payment_match(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_payment_match_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_payment_match_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_client_payment_availability(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_payment_request_balance(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_payment_match(uuid, uuid, uuid, numeric, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_payment_match(uuid, uuid, uuid, uuid, numeric, uuid, uuid, numeric, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_approve_payment_match(uuid, uuid, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_void_payment_match(uuid, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_payment_match_list(uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_payment_match_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_client_payment_availability(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_payment_request_balance(uuid, uuid) TO service_role;

COMMIT;
