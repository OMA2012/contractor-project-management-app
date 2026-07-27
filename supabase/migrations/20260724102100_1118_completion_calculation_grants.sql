BEGIN;

REVOKE ALL ON app.tasks FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.calculate_project_phase_completion(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.calculate_project_completion(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_phase_completion(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_completion(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_phase_completion_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_completion_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_project_phase_completion(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_project_completion(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.server_owner_project_phase_completion(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_completion(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.current_client_project_phase_completion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_project_completion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.server_owner_project_phase_completion(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_completion(uuid, uuid) TO service_role;

COMMIT;
