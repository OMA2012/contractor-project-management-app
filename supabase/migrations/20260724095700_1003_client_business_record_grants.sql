BEGIN;

REVOKE ALL ON app.clients FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE app.client_number_seq FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.normalize_optional_text(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.assert_portal_client_link_target(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_client_record(uuid, text, text, citext, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.update_client_record(uuid, uuid, integer, text, text, citext, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.link_client_portal_user(uuid, uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.unlink_client_portal_user(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.archive_client_record(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_client_record_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_client_record_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_record_for_authenticated_user() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_record() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.current_client_record() TO authenticated;

REVOKE ALL ON FUNCTION public.server_create_client_record(uuid, text, text, citext, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_update_client_record(uuid, uuid, integer, text, text, citext, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_link_client_portal_user(uuid, uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_unlink_client_portal_user(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_archive_client_record(uuid, uuid, integer, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_client_record_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_client_record_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_create_client_record(uuid, text, text, citext, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_update_client_record(uuid, uuid, integer, text, text, citext, text, text, text, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_link_client_portal_user(uuid, uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_unlink_client_portal_user(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_archive_client_record(uuid, uuid, integer, text, text, text, inet) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_client_record_detail(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_client_record_list(uuid, integer, integer) TO service_role;

COMMIT;
