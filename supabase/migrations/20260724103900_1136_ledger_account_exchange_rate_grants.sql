BEGIN;

REVOKE ALL ON app.ledger_accounts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.exchange_rates FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.ledger_accounts_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_ledger_account_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_ledger_account_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_exchange_rate_update() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_exchange_rate_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_exchange_rate_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.ensure_financial_asset_ledger_account(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.sync_financial_account_ledger_account() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_exchange_rate(uuid, date, char, char, numeric, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_exchange_rate_list(uuid, char, char, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_exchange_rate_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.convert_amount_with_exchange_rate(numeric, char, char, char, char, numeric) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_exchange_rate(uuid, date, char, char, numeric, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_exchange_rate_list(uuid, char, char, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_exchange_rate_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_exchange_rate(uuid, date, char, char, numeric, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_exchange_rate_list(uuid, char, char, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_exchange_rate_detail(uuid, uuid) TO service_role;

COMMIT;
