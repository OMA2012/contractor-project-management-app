BEGIN;

REVOKE ALL ON app.document_image_derivatives FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_image_generate_derivative_token() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_image_is_eligible(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_image_client_parent_visible(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_prepare_document_image_processing(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_complete_document_image_processing(uuid, uuid, bytea, integer, integer, bigint, bytea, integer, integer, bigint, bytea, integer, integer, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_fail_document_image_processing(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.authorize_document_image_access(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_image_derivatives_touch_updated_at() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_prepare_document_image_processing(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_complete_document_image_processing(uuid, uuid, bytea, integer, integer, bigint, bytea, integer, integer, bigint, bytea, integer, integer, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_fail_document_image_processing(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_authorize_document_image_access(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_prepare_document_image_processing(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_complete_document_image_processing(uuid, uuid, bytea, integer, integer, bigint, bytea, integer, integer, bigint, bytea, integer, integer, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_fail_document_image_processing(uuid, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_authorize_document_image_access(uuid, uuid, text, text) TO service_role;

COMMIT;
