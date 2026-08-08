BEGIN;
SELECT plan(18);

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.document_types'::regclass), 'document types RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.document_types'::regclass), 'document types RLS forced');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.documents'::regclass), 'documents RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.documents'::regclass), 'documents RLS forced');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.document_links'::regclass), 'document links RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.document_links'::regclass), 'document links RLS forced');
SELECT throws_ok($$ INSERT INTO app.documents DEFAULT VALUES $$, '23514', 'Documents require trusted metadata functions.', 'direct document insert denied');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'documents_no_delete'), 'document delete prevention trigger exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'document_links_no_delete'), 'document link delete prevention trigger exists');
SELECT has_function('public', 'current_client_document_list', ARRAY['integer','integer'], 'client document list rpc exists');
SELECT has_function('public', 'server_owner_create_document_metadata', ARRAY['uuid','text','text','text','text','bigint','bytea','character varying','boolean','text'], 'owner create document metadata rpc exists');
SELECT has_function('public', 'server_owner_archive_document_metadata', ARRAY['uuid','uuid'], 'owner archive document metadata rpc exists');
SELECT has_function('public', 'server_owner_link_document', ARRAY['uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid'], 'owner link document rpc exists');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_document_list(integer, integer)', 'EXECUTE'), 'authenticated can execute client list');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_create_document_metadata(uuid, text, text, text, text, bigint, bytea, character varying, boolean, text)', 'EXECUTE'), 'authenticated cannot execute owner create');
SELECT ok(NOT has_function_privilege('service_role', 'public.server_owner_create_document_metadata(uuid, text, text, text, text, bigint, bytea, character varying, boolean, text)', 'EXECUTE'), 'service role cannot execute legacy owner create after secure upload foundation');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_project_manager_document_list','current_accountant_document_list','current_site_supervisor_document_list') $$, 'reserved role document gateways absent');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('document_scans','document_thumbnails')), 'scanner thumbnail objects absent');

SELECT * FROM finish();
ROLLBACK;
