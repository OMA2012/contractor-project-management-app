BEGIN;

REVOKE ALL ON app.task_updates FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.assert_project_task_workflow_project(app.projects, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.insert_project_task_update(uuid, uuid, app.project_task_status, app.project_task_status, numeric, numeric, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.update_project_task_progress(uuid, uuid, integer, numeric, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.change_project_task_status(uuid, uuid, integer, app.project_task_status, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.complete_project_task(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.reopen_project_task(uuid, uuid, integer, numeric, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.cancel_project_task(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_task_update_list(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_task_update_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_update_project_task_progress(uuid, uuid, integer, numeric, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_change_project_task_status(uuid, uuid, integer, app.project_task_status, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_complete_project_task(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_reopen_project_task(uuid, uuid, integer, numeric, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_cancel_project_task(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_task_update_list(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_task_update_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_update_project_task_progress(uuid, uuid, integer, numeric, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_change_project_task_status(uuid, uuid, integer, app.project_task_status, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_complete_project_task(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_reopen_project_task(uuid, uuid, integer, numeric, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_cancel_project_task(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_task_update_list(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_task_update_detail(uuid, uuid) TO service_role;

COMMIT;
