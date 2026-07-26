BEGIN;

REVOKE ALL ON app.project_milestones FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.assert_project_milestone_due_date(app.projects, uuid, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_project_milestone_editable_project(app.projects) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_project_milestone(uuid, uuid, text, uuid, text, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.update_project_milestone(uuid, uuid, integer, text, uuid, text, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.complete_project_milestone(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.archive_project_milestone(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_milestone_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_milestone_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_milestones_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_milestone_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_project_milestones(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_project_milestone(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.server_create_project_milestone(uuid, uuid, text, uuid, text, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_update_project_milestone(uuid, uuid, integer, text, uuid, text, date, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_complete_project_milestone(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_archive_project_milestone(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_milestone_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_milestone_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.current_client_project_milestones(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_project_milestone(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.server_create_project_milestone(uuid, uuid, text, uuid, text, date, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_update_project_milestone(uuid, uuid, integer, text, uuid, text, date, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_complete_project_milestone(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_archive_project_milestone(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_milestone_list(uuid, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_milestone_detail(uuid, uuid) TO service_role;

COMMIT;
