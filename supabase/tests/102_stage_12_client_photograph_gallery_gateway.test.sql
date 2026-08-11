BEGIN;
SELECT plan(25);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010201','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.102@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010202','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.a.102@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010203','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.b.102@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010204','00000000-0000-0000-0000-000000000000','authenticated','authenticated','inactive.102@example.test','',now(),'{}','{}',now(),now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010201','owner.102@example.test','Owner 102',decode('1021021021021021021021021021021021021021021021021021021021021021','hex'),'req-102','corr-102');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010201',true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Photo Contractor','Photo Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010202','00000000-0000-0000-0000-000000010202','client.a.102@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('10000000-0000-0000-0000-000000010203','00000000-0000-0000-0000-000000010203','client.b.102@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('10000000-0000-0000-0000-000000010204','00000000-0000-0000-0000-000000010204','inactive.102@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010202','Client A 102',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('10000000-0000-0000-0000-000000010203','Client B 102',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('10000000-0000-0000-0000-000000010204','Inactive Client 102',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'));
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000010202','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),true),
  ('10000000-0000-0000-0000-000000010203','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),true),
  ('10000000-0000-0000-0000-000000010204','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),true);
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010201','Photo Client A',NULL,'photo.a@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010201','Photo Client B',NULL,'photo.b@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010201','Photo Client Inactive',NULL,'photo.inactive@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000010201',(SELECT id FROM app.clients WHERE display_name='Photo Client A'),'10000000-0000-0000-0000-000000010202',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000010201',(SELECT id FROM app.clients WHERE display_name='Photo Client B'),'10000000-0000-0000-0000-000000010203',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000010201',(SELECT id FROM app.clients WHERE display_name='Photo Client Inactive'),'10000000-0000-0000-0000-000000010204',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010201',(SELECT id FROM app.clients WHERE display_name='Photo Client A'),'Photo Project A','USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010201',(SELECT id FROM app.clients WHERE display_name='Photo Client B'),'Photo Project B','USD');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000010201',(SELECT id FROM app.projects WHERE name='Photo Project A'),'Photo task visible',NULL,NULL,'Summary','Client summary',10,true,NULL,NULL,true);

UPDATE app.users SET status = 'SUSPENDED', is_active = false WHERE id = '10000000-0000-0000-0000-000000010204';

SELECT set_config('app.document_metadata_context','owner_metadata_mutation',true);
INSERT INTO app.documents (id, storage_bucket, storage_object_key, original_file_name, mime_type, file_size_bytes, sha256_hash, document_type_code, client_visible, uploaded_by, uploaded_at, status, archived_at, archived_by)
VALUES
  ('22000000-0000-4000-8000-000000010201','documents-private','objects/22000000-0000-4000-8000-000000010201/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','own-ready.jpg','image/jpeg',101,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '1 minute','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010202','documents-private','objects/22000000-0000-4000-8000-000000010202/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','own-private.jpg','image/jpeg',102,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'PROGRESS_PHOTOGRAPH',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '2 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010203','documents-private','objects/22000000-0000-4000-8000-000000010203/ccccccccccccccccccccccccccccccccccccccccccc','own-archived.jpg','image/jpeg',103,decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '3 minutes','ARCHIVED',now(),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010204','documents-private','objects/22000000-0000-4000-8000-000000010204/ddddddddddddddddddddddddddddddddddddddddddd','own-superseded.jpg','image/jpeg',104,decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '4 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010205','documents-private','objects/22000000-0000-4000-8000-000000010205/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','own-replacement.jpg','image/jpeg',105,decode('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '5 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010206','documents-private','objects/22000000-0000-4000-8000-000000010206/fffffffffffffffffffffffffffffffffffffffffff','own-lifecycle-private.jpg','image/jpeg',106,decode('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '6 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010207','documents-private','objects/22000000-0000-4000-8000-000000010207/1111111111111111111111111111111111111111111','general-image.jpg','image/jpeg',107,decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '7 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010208','documents-private','objects/22000000-0000-4000-8000-000000010208/2222222222222222222222222222222222222222222','task-image.png','image/png',108,decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '8 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010209','documents-private','objects/22000000-0000-4000-8000-000000010209/3333333333333333333333333333333333333333333','task-pdf.pdf','application/pdf',109,decode('3333333333333333333333333333333333333333333333333333333333333333','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '9 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010210','documents-private','objects/22000000-0000-4000-8000-000000010210/4444444444444444444444444444444444444444444','other-client.jpg','image/jpeg',110,decode('4444444444444444444444444444444444444444444444444444444444444444','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '10 minutes','ACTIVE',NULL,NULL),
  ('22000000-0000-4000-8000-000000010211','documents-private','objects/22000000-0000-4000-8000-000000010211/5555555555555555555555555555555555555555555','mixed-client.jpg','image/jpeg',111,decode('5555555555555555555555555555555555555555555555555555555555555555','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'),now() - interval '11 minutes','ACTIVE',NULL,NULL);
SELECT set_config('app.document_metadata_context','',true);

INSERT INTO app.document_links (document_id, project_id, task_id, created_by)
VALUES
  ('22000000-0000-4000-8000-000000010201',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010202',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010203',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010204',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010205',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010206',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010207',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010208',NULL,(SELECT id FROM app.tasks WHERE title='Photo task visible'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010209',NULL,(SELECT id FROM app.tasks WHERE title='Photo task visible'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010210',(SELECT id FROM app.projects WHERE name='Photo Project B'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010211',(SELECT id FROM app.projects WHERE name='Photo Project A'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201')),
  ('22000000-0000-4000-8000-000000010211',(SELECT id FROM app.projects WHERE name='Photo Project B'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'));

SELECT set_config('app.document_lifecycle_context','owner_document_lifecycle_mutation',true);
INSERT INTO app.document_replacements (superseded_document_id, replacement_document_id, created_by)
VALUES ('22000000-0000-4000-8000-000000010204','22000000-0000-4000-8000-000000010205',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'));
INSERT INTO app.document_client_access_privacy (document_id, privacy_reason, created_by)
VALUES ('22000000-0000-4000-8000-000000010206','RESTORED_PRIVATE',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010201'));
SELECT set_config('app.document_lifecycle_context','',true);

INSERT INTO app.document_image_derivatives (document_id, processing_status, source_sha256_hash, source_width, source_height, thumbnail_storage_object_key, thumbnail_width, thumbnail_height, thumbnail_file_size_bytes, thumbnail_sha256_hash, preview_storage_object_key, preview_width, preview_height, preview_file_size_bytes, preview_sha256_hash, processor_version, processing_completed_at, failure_code, processing_failed_at)
VALUES
  ('22000000-0000-4000-8000-000000010201','READY',decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),4,3,'derivatives/22000000-0000-4000-8000-000000010201/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/thumbnail.webp',3,2,60,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'derivatives/22000000-0000-4000-8000-000000010201/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/preview.webp',4,3,70,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'test',now(),NULL,NULL),
  ('22000000-0000-4000-8000-000000010208','FAILED',decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'test',NULL,'animated_image_unsupported',now());

SELECT ok(NOT has_function_privilege('anon','public.current_client_photograph_list(integer,integer)','EXECUTE'), 'unauthenticated access denied');
SELECT ok(has_function_privilege('authenticated','public.current_client_photograph_list(integer,integer)','EXECUTE'), 'authenticated can execute photograph gallery RPC');
SELECT ok(NOT has_function_privilege('service_role','public.current_client_photograph_list(integer,integer)','EXECUTE'), 'service role direct RPC grant withheld');
SELECT ok(NOT has_function_privilege('authenticated','app.current_client_photograph_list_for_authenticated_user(integer,integer)','EXECUTE'), 'private helper not executable by authenticated');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010204',true);
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list()),0,'inactive Client denied');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010202',true);
SELECT results_eq($$ SELECT id, original_file_name, photograph_processing_status, thumbnail_available, preview_available FROM public.current_client_photograph_list() ORDER BY uploaded_at DESC, id DESC $$, $$ VALUES ('22000000-0000-4000-8000-000000010201'::uuid,'own-ready.jpg'::text,'READY'::text,true,true), ('22000000-0000-4000-8000-000000010205'::uuid,'own-replacement.jpg'::text,NULL::text,false,false), ('22000000-0000-4000-8000-000000010208'::uuid,'task-image.png'::text,'FAILED'::text,false,false) $$, 'Client sees only own eligible active visible photographs with derivative status');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010210'),0,'Client A cannot see Client B photographs');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010202'),0,'contractor-private photograph excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010203'),0,'archived photograph excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010204'),0,'superseded photograph excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010206'),0,'lifecycle-private photograph excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010211'),0,'mixed-client photograph excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010207'),0,'non-photograph image document excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010209'),0,'TASK_ATTACHMENT PDF excluded by image semantics');
SELECT is((SELECT count(*)::integer FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010208'),1,'image TASK_ATTACHMENT included by existing image semantics');
SELECT results_eq($$ SELECT photograph_processing_status, thumbnail_available, preview_available FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010201' $$, $$ VALUES ('READY'::text,true,true) $$, 'READY derivative availability returned safely');
SELECT results_eq($$ SELECT photograph_processing_status, thumbnail_available, preview_available FROM public.current_client_photograph_list() WHERE id='22000000-0000-4000-8000-000000010208' $$, $$ VALUES ('FAILED'::text,false,false) $$, 'FAILED derivative availability returned safely');
SELECT ok((SELECT pg_get_function_result('public.current_client_photograph_list(integer,integer)'::regprocedure)) NOT ILIKE '%bucket%' AND (SELECT pg_get_function_result('public.current_client_photograph_list(integer,integer)'::regprocedure)) NOT ILIKE '%storage%' AND (SELECT pg_get_function_result('public.current_client_photograph_list(integer,integer)'::regprocedure)) NOT ILIKE '%object%' AND (SELECT pg_get_function_result('public.current_client_photograph_list(integer,integer)'::regprocedure)) NOT ILIKE '%hash%' AND (SELECT pg_get_function_result('public.current_client_photograph_list(integer,integer)'::regprocedure)) NOT ILIKE '%scanner%' AND (SELECT pg_get_function_result('public.current_client_photograph_list(integer,integer)'::regprocedure)) NOT ILIKE '%service%' AND (SELECT pg_get_function_result('public.current_client_photograph_list(integer,integer)'::regprocedure)) NOT ILIKE '%signed%', 'safe projection excludes storage/hash/scanner/service/signed-url fields');
SELECT results_eq($$ SELECT original_file_name FROM public.current_client_photograph_list(1,0) $$, $$ VALUES ('own-ready.jpg'::text) $$, 'pagination limit returns first ordered photograph');
SELECT results_eq($$ SELECT original_file_name FROM public.current_client_photograph_list(1,1) $$, $$ VALUES ('own-replacement.jpg'::text) $$, 'pagination offset returns second ordered photograph');
SELECT throws_ok($$ SELECT * FROM public.current_client_photograph_list(101,0) $$, '23514', 'Invalid pagination request.', 'maximum limit enforcement works');
SELECT throws_ok($$ SELECT * FROM public.current_client_photograph_list(0,0) $$, '23514', 'Invalid pagination request.', 'minimum limit enforcement works');
SELECT throws_ok($$ SELECT * FROM public.current_client_photograph_list(50,-1) $$, '23514', 'Invalid pagination request.', 'negative offset rejected');
SELECT results_eq($$ SELECT original_file_name FROM public.current_client_photograph_list(50,0) ORDER BY uploaded_at DESC, id DESC $$, $$ VALUES ('own-ready.jpg'::text), ('own-replacement.jpg'::text), ('task-image.png'::text) $$, 'ordering is deterministic uploaded_at desc id desc');
SELECT ok((SELECT pg_get_functiondef('app.current_client_photograph_list_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%app.document_image_is_eligible%' AND (SELECT pg_get_functiondef('app.current_client_photograph_list_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%app.document_image_client_parent_visible%' AND (SELECT pg_get_functiondef('app.current_client_photograph_list_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%NOT app.document_is_superseded%' AND (SELECT pg_get_functiondef('app.current_client_photograph_list_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%NOT app.document_is_client_lifecycle_private%', 'gateway reuses image eligibility, parent visibility, supersession, and lifecycle privacy helpers');

SELECT * FROM finish();
ROLLBACK;
