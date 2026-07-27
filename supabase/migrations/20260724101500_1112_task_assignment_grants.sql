BEGIN;

REVOKE ALL ON app.task_assignments FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.prevent_task_assignment_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.task_assignments_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assign_project_task(uuid, uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.remove_project_task_assignment(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_task_assignment_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_task_assignment_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_assign_project_task(uuid, uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_remove_project_task_assignment(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_task_assignment_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_task_assignment_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_assign_project_task(uuid, uuid, uuid, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_remove_project_task_assignment(uuid, uuid, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_task_assignment_list(uuid, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_task_assignment_detail(uuid, uuid) TO service_role;

COMMIT;
