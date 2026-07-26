BEGIN;

REVOKE ALL ON app.project_staff_assignments FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.assert_project_staff_assignment_role(varchar) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_project_staff_assignment_target(uuid, uuid, varchar) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.remove_project_staff_assignment(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_staff_assignment_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_staff_assignment_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_eligible_project_staff_list(uuid, varchar, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.has_active_project_assignment(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.has_active_project_assignment_role(uuid, uuid, varchar) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_remove_project_staff_assignment(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_staff_assignment_list(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_staff_assignment_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_eligible_project_staff_list(uuid, varchar, integer, integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_remove_project_staff_assignment(uuid, uuid, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_staff_assignment_list(uuid, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_staff_assignment_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_eligible_project_staff_list(uuid, varchar, integer, integer) TO service_role;

COMMIT;
