BEGIN;

REVOKE ALL ON app.document_replacements FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_replacements_guard_history() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.document_client_access_privacy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_client_access_privacy_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_business_context(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_is_superseded(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_is_client_lifecycle_private(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_replacement_would_cycle(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_is_finalized_from_clean_scan(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_restore_document_metadata(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_declare_document_replacement(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_document_lifecycle_history(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_restore_document_metadata(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_declare_document_replacement(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_document_lifecycle_history(uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_restore_document_metadata(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_declare_document_replacement(uuid, uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_document_lifecycle_history(uuid, uuid) TO service_role;

COMMIT;
