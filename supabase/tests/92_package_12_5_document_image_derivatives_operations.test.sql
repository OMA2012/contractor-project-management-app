BEGIN;
SELECT plan(30);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000009201','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.92@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000009202','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.92@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000009203','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other.92@example.test','',now(),'{}','{}',now(),now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000009201','owner.92@example.test','Owner Ninety Two',decode('9292929292929292929292929292929292929292929292929292929292929292','hex'),'req-92','corr-92');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009201',true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Image Contractor','Image Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000009202','00000000-0000-0000-0000-000000009202','client.92@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('10000000-0000-0000-0000-000000009203','00000000-0000-0000-0000-000000009203','other.92@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000009202','Client 92',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('10000000-0000-0000-0000-000000009203','Other 92',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'));
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000009202','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'),true),
  ('10000000-0000-0000-0000-000000009203','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'),true);
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000009201','Image Client A',NULL,'image.a@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000009201','Image Client B',NULL,'image.b@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000009201',(SELECT id FROM app.clients WHERE display_name='Image Client A'),'10000000-0000-0000-0000-000000009202',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000009201',(SELECT id FROM app.clients WHERE display_name='Image Client B'),'10000000-0000-0000-0000-000000009203',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000009201',(SELECT id FROM app.clients WHERE display_name='Image Client A'),'Image Project A','USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000009201',(SELECT id FROM app.clients WHERE display_name='Image Client B'),'Image Project B','USD');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000009201',(SELECT id FROM app.projects WHERE name='Image Project A'),'Visible task',NULL,NULL,'Summary','Client summary',10,true,NULL,NULL,true);
SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000009201',(SELECT id FROM app.projects WHERE name='Image Project A'),NULL,'Photo update','Visible summary',1,false);

SELECT set_config('app.document_metadata_context','owner_metadata_mutation',true);
INSERT INTO app.documents (id, storage_bucket, storage_object_key, original_file_name, mime_type, file_size_bytes, sha256_hash, document_type_code, client_visible, uploaded_by)
VALUES
  ('20000000-0000-4000-8000-000000009201','documents-private','objects/20000000-0000-4000-8000-000000009201/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','progress.jpg','image/jpeg',100,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009202','documents-private','objects/20000000-0000-4000-8000-000000009202/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','task.png','image/png',100,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009203','documents-private','objects/20000000-0000-4000-8000-000000009203/ccccccccccccccccccccccccccccccccccccccccccc','general.jpg','image/jpeg',100,decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009204','documents-private','objects/20000000-0000-4000-8000-000000009204/ddddddddddddddddddddddddddddddddddddddddddd','task.pdf','application/pdf',100,decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009205','documents-private','objects/20000000-0000-4000-8000-000000009205/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','large.jpg','image/jpeg',5242881,decode('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'));
