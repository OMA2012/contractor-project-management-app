BEGIN;

REVOKE ALL ON app.document_scans FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_generate_final_object_key(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_start_document_scan(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_record_document_scan_result(uuid, uuid, app.document_scan_status, bytea, bigint, text, text, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_prepare_clean_document_finalization(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_finalize_clean_document_upload(uuid, uuid, bytea, bigint, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_scans_guard_history() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_start_document_scan(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_record_document_scan_result(uuid, uuid, app.document_scan_status, bytea, bigint, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_prepare_clean_document_finalization(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_finalize_clean_document_upload(uuid, uuid, bytea, bigint, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_start_document_scan(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_record_document_scan_result(uuid, uuid, app.document_scan_status, bytea, bigint, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_prepare_clean_document_finalization(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_finalize_clean_document_upload(uuid, uuid, bytea, bigint, text) TO service_role;

COMMIT;
