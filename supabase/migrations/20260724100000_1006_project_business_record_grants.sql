BEGIN;

REVOKE ALL ON app.project_number_counters FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.projects FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.generate_project_number() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.normalize_project_optional_text(text, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.require_active_client_record(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_project_updateable(app.projects) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.is_allowed_project_transition(app.project_record_status, app.project_record_status) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_project_record(uuid, uuid, text, char, text, text, date, date, numeric, char, numeric, char, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.update_project_record(uuid, uuid, integer, text, char, text, text, date, date, numeric, char, numeric, char, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.change_project_client(uuid, uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.change_project_status(uuid, uuid, integer, app.project_record_status, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.complete_project_record(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.cancel_project_record(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.archive_project_record(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_record_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_record_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_records_for_authenticated_user(integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_record_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_project_records(integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_project_record(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.current_client_project_records(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_project_record(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.server_create_project_record(uuid, uuid, text, char, text, text, date, date, numeric, char, numeric, char, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_update_project_record(uuid, uuid, integer, text, char, text, text, date, date, numeric, char, numeric, char, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_change_project_client(uuid, uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_change_project_status(uuid, uuid, integer, app.project_record_status, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_complete_project_record(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_cancel_project_record(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_archive_project_record(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_record_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_record_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_create_project_record(uuid, uuid, text, char, text, text, date, date, numeric, char, numeric, char, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_update_project_record(uuid, uuid, integer, text, char, text, text, date, date, numeric, char, numeric, char, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_change_project_client(uuid, uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_change_project_status(uuid, uuid, integer, app.project_record_status, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_complete_project_record(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_cancel_project_record(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_archive_project_record(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_record_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_record_list(uuid, integer, integer) TO service_role;

COMMIT;
