BEGIN;

REVOKE ALL ON app.project_task_number_counters FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.tasks FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.generate_project_task_number(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_task_number_counter_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_task_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.tasks_validate_relationships() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.tasks_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_project_task_editable_project(app.projects) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.normalize_project_task_weight(boolean, numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_project_task(uuid, uuid, text, uuid, uuid, text, text, numeric, boolean, date, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.update_project_task(uuid, uuid, integer, text, uuid, uuid, text, text, numeric, boolean, date, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.archive_project_task(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_task_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_task_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_tasks_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_task_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_project_tasks(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_project_task(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.server_create_project_task(uuid, uuid, text, uuid, uuid, text, text, numeric, boolean, date, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_update_project_task(uuid, uuid, integer, text, uuid, uuid, text, text, numeric, boolean, date, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_archive_project_task(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_task_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_task_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.current_client_project_tasks(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_project_task(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.server_create_project_task(uuid, uuid, text, uuid, uuid, text, text, numeric, boolean, date, date, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_update_project_task(uuid, uuid, integer, text, uuid, uuid, text, text, numeric, boolean, date, date, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_archive_project_task(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_task_list(uuid, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_task_detail(uuid, uuid) TO service_role;

COMMIT;
