BEGIN;

REVOKE ALL ON app.currency_exchanges FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.currency_exchanges_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_currency_exchange_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_currency_exchange_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.normalize_currency_exchange_reference(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.currency_exchange_duplicate_fingerprint(uuid, uuid, date, char, char, numeric, numeric, char, char, numeric, numeric, char, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.round_half_up_positive(numeric, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.ensure_currency_exchange_clearing_ledger_account(char) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.ensure_currency_exchange_fee_ledger_account(char) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.currency_exchange_calculate_destination(numeric, char, char, char, char, numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.currency_exchange_reporting_snapshot(numeric, char, char, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.currency_exchange_validate_accounts(uuid, uuid, uuid, numeric, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_currency_exchange(uuid, uuid, uuid, numeric, uuid, numeric, uuid, date, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_update_currency_exchange(uuid, uuid, integer, uuid, uuid, numeric, uuid, numeric, uuid, date, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_submit_currency_exchange(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_reject_currency_exchange(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_approve_currency_exchange(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_currency_exchange_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_currency_exchange_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_currency_exchange(uuid, uuid, uuid, numeric, uuid, numeric, uuid, date, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_currency_exchange(uuid, uuid, integer, uuid, uuid, numeric, uuid, numeric, uuid, date, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_submit_currency_exchange(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_reject_currency_exchange(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_approve_currency_exchange(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_currency_exchange_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_currency_exchange_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_currency_exchange(uuid, uuid, uuid, numeric, uuid, numeric, uuid, date, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_currency_exchange(uuid, uuid, integer, uuid, uuid, numeric, uuid, numeric, uuid, date, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_submit_currency_exchange(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_reject_currency_exchange(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_approve_currency_exchange(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_currency_exchange_list(uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_currency_exchange_detail(uuid, uuid) TO service_role;

COMMIT;
