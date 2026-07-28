BEGIN;

REVOKE ALL ON app.financial_accounts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE app.financial_account_number_seq FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.normalize_financial_account_optional_text(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_financial_account(uuid, text, app.financial_account_type, char, text, text, bytea, boolean, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_update_financial_account(uuid, uuid, integer, text, app.financial_account_type, char, text, text, bytea, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_activate_financial_account(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_deactivate_financial_account(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_archive_financial_account(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_financial_account_list(uuid, boolean, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_financial_account_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_financial_account(uuid, text, app.financial_account_type, char, text, text, bytea, boolean, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_financial_account(uuid, uuid, integer, text, app.financial_account_type, char, text, text, bytea, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_activate_financial_account(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_deactivate_financial_account(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_archive_financial_account(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_financial_account_list(uuid, boolean, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_financial_account_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_financial_account(uuid, text, app.financial_account_type, char, text, text, bytea, boolean, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_financial_account(uuid, uuid, integer, text, app.financial_account_type, char, text, text, bytea, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_activate_financial_account(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_deactivate_financial_account(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_archive_financial_account(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_financial_account_list(uuid, boolean, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_financial_account_detail(uuid, uuid) TO service_role;

COMMIT;
