BEGIN;

REVOKE ALL ON app.project_completion_overrides FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.normalize_project_completion_override_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_completion_override_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_completion_override_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.project_completion_overrides_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.derive_project_completion_override_state(timestamptz, uuid, timestamptz, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_project_official_completion(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_approve_project_completion_override(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_revoke_project_completion_override(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_official_project_completion(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_completion_override_list(uuid, uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_project_completion_override_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_project_completion_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_approve_project_completion_override(uuid, uuid, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_revoke_project_completion_override(uuid, uuid, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_official_project_completion(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_completion_override_list(uuid, uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_project_completion_override_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.current_client_project_completion(uuid) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.server_owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_approve_project_completion_override(uuid, uuid, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_revoke_project_completion_override(uuid, uuid, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_official_project_completion(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_completion_override_list(uuid, uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_project_completion_override_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.current_client_project_completion(uuid) TO authenticated;

COMMIT;
