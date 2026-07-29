BEGIN;
SELECT plan(22);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.50@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.50@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.50@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000005001', 'owner.50@example.test', 'Owner Fifty', decode('5050505050505050505050505050505050505050505050505050505050505050', 'hex'), 'req-50', 'corr-50');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005001', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Document Operations Contractor', 'Document Operations Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-000000005002', 'client.50@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001')),
  ('10000000-0000-0000-0000-000000005003', '00000000-0000-0000-0000-000000005003', 'other.50@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000005002', 'Client Fifty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001')),
  ('10000000-0000-0000-0000-000000005003', 'Other Fifty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000005002', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'), true),
  ('10000000-0000-0000-0000-000000005003', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001'), true);

SELECT setval('app.document_number_seq', 1, false);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000005001', 'Document Client A', NULL, 'document.client.a@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000005001', 'Document Client B', NULL, 'document.client.b@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000005001', (SELECT id FROM app.clients WHERE display_name = 'Document Client A'), '10000000-0000-0000-0000-000000005002', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000005001', (SELECT id FROM app.clients WHERE display_name = 'Document Client B'), '10000000-0000-0000-0000-000000005003', 1);

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_document_metadata('00000000-0000-0000-0000-000000005001', 'metadata-only', 'documents/a.pdf', 'a.pdf', 'application/pdf', 100, decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'), 'GENERAL', true, 'visible') $$, 'owner creates first document metadata');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_document_metadata('00000000-0000-0000-0000-000000005001', 'metadata-only', 'documents/b.pdf', 'b.pdf', 'application/pdf', 200, decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'hex'), 'CONTRACT', false, NULL) $$, 'owner creates second document metadata');
SELECT results_eq($$ SELECT document_number FROM app.documents ORDER BY document_number $$, $$ VALUES ('DOC-000001'::varchar), ('DOC-000002'::varchar) $$, 'global sequence emits six digit document numbers');
SELECT throws_ok($$ UPDATE app.documents SET document_number = 'DOC-999999' WHERE document_number = 'DOC-000001' $$, '23514', 'Document identity fields are immutable.', 'document number immutable through direct update');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_document_metadata('00000000-0000-0000-0000-000000005001', 'metadata-only', 'documents/c.pdf', 'c.pdf', ' ', 100, decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'hex'), 'GENERAL', false, NULL) $$, '23514', 'new row for relation "documents" violates check constraint "documents_mime_type_ck"', 'blank mime type rejected');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_document_metadata('00000000-0000-0000-0000-000000005001', 'metadata-only', 'documents/c.pdf', 'c.pdf', 'text/plain', 0, decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'hex'), 'GENERAL', false, NULL) $$, '23514', 'new row for relation "documents" violates check constraint "documents_file_size_bytes_ck"', 'nonpositive file size rejected');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_document_metadata('00000000-0000-0000-0000-000000005001', 'metadata-only', 'documents/c.pdf', 'c.pdf', 'text/plain', 1, decode('cccc', 'hex'), 'GENERAL', false, NULL) $$, '23514', 'new row for relation "documents" violates check constraint "documents_sha256_hash_ck"', 'non-32-byte hash rejected');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_document_metadata('00000000-0000-0000-0000-000000005001', 'metadata-only', 'documents/c.pdf', 'c.pdf', 'text/plain', 1, decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'hex'), 'general', false, NULL) $$, '23514', 'Document type code must be uppercase and stable.', 'lowercase document type code rejected');

SELECT lives_ok($$ SELECT * FROM public.server_owner_link_document('00000000-0000-0000-0000-000000005001', (SELECT id FROM app.documents WHERE document_number = 'DOC-000001'), (SELECT id FROM app.clients WHERE display_name = 'Document Client A'), NULL, NULL, NULL, NULL, NULL, NULL, NULL) $$, 'owner links document to existing client');
SELECT throws_ok($$ SELECT * FROM public.server_owner_link_document('00000000-0000-0000-0000-000000005001', (SELECT id FROM app.documents WHERE document_number = 'DOC-000001'), NULL, NULL, NULL, NULL, gen_random_uuid(), NULL, NULL, NULL) $$, '23514', 'Finance document link targets are not enabled.', 'finance target link rejected by function');
SELECT throws_ok($$ INSERT INTO app.document_links (document_id, client_payment_id, created_by) VALUES ((SELECT id FROM app.documents WHERE document_number = 'DOC-000001'), gen_random_uuid(), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001')) $$, '23514', 'new row for relation "document_links" violates check constraint "document_links_finance_targets_disabled_ck"', 'finance target link rejected by constraint');
SELECT throws_ok($$ INSERT INTO app.document_links (document_id, client_id, project_id, created_by) VALUES ((SELECT id FROM app.documents WHERE document_number = 'DOC-000001'), (SELECT id FROM app.clients WHERE display_name = 'Document Client A'), gen_random_uuid(), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005001')) $$, '23514', 'new row for relation "document_links" violates check constraint "document_links_exactly_one_target_ck"', 'multi-target document link rejected');
SELECT is((SELECT count(*)::integer FROM app.document_links), 1, 'only valid document link persisted');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005002', true);
SELECT results_eq($$ SELECT document_number, original_file_name FROM public.current_client_document_list(50, 0) $$, $$ VALUES ('DOC-000001'::text, 'a.pdf'::text) $$, 'client sees own client-visible metadata');
SELECT ok(pg_get_function_result('public.current_client_document_list(integer, integer)'::regprocedure) NOT LIKE '%storage_object_key%', 'client list does not expose storage object key');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005003', true);
SELECT is_empty($$ SELECT * FROM public.current_client_document_list(50, 0) $$, 'other client sees no linked metadata');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005001', true);
SELECT is_empty($$ SELECT * FROM public.current_client_document_list(50, 0) $$, 'owner is not activated as client reader');
SELECT lives_ok($$ SELECT * FROM public.server_owner_archive_document_metadata('00000000-0000-0000-0000-000000005001', (SELECT id FROM app.documents WHERE document_number = 'DOC-000001')) $$, 'owner archives document metadata');
SELECT ok((SELECT status = 'ARCHIVED' AND archived_at IS NOT NULL AND archived_by IS NOT NULL FROM app.documents WHERE document_number = 'DOC-000001'), 'archive fields paired after archive');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005002', true);
SELECT is_empty($$ SELECT * FROM public.current_client_document_list(50, 0) $$, 'archived document disappears from client metadata list');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('payment_requests','project_expenses','currency_exchanges','document_scans','document_thumbnails')), 'finance scanner thumbnail tables absent except Package 14.1 client payments');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name ~ '(upload|download|signed|scanner|thumbnail|finance)' $$, 'upload download signed scanner thumbnail finance routines absent');

SELECT * FROM finish();
ROLLBACK;
