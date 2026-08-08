BEGIN;

REVOKE ALL ON app.document_uploads FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_allowed_extension(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_filename_is_safe(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_validate_upload_request(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_target_exists(uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_complete_document_upload(uuid, uuid, text, bigint, bytea, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_document_upload_storage_context(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.authorize_document_access(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_invalidate_expired_document_upload(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_document_metadata(uuid, text, text, text, text, bigint, bytea, varchar(50), boolean, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_complete_document_upload(uuid, uuid, text, bigint, bytea, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_document_upload_storage_context(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_authorize_document_access(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_invalidate_expired_document_upload(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_complete_document_upload(uuid, uuid, text, bigint, bytea, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_document_upload_storage_context(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_authorize_document_access(uuid, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_invalidate_expired_document_upload(uuid, uuid, text) TO service_role;

COMMIT;
