BEGIN;

REVOKE ALL ON app.financial_event_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.financial_transaction_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.financial_events FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.financial_transactions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.ledger_entries FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.account_opening_balances FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.normalize_financial_optional_text(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.ensure_opening_balance_control_ledger_account(char) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_opening_balance(uuid, uuid, numeric, date, char, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_update_opening_balance(uuid, uuid, integer, numeric, date, char, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_submit_opening_balance(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_reject_opening_balance(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_approve_opening_balance(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_opening_balance_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_opening_balance_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_financial_account_balance(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_financial_account_balances_by_currency(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_cash_totals_by_currency(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_bank_totals_by_currency(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_opening_balance(uuid, uuid, numeric, date, char, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_opening_balance(uuid, uuid, integer, numeric, date, char, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_submit_opening_balance(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_reject_opening_balance(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_approve_opening_balance(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_opening_balance_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_opening_balance_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_financial_account_balance(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_financial_account_balances_by_currency(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_cash_totals_by_currency(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_bank_totals_by_currency(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_opening_balance(uuid, uuid, numeric, date, char, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_opening_balance(uuid, uuid, integer, numeric, date, char, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_submit_opening_balance(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_reject_opening_balance(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_approve_opening_balance(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_opening_balance_list(uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_opening_balance_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_financial_account_balance(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_financial_account_balances_by_currency(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_cash_totals_by_currency(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_bank_totals_by_currency(uuid) TO service_role;

COMMIT;
