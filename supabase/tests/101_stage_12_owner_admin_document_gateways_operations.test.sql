BEGIN;
SELECT plan(39);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010101','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.101@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010102','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.101@example.test','',now(),'{}','{}',now(),now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010101','owner.101@example.test','Owner 101',decode('1011011011011011011011011011011011011011011011011011011011011011','hex'),'req-101','corr-101');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010101',true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Gateway Contractor','Gateway Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES ('10000000-0000-0000-0000-000000010102','00000000-0000-0000-0000-000000010102','client.101@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES ('10000000-0000-0000-0000-000000010102','Client 101',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'));
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES ('10000000-0000-0000-0000-000000010102','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'),true);
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010101','Gateway Client',NULL,'gateway.client@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000010101',(SELECT id FROM app.clients WHERE display_name='Gateway Client'),'10000000-0000-0000-0000-000000010102',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010101',(SELECT id FROM app.clients WHERE display_name='Gateway Client'),'Gateway Project','USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010101',(SELECT id FROM app.clients WHERE display_name='Gateway Client'),'Gateway Project Other','USD');

SELECT set_config('app.document_metadata_context','owner_metadata_mutation',true);
INSERT INTO app.documents (id, storage_bucket, storage_object_key, original_file_name, mime_type, file_size_bytes, sha256_hash, document_type_code, client_visible, uploaded_by)
VALUES
  ('21000000-0000-4000-8000-000000010101','documents-private','objects/21000000-0000-4000-8000-000000010101/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','active.pdf','application/pdf',101,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010102','documents-private','objects/21000000-0000-4000-8000-000000010102/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','private.pdf','application/pdf',102,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'GENERAL',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010103','documents-private','objects/21000000-0000-4000-8000-000000010103/ccccccccccccccccccccccccccccccccccccccccccc','archived.pdf','application/pdf',103,decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010104','documents-private','objects/21000000-0000-4000-8000-000000010104/ddddddddddddddddddddddddddddddddddddddddddd','replacement.pdf','application/pdf',104,decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','hex'),'GENERAL',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010105','documents-private','objects/21000000-0000-4000-8000-000000010105/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','other-project.pdf','application/pdf',105,decode('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010106','documents-private','objects/21000000-0000-4000-8000-000000010106/fffffffffffffffffffffffffffffffffffffffffff','photo.jpg','image/jpeg',106,decode('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010107','documents-private','objects/21000000-0000-4000-8000-000000010107/1111111111111111111111111111111111111111111','chain-a.pdf','application/pdf',107,decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010108','documents-private','objects/21000000-0000-4000-8000-000000010108/2222222222222222222222222222222222222222222','chain-b.pdf','application/pdf',108,decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010109','documents-private','objects/21000000-0000-4000-8000-000000010109/3333333333333333333333333333333333333333333','chain-c.pdf','application/pdf',109,decode('3333333333333333333333333333333333333333333333333333333333333333','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'));