SELECT set_config('app.document_metadata_context','',true);
INSERT INTO app.document_links (document_id, project_id, task_id, progress_update_id, created_by)
VALUES
  ('20000000-0000-4000-8000-000000009201',(SELECT id FROM app.projects WHERE name='Image Project A'),NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009202',NULL,(SELECT id FROM app.tasks WHERE title='Visible task'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009203',(SELECT id FROM app.projects WHERE name='Image Project A'),NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009204',NULL,(SELECT id FROM app.tasks WHERE title='Visible task'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201')),
  ('20000000-0000-4000-8000-000000009205',(SELECT id FROM app.projects WHERE name='Image Project A'),NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000009201'));

INSERT INTO app.document_uploads (id, reserved_document_id, storage_object_key, original_file_name, declared_mime_type, verified_mime_type, verified_file_size_bytes, verified_sha256_hash, document_type_code, requested_client_visible, project_id, task_id, authorized_by, expires_at, status, final_storage_object_key, finalized_document_id, awaiting_scan_at, scan_started_at, scan_completed_at, finalizing_at, finalized_at)
SELECT gen_random_uuid(), d.id, 'temporary/' || gen_random_uuid()::text || '/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', d.original_file_name, d.mime_type, d.mime_type, d.file_size_bytes, d.sha256_hash, d.document_type_code, d.client_visible, dl.project_id, dl.task_id, d.uploaded_by, now() + interval '5 minutes', 'FINALIZED', d.storage_object_key, d.id, now(), now(), now(), now(), now()
FROM app.documents d JOIN app.document_links dl ON dl.document_id=d.id
WHERE d.id IN ('20000000-0000-4000-8000-000000009201','20000000-0000-4000-8000-000000009202','20000000-0000-4000-8000-000000009203','20000000-0000-4000-8000-000000009204','20000000-0000-4000-8000-000000009205');
INSERT INTO app.document_scans (document_upload_id, attempt_number, status, scanner_engine, completed_at, scanned_storage_bucket, scanned_storage_object_key, scanned_sha256_hash, scanned_file_size_bytes)
SELECT id, 1, 'CLEAN', 'test', now(), storage_bucket, storage_object_key, verified_sha256_hash, verified_file_size_bytes FROM app.document_uploads;

SELECT lives_ok($$ SELECT * FROM public.server_owner_prepare_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009201','req') $$, 'eligible progress JPEG prepares');
SELECT lives_ok($$ SELECT * FROM public.server_owner_prepare_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009202','req') $$, 'eligible task PNG prepares');
SELECT throws_ok($$ SELECT * FROM public.server_owner_prepare_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009203','req') $$, '23514', 'not_photograph_type', 'GENERAL image not processed');
SELECT throws_ok($$ SELECT * FROM public.server_owner_prepare_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009204','req') $$, '23514', 'unsupported_mime', 'TASK_ATTACHMENT PDF excluded');
SELECT throws_ok($$ SELECT * FROM public.server_owner_prepare_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009205','req') $$, '23514', 'source_dimensions_exceeded', '5 MiB photograph limit enforced');
SELECT ok((SELECT thumbnail_storage_object_key ~ '^derivatives/20000000-0000-4000-8000-000000009201/[0-9a-f]{43}/thumbnail[.]webp$' FROM app.document_image_derivatives WHERE document_id='20000000-0000-4000-8000-000000009201'), 'thumbnail key is opaque and scoped');
SELECT ok((SELECT preview_storage_object_key ~ '^derivatives/20000000-0000-4000-8000-000000009201/[0-9a-f]{43}/preview[.]webp$' FROM app.document_image_derivatives WHERE document_id='20000000-0000-4000-8000-000000009201'), 'preview key is opaque and scoped');
SELECT is((SELECT count(*)::integer FROM app.document_image_derivatives WHERE document_id='20000000-0000-4000-8000-000000009201'),1,'one derivative row per document');
SELECT lives_ok($$ SELECT * FROM public.server_owner_prepare_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009201','req') $$, 'duplicate prepare resumes same row');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='photograph_processing_started' AND entity_id='20000000-0000-4000-8000-000000009201'),1,'started logged once');
SELECT throws_ok($$ SELECT * FROM public.server_owner_complete_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009201',decode('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','hex'),4,3,50,decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),3,2,60,decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),4,3,'test','req') $$, '23514', 'Photograph source hash mismatch.', 'source hash reverified before completion');
SELECT lives_ok($$ SELECT * FROM public.server_owner_complete_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009201',decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),4,3,50,decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),3,2,60,decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),4,3,'test','req') $$, 'completion marks READY after derivative verification facts');
SELECT results_eq($$ SELECT processing_status::text, source_width, source_height, thumbnail_width, preview_width, failure_code FROM app.document_image_derivatives WHERE document_id='20000000-0000-4000-8000-000000009201' $$, $$ VALUES ('READY'::text,4,3,3,4,NULL::varchar) $$, 'READY stores dimensions and clears failure');
SELECT lives_ok($$ SELECT * FROM public.server_owner_complete_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009201',decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),4,3,50,decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),3,2,60,decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),4,3,'test','req') $$, 'duplicate completion idempotent');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='photograph_processing_completed' AND entity_id='20000000-0000-4000-8000-000000009201'),1,'completed logged once');
SELECT lives_ok($$ SELECT * FROM public.server_owner_fail_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009202','animated_image_unsupported','req') $$, 'controlled failure recorded');
SELECT results_eq($$ SELECT processing_status::text, failure_code, thumbnail_sha256_hash IS NULL, preview_sha256_hash IS NULL FROM app.document_image_derivatives WHERE document_id='20000000-0000-4000-8000-000000009202' $$, $$ VALUES ('FAILED'::text,'animated_image_unsupported'::varchar,true,true) $$, 'FAILED has no authoritative derivative hashes');
SELECT lives_ok($$ SELECT * FROM public.server_owner_prepare_document_image_processing('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009202','req') $$, 'retry from FAILED enters processing');
SELECT lives_ok($$ SELECT * FROM public.server_authorize_document_image_access('00000000-0000-0000-0000-000000009202','20000000-0000-4000-8000-000000009201','preview','req') $$, 'Client visible own-project preview allowed');
SELECT results_eq($$ SELECT storage_object_key, mime_type, file_size_bytes FROM public.server_authorize_document_image_access('00000000-0000-0000-0000-000000009202','20000000-0000-4000-8000-000000009201','download','req') $$, $$ SELECT preview_storage_object_key, 'image/webp'::text, preview_file_size_bytes FROM app.document_image_derivatives WHERE document_id='20000000-0000-4000-8000-000000009201' $$, 'Client photograph download returns sanitized preview derivative');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_image_access('00000000-0000-0000-0000-000000009202','20000000-0000-4000-8000-000000009201','original','req') $$, '42501', 'Document access denied.', 'Client photograph original access denied');
SELECT results_eq($$ SELECT storage_object_key FROM public.server_authorize_document_image_access('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009201','original','req') $$, $$ VALUES ('objects/20000000-0000-4000-8000-000000009201/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'::text) $$, 'Owner original remains available');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_image_access('00000000-0000-0000-0000-000000009203','20000000-0000-4000-8000-000000009201','thumbnail','req') $$, '42501', 'Document access denied.', 'cross-Client thumbnail denied');
SELECT * FROM public.server_owner_archive_document_metadata('00000000-0000-0000-0000-000000009201','20000000-0000-4000-8000-000000009201');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_image_access('00000000-0000-0000-0000-000000009202','20000000-0000-4000-8000-000000009201','thumbnail','req') $$, '42501', 'Document access denied.', 'archived Client thumbnail denied');
SELECT ok((SELECT sha256_hash = decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex') AND file_size_bytes=100 FROM app.documents WHERE id='20000000-0000-4000-8000-000000009201'), 'original document hash and size unchanged');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action LIKE 'photograph_%' AND metadata::text ILIKE '%derivatives/%'), 'photograph logs omit derivative paths');
SELECT throws_ok($$ INSERT INTO app.document_image_derivatives(document_id, processing_status, source_width, source_height) VALUES ('20000000-0000-4000-8000-000000009203','READY',7000,1) $$, '23514', NULL, '6000 source dimension limit enforced');
SELECT throws_ok($$ INSERT INTO app.document_image_derivatives(document_id, processing_status, source_width, source_height) VALUES ('20000000-0000-4000-8000-000000009204','READY',4000,4000) $$, '23514', NULL, '12MP decoded-pixel limit enforced');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%document_image%', 'public.current_account unchanged');
SELECT ok((SELECT pg_get_functiondef('app.authorize_document_image_access(uuid,uuid,text,text)'::regprocedure)) ILIKE '%project_expense_id IS NULL%', 'Package 12.4 finance protections preserved');

SELECT * FROM finish();
ROLLBACK;
