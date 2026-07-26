BEGIN;

REVOKE ALL ON app.project_phases FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.assert_project_phase_dates(app.projects, date, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_project_phase_editable(app.projects) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_project_phase(uuid, uuid, text, text, date, date, boolean, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.update_project_phase(uuid, uuid, integer, text, text, date, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.reorder_project_phases(uuid, uuid, uuid[], integer[], text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.archive_project_phase(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_phase_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_phase_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_phases_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_phase_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_project_phases(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_project_phase(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.server_create_project_phase(uuid, uuid, text, text, date, date, boolean, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_update_project_phase(uuid, uuid, integer, text, text, date, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_reorder_project_phases(uuid, uuid, uuid[], integer[], text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_archive_project_phase(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_phase_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_phase_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.current_client_project_phases(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_project_phase(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.server_create_project_phase(uuid, uuid, text, text, date, date, boolean, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_update_project_phase(uuid, uuid, integer, text, text, date, date, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_reorder_project_phases(uuid, uuid, uuid[], integer[], text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_archive_project_phase(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_phase_list(uuid, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_phase_detail(uuid, uuid) TO service_role;

COMMIT;