SELECT set_config('app.document_metadata_context','',true);
INSERT INTO app.document_links (document_id, project_id, created_by)
VALUES
  ('21000000-0000-4000-8000-000000010101',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010102',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010103',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010104',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010105',(SELECT id FROM app.projects WHERE name='Gateway Project Other'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010106',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010107',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010108',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101')),
  ('21000000-0000-4000-8000-000000010109',(SELECT id FROM app.projects WHERE name='Gateway Project'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010101'));
INSERT INTO app.document_uploads (id, reserved_document_id, storage_object_key, original_file_name, declared_mime_type, verified_mime_type, verified_file_size_bytes, verified_sha256_hash, document_type_code, requested_client_visible, project_id, authorized_by, expires_at, status, final_storage_object_key, finalized_document_id, awaiting_scan_at, scan_started_at, scan_completed_at, finalizing_at, finalized_at)
SELECT gen_random_uuid(), d.id, 'temporary/' || gen_random_uuid()::text || '/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', d.original_file_name, d.mime_type, d.mime_type, d.file_size_bytes, d.sha256_hash, d.document_type_code, d.client_visible, dl.project_id, d.uploaded_by, now() + interval '5 minutes', 'FINALIZED', d.storage_object_key, d.id, now(), now(), now(), now(), now()
FROM app.documents d JOIN app.document_links dl ON dl.document_id = d.id
WHERE d.id::text LIKE '21000000-0000-4000-8000-00000001010%';
INSERT INTO app.document_scans (document_upload_id, attempt_number, status, scanner_engine, completed_at, scanned_storage_bucket, scanned_storage_object_key, scanned_sha256_hash, scanned_file_size_bytes)
SELECT id, 1, 'CLEAN', 'test', now(), storage_bucket, storage_object_key, verified_sha256_hash, verified_file_size_bytes
FROM app.document_uploads WHERE finalized_document_id::text LIKE '21000000-0000-4000-8000-00000001010%';
INSERT INTO app.document_image_derivatives (document_id, processing_status, source_sha256_hash, source_width, source_height, thumbnail_storage_object_key, thumbnail_width, thumbnail_height, thumbnail_file_size_bytes, thumbnail_sha256_hash, preview_storage_object_key, preview_width, preview_height, preview_file_size_bytes, preview_sha256_hash, processor_version, processing_completed_at)
VALUES ('21000000-0000-4000-8000-000000010106','READY',decode('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','hex'),4,3,'derivatives/21000000-0000-4000-8000-000000010106/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/thumbnail.webp',3,2,60,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'derivatives/21000000-0000-4000-8000-000000010106/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/preview.webp',4,3,70,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'test',now());

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010101',true);
SELECT is((SELECT count(*)::integer FROM public.owner_admin_document_list(NULL,NULL,NULL,NULL,NULL,10,0)),9,'Owner/Admin sees active and private documents');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_list(NULL,NULL,NULL,NULL,NULL,101,0) $$, '23514', 'Invalid pagination request.', 'pagination is bounded');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_document_list((SELECT id FROM app.projects WHERE name='Gateway Project'),NULL,NULL,NULL,NULL,10,0)),8,'project filter works');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_document_list(NULL,'PROGRESS_PHOTOGRAPH',NULL,NULL,NULL,10,0)),1,'document type filter works');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_document_list(NULL,NULL,false,NULL,NULL,10,0)),2,'client-visible filter works');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_document_list(NULL,NULL,NULL,NULL,'project',10,0)),9,'context type filter works');
SELECT results_eq($$ SELECT original_file_name, thumbnail_available, preview_available FROM public.owner_admin_document_detail('21000000-0000-4000-8000-000000010106') $$, $$ VALUES ('photo.jpg'::text,true,true) $$, 'detail exposes safe image availability');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_detail('21000000-0000-4000-8000-000000019999') $$, '23514', 'Document metadata is not available.', 'nonexistent detail fails safely');
SELECT ok((SELECT pg_get_function_result('public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%bucket%' AND (SELECT pg_get_function_result('public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%storage%' AND (SELECT pg_get_function_result('public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%sha%' AND (SELECT pg_get_function_result('public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%hash%' AND (SELECT pg_get_function_result('public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%signed%', 'list signature excludes technical fields');
SELECT ok((SELECT pg_get_function_result('public.owner_admin_document_detail(uuid)'::regprocedure)) NOT ILIKE '%bucket%' AND (SELECT pg_get_function_result('public.owner_admin_document_detail(uuid)'::regprocedure)) NOT ILIKE '%object%' AND (SELECT pg_get_function_result('public.owner_admin_document_detail(uuid)'::regprocedure)) NOT ILIKE '%temp%' AND (SELECT pg_get_function_result('public.owner_admin_document_detail(uuid)'::regprocedure)) NOT ILIKE '%scanner%' AND (SELECT pg_get_function_result('public.owner_admin_document_detail(uuid)'::regprocedure)) NOT ILIKE '%service%', 'detail signature excludes technical fields');

SELECT lives_ok($$ SELECT * FROM public.owner_admin_archive_document('21000000-0000-4000-8000-000000010103') $$, 'archive succeeds');
SELECT results_eq($$ SELECT status::text, client_visible, archived_at IS NOT NULL FROM app.documents WHERE id='21000000-0000-4000-8000-000000010103' $$, $$ VALUES ('ARCHIVED'::text,true,true) $$, 'archive retains document and marks archived');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='document_archived' AND entity_id='21000000-0000-4000-8000-000000010103'),1,'archive activity emitted exactly once by delegate');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010102',true);
SELECT is((SELECT count(*)::integer FROM public.current_client_document_list() WHERE id='21000000-0000-4000-8000-000000010103'),0,'archived document hidden from Client list');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010101',true);
SELECT lives_ok($$ SELECT * FROM public.owner_admin_restore_document('21000000-0000-4000-8000-000000010103','req-restore') $$, 'restore succeeds');
SELECT results_eq($$ SELECT status::text, client_visible, archived_at IS NULL FROM app.documents WHERE id='21000000-0000-4000-8000-000000010103' $$, $$ VALUES ('ACTIVE'::text,false,true) $$, 'restore makes document contractor-private');
SELECT is((SELECT privacy_reason::text FROM app.document_client_access_privacy WHERE document_id='21000000-0000-4000-8000-000000010103'),'RESTORED_PRIVATE','restore writes RESTORED_PRIVATE marker');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='document_restored' AND entity_id='21000000-0000-4000-8000-000000010103'),1,'restore activity emitted once by delegate');

SELECT lives_ok($$ SELECT * FROM public.owner_admin_replace_document('21000000-0000-4000-8000-000000010101','21000000-0000-4000-8000-000000010104','req-replace') $$, 'replacement succeeds');
SELECT results_eq($$ SELECT superseded_document_id, replacement_document_id FROM app.document_replacements WHERE superseded_document_id='21000000-0000-4000-8000-000000010101' $$, $$ VALUES ('21000000-0000-4000-8000-000000010101'::uuid,'21000000-0000-4000-8000-000000010104'::uuid) $$, 'replacement relationship persisted');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_replace_document('21000000-0000-4000-8000-000000010104','21000000-0000-4000-8000-000000010101','req-cycle') $$, '23514', 'Document replacement cycles are not allowed.', 'cycle denied');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_replace_document('21000000-0000-4000-8000-000000010102','21000000-0000-4000-8000-000000010105','req-mismatch') $$, '23514', 'Document replacement requires matching Project context.', 'same Client different Project denied');
SELECT lives_ok($$ SELECT * FROM public.owner_admin_replace_document('21000000-0000-4000-8000-000000010107','21000000-0000-4000-8000-000000010108','req-chain-a-b') $$, 'replacement chain A to B starts through public wrapper');
SELECT lives_ok($$ SELECT * FROM public.owner_admin_replace_document('21000000-0000-4000-8000-000000010108','21000000-0000-4000-8000-000000010109','req-chain-b-c') $$, 'replacement chain B to C succeeds through public wrapper');
SELECT results_eq($$ SELECT superseded_document_id, replacement_document_id FROM app.document_replacements WHERE superseded_document_id IN ('21000000-0000-4000-8000-000000010107','21000000-0000-4000-8000-000000010108') ORDER BY superseded_document_id $$, $$ VALUES ('21000000-0000-4000-8000-000000010107'::uuid,'21000000-0000-4000-8000-000000010108'::uuid), ('21000000-0000-4000-8000-000000010108'::uuid,'21000000-0000-4000-8000-000000010109'::uuid) $$, 'replacement chain direct relationships persisted');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_replace_document('21000000-0000-4000-8000-000000010109','21000000-0000-4000-8000-000000010107','req-chain-cycle') $$, '23514', 'Document replacement cycles are not allowed.', 'multi-node cycle A to B to C to A denied');
SELECT ok((SELECT count(*)::integer FROM app.documents WHERE id IN ('21000000-0000-4000-8000-000000010107','21000000-0000-4000-8000-000000010108','21000000-0000-4000-8000-000000010109')) = 3, 'replacement chain documents retained');
SELECT results_eq($$ SELECT superseded_by_document_id FROM public.owner_admin_document_detail('21000000-0000-4000-8000-000000010101') $$, $$ VALUES ('21000000-0000-4000-8000-000000010104'::uuid) $$, 'detail reports supersession indicator');
SELECT results_eq($$ SELECT replaces_document_id FROM public.owner_admin_document_detail('21000000-0000-4000-8000-000000010104') $$, $$ VALUES ('21000000-0000-4000-8000-000000010101'::uuid) $$, 'detail reports replaced predecessor');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010102',true);
SELECT is((SELECT count(*)::integer FROM public.current_client_document_list() WHERE id='21000000-0000-4000-8000-000000010101'),0,'old superseded document hidden from Client');
SELECT is((SELECT count(*)::integer FROM public.current_client_document_list() WHERE id='21000000-0000-4000-8000-000000010104'),0,'replacement visibility is not automatically transferred');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010101',true);
SELECT ok((SELECT count(*)::integer FROM app.documents WHERE id::text LIKE '21000000-0000-4000-8000-00000001010%') = 9, 'operations do not hard-delete documents');
SELECT ok((SELECT storage_object_key LIKE 'objects/%' AND sha256_hash IS NOT NULL FROM app.documents WHERE id='21000000-0000-4000-8000-000000010101'), 'old document technical metadata retained');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='document_replaced' AND entity_id='21000000-0000-4000-8000-000000010101'),1,'replacement activity emitted once by delegate');
SELECT lives_ok($$ SELECT * FROM public.owner_admin_archive_document('21000000-0000-4000-8000-000000010107') $$, 'superseded document can be archived before restore denial check');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_restore_document('21000000-0000-4000-8000-000000010107','req-superseded-restore') $$, '23514', 'Superseded documents cannot be restored as current documents.', 'superseded restore denied through public wrapper');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_document_list(NULL,NULL,NULL,'ARCHIVED',NULL,10,0)),1,'status filter reflects archived superseded document');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_document_list(NULL,NULL,NULL,'ACTIVE',NULL,10,0)),8,'active status filter works');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action IN ('document_archived','document_restored','document_replaced') AND metadata::text ILIKE '%objects/%'), 'lifecycle activity does not leak object keys');

SELECT * FROM finish();
ROLLBACK;
