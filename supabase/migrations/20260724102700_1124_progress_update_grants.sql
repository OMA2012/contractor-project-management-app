BEGIN;

REVOKE ALL ON app.progress_updates FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.assert_progress_update_project_writable(app.projects) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_progress_update_milestone(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_project_client_readable_for_progress(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_progress_update(uuid, uuid, uuid, text, text, numeric, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_update_progress_update_draft(uuid, uuid, integer, uuid, text, text, numeric, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_submit_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_approve_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_reject_progress_update(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_set_progress_update_client_visibility(uuid, uuid, integer, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_publish_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_archive_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_progress_update_list(uuid, uuid, app.progress_update_status, boolean, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_progress_update_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_progress_update_list_for_authenticated_user(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_progress_update_detail_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_progress_update(uuid, uuid, uuid, text, text, numeric, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_update_progress_update_draft(uuid, uuid, integer, uuid, text, text, numeric, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_submit_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_approve_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_reject_progress_update(uuid, uuid, integer, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_set_progress_update_client_visibility(uuid, uuid, integer, boolean, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_publish_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_archive_progress_update(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_progress_update_list(uuid, uuid, app.progress_update_status, boolean, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_progress_update_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.current_client_progress_update_list(uuid, integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_progress_update_detail(uuid) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.server_owner_create_progress_update(uuid, uuid, uuid, text, text, numeric, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_update_progress_update_draft(uuid, uuid, integer, uuid, text, text, numeric, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_submit_progress_update(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_approve_progress_update(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_reject_progress_update(uuid, uuid, integer, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_set_progress_update_client_visibility(uuid, uuid, integer, boolean, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_publish_progress_update(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_archive_progress_update(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_progress_update_list(uuid, uuid, app.progress_update_status, boolean, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_progress_update_detail(uuid, uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.current_client_progress_update_list(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_progress_update_detail(uuid) TO authenticated;

COMMIT;
