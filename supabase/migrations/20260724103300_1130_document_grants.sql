BEGIN;

REVOKE ALL ON app.document_types FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.documents FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.document_links FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.document_safe_row(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_document_metadata(uuid, text, text, text, text, bigint, bytea, varchar(50), boolean, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_archive_document_metadata(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_link_document(uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_document_list_for_authenticated_user(integer, integer) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_document_list(integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.server_owner_create_document_metadata(uuid, text, text, text, text, bigint, bytea, varchar(50), boolean, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_archive_document_metadata(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_link_document(uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.current_client_document_list(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.server_owner_create_document_metadata(uuid, text, text, text, text, bigint, bytea, varchar(50), boolean, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_archive_document_metadata(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_link_document(uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) TO service_role;

COMMIT;
