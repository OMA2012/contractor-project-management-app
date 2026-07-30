BEGIN;

REVOKE ALL ON app.expense_categories FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.project_expenses FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE app.project_expense_number_seq FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.normalize_project_expense_vendor_reference(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.project_expense_duplicate_fingerprint(uuid, char, date, numeric, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.ensure_project_expense_control_ledger_account(char) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_expense_category(uuid, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_expense_category(uuid, uuid, integer, text, text, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_create_project_expense(uuid, uuid, uuid, numeric, char, uuid, date, text, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_project_expense(uuid, uuid, integer, uuid, uuid, numeric, char, uuid, date, text, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_submit_project_expense(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_reject_project_expense(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_approve_project_expense(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_expense_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_expense_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_expense_totals(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_create_expense_category(uuid, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_expense_category(uuid, uuid, integer, text, text, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_create_project_expense(uuid, uuid, uuid, numeric, char, uuid, date, text, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_project_expense(uuid, uuid, integer, uuid, uuid, numeric, char, uuid, date, text, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_submit_project_expense(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_reject_project_expense(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_approve_project_expense(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_expense_list(uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_expense_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_expense_totals(uuid, uuid) TO service_role;

COMMIT;
