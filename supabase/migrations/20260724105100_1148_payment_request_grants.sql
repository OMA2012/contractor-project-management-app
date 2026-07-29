BEGIN;

REVOKE ALL ON app.payment_request_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.payment_requests FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.contractor_local_date() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.payment_request_effective_status(app.payment_request_status, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_payment_request_client_context() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_payment_request(uuid, uuid, numeric, char, date, date, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_update_payment_request(uuid, uuid, integer, uuid, numeric, char, date, date, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_send_payment_request(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_cancel_payment_request(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_payment_request_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_payment_request_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_refresh_payment_request_overdue(uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_payment_request_list(integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_view_payment_request_detail(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_payment_request(uuid, uuid, numeric, char, date, date, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_payment_request(uuid, uuid, integer, uuid, numeric, char, date, date, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_send_payment_request(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_cancel_payment_request(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_payment_request_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_payment_request_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_refresh_payment_request_overdue(uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_payment_request(uuid, uuid, numeric, char, date, date, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_payment_request(uuid, uuid, integer, uuid, numeric, char, date, date, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_send_payment_request(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_cancel_payment_request(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_payment_request_list(uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_payment_request_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_refresh_payment_request_overdue(uuid, text, text, text, inet) TO service_role;

REVOKE ALL ON FUNCTION public.current_client_payment_request_list(integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_view_payment_request_detail(uuid, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.current_client_payment_request_list(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_view_payment_request_detail(uuid, text, text) TO authenticated;

COMMIT;
