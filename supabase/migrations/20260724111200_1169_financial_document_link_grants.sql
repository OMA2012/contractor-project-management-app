BEGIN;

REVOKE ALL ON FUNCTION app.document_finance_target_scope(uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_finance_type_allowed(varchar(50), boolean, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_target_exists(uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_reserve_transfer_evidence_upload(uuid, text, text, text, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_transfer_evidence_upload_storage_context(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.complete_document_upload_trusted(app.document_uploads, text, bigint, bytea, uuid, uuid, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_complete_transfer_evidence_upload(uuid, uuid, text, bigint, bytea, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.current_client_reserve_transfer_evidence_upload(uuid, text, text, text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.current_client_transfer_evidence_upload_storage_context(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.current_client_complete_transfer_evidence_upload(uuid, uuid, text, bigint, bytea, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.current_client_reserve_transfer_evidence_upload(uuid, text, text, text, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.current_client_transfer_evidence_upload_storage_context(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.current_client_complete_transfer_evidence_upload(uuid, uuid, text, bigint, bytea, text) TO service_role;

COMMIT;
