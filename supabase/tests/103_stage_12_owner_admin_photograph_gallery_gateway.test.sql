BEGIN;
SELECT plan(27);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010301','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.103@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010302','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.103@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010303','00000000-0000-0000-0000-000000000000','authenticated','authenticated','inactive.owner.103@example.test','',now(),'{}','{}',now(),now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010301','owner.103@example.test','Owner 103',decode('1031031031031031031031031031031031031031031031031031031031031031','hex'),'req-103','corr-103');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010301',true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Owner Photo Contractor','Owner Photo Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010302','00000000-0000-0000-0000-000000010302','client.103@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('10000000-0000-0000-0000-000000010303','00000000-0000-0000-0000-000000010303','inactive.owner.103@example.test','STAFF','INVITED',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010302','Client 103',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('10000000-0000-0000-0000-000000010303','Inactive Owner 103',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'));
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active, revoked_at, revoked_by, revoke_reason)
VALUES
  ('10000000-0000-0000-0000-000000010302','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),true,NULL,NULL,NULL),
  ('10000000-0000-0000-0000-000000010303','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),false,now(),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'inactive test role');

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010301','Photo Client 103',NULL,'photo.103@example.test');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010301',(SELECT id FROM app.clients WHERE display_name='Photo Client 103'),'Photo Project 103','USD');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000010301',(SELECT id FROM app.projects WHERE name='Photo Project 103'),'Active photo task 103',NULL,NULL,'Summary','Client summary',10,true,NULL,NULL,true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000010301',(SELECT id FROM app.projects WHERE name='Photo Project 103'),'Inactive photo task 103',NULL,NULL,'Summary','Client summary',10,true,NULL,NULL,true);

SELECT set_config('app.allow_project_task_archive','on',true);
UPDATE app.tasks SET is_active=false WHERE title='Inactive photo task 103';
SELECT set_config('app.allow_project_task_archive','',true);

SELECT set_config('app.document_metadata_context','owner_metadata_mutation',true);
INSERT INTO app.documents (id, storage_bucket, storage_object_key, original_file_name, mime_type, file_size_bytes, sha256_hash, document_type_code, client_visible, uploaded_by, uploaded_at, status, archived_at, archived_by)
VALUES
  ('23000000-0000-4000-8000-000000010301','documents-private','objects/23000000-0000-4000-8000-000000010301/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','progress-ready.jpg','image/jpeg',101,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 10:00:00+00','ACTIVE',NULL,NULL),
  ('23000000-0000-4000-8000-000000010302','documents-private','objects/23000000-0000-4000-8000-000000010302/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','task-ready.png','image/png',102,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 09:00:00+00','ACTIVE',NULL,NULL),
  ('23000000-0000-4000-8000-000000010303','documents-private','objects/23000000-0000-4000-8000-000000010303/ccccccccccccccccccccccccccccccccccccccccccc','task-pdf.pdf','application/pdf',103,decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 08:00:00+00','ACTIVE',NULL,NULL),
  ('23000000-0000-4000-8000-000000010304','documents-private','objects/23000000-0000-4000-8000-000000010304/ddddddddddddddddddddddddddddddddddddddddddd','unsupported.gif','image/gif',104,decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 07:00:00+00','ACTIVE',NULL,NULL),
  ('23000000-0000-4000-8000-000000010305','documents-private','objects/23000000-0000-4000-8000-000000010305/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','inactive-task.jpg','image/jpeg',105,decode('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 06:00:00+00','ACTIVE',NULL,NULL),
  ('23000000-0000-4000-8000-000000010306','documents-private','objects/23000000-0000-4000-8000-000000010306/fffffffffffffffffffffffffffffffffffffffffff','archived-progress.jpg','image/jpeg',106,decode('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 05:00:00+00','ARCHIVED',now(),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010307','documents-private','objects/23000000-0000-4000-8000-000000010307/1111111111111111111111111111111111111111111','superseded-progress.jpg','image/jpeg',107,decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 04:00:00+00','ACTIVE',NULL,NULL),
  ('23000000-0000-4000-8000-000000010308','documents-private','objects/23000000-0000-4000-8000-000000010308/2222222222222222222222222222222222222222222','replacement-progress.jpg','image/jpeg',108,decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 03:00:00+00','ACTIVE',NULL,NULL),
  ('23000000-0000-4000-8000-000000010310','documents-private','objects/23000000-0000-4000-8000-000000010310/4444444444444444444444444444444444444444444','same-time-b.jpg','image/jpeg',110,decode('4444444444444444444444444444444444444444444444444444444444444444','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'),'2026-08-11 10:00:00+00','ACTIVE',NULL,NULL);
SELECT set_config('app.document_metadata_context','',true);

INSERT INTO app.document_links (document_id, project_id, task_id, created_by)
VALUES
  ('23000000-0000-4000-8000-000000010301',(SELECT id FROM app.projects WHERE name='Photo Project 103'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010302',NULL,(SELECT id FROM app.tasks WHERE title='Active photo task 103'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010303',NULL,(SELECT id FROM app.tasks WHERE title='Active photo task 103'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010304',NULL,(SELECT id FROM app.tasks WHERE title='Active photo task 103'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010305',NULL,(SELECT id FROM app.tasks WHERE title='Inactive photo task 103'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010306',(SELECT id FROM app.projects WHERE name='Photo Project 103'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010307',(SELECT id FROM app.projects WHERE name='Photo Project 103'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010308',(SELECT id FROM app.projects WHERE name='Photo Project 103'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301')),
  ('23000000-0000-4000-8000-000000010310',(SELECT id FROM app.projects WHERE name='Photo Project 103'),NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'));

SELECT set_config('app.document_lifecycle_context','owner_document_lifecycle_mutation',true);
INSERT INTO app.document_replacements (superseded_document_id, replacement_document_id, created_by)
VALUES ('23000000-0000-4000-8000-000000010307','23000000-0000-4000-8000-000000010308',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010301'));
SELECT set_config('app.document_lifecycle_context','',true);

INSERT INTO app.document_image_derivatives (document_id, processing_status, source_sha256_hash, source_width, source_height, thumbnail_storage_object_key, thumbnail_width, thumbnail_height, thumbnail_file_size_bytes, thumbnail_sha256_hash, preview_storage_object_key, preview_width, preview_height, preview_file_size_bytes, preview_sha256_hash, processor_version, processing_completed_at, failure_code, processing_failed_at)
VALUES
  ('23000000-0000-4000-8000-000000010301','READY',decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),4,3,'derivatives/23000000-0000-4000-8000-000000010301/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/thumbnail.webp',3,2,60,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'derivatives/23000000-0000-4000-8000-000000010301/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/preview.webp',4,3,70,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'test',now(),NULL,NULL),
  ('23000000-0000-4000-8000-000000010302','FAILED',decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'test',NULL,'animated_image_unsupported',now());

SELECT ok(has_function_privilege('authenticated','public.owner_admin_photograph_list(text,integer,integer)','EXECUTE'), 'authenticated can execute Owner/Admin photograph RPC');
SELECT ok(NOT has_function_privilege('anon','public.owner_admin_photograph_list(text,integer,integer)','EXECUTE'), 'anonymous execution grant denied');
SELECT ok(NOT has_function_privilege('service_role','public.owner_admin_photograph_list(text,integer,integer)','EXECUTE'), 'service role direct RPC grant withheld');
SELECT ok(NOT has_function_privilege('authenticated','app.owner_admin_photograph_projection(uuid,text,integer,integer)','EXECUTE'), 'private helper not executable by authenticated');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010302',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') $$, '42501', 'Privileged operation denied.', 'Client cannot execute Owner/Admin photograph RPC');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010303',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') $$, '42501', 'Privileged operation denied.', 'inactive/untrusted Owner/Admin denied');
SELECT set_config('request.jwt.claim.sub','',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') $$, '42501', 'Privileged operation denied.', 'anonymous execution denied');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010301',true);
SELECT lives_ok($$ SELECT * FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') $$, 'active Owner/Admin allowed');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') WHERE id='23000000-0000-4000-8000-000000010301'),1,'PROGRESS_PHOTOGRAPH category returns eligible photograph');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('TASK_ATTACHMENT') WHERE id='23000000-0000-4000-8000-000000010302'),1,'TASK_ATTACHMENT category returns eligible image task attachment');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('TASK_ATTACHMENT') WHERE id='23000000-0000-4000-8000-000000010303'),0,'TASK_ATTACHMENT PDF excluded');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('TASK_ATTACHMENT') WHERE id='23000000-0000-4000-8000-000000010304'),0,'unsupported image MIME excluded according to existing helper');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('TASK_ATTACHMENT') WHERE id='23000000-0000-4000-8000-000000010305'),0,'task image with inactive Task parent excluded by helper semantics');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') WHERE id='23000000-0000-4000-8000-000000010306'),0,'archived/non-ACTIVE photograph excluded');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') WHERE id='23000000-0000-4000-8000-000000010307'),0,'superseded photograph excluded');
SELECT results_eq($$ SELECT photograph_processing_status, thumbnail_available, preview_available FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') WHERE id='23000000-0000-4000-8000-000000010301' $$, $$ VALUES ('READY'::text,true,true) $$, 'processing status and READY derivative availability returned safely');
SELECT results_eq($$ SELECT photograph_processing_status, thumbnail_available, preview_available FROM public.owner_admin_photograph_list('TASK_ATTACHMENT') WHERE id='23000000-0000-4000-8000-000000010302' $$, $$ VALUES ('FAILED'::text,false,false) $$, 'FAILED derivative availability returned safely');
SELECT ok((SELECT pg_get_function_result('public.owner_admin_photograph_list(text,integer,integer)'::regprocedure)) NOT ILIKE '%bucket%' AND (SELECT pg_get_function_result('public.owner_admin_photograph_list(text,integer,integer)'::regprocedure)) NOT ILIKE '%storage%' AND (SELECT pg_get_function_result('public.owner_admin_photograph_list(text,integer,integer)'::regprocedure)) NOT ILIKE '%object%' AND (SELECT pg_get_function_result('public.owner_admin_photograph_list(text,integer,integer)'::regprocedure)) NOT ILIKE '%hash%' AND (SELECT pg_get_function_result('public.owner_admin_photograph_list(text,integer,integer)'::regprocedure)) NOT ILIKE '%scanner%' AND (SELECT pg_get_function_result('public.owner_admin_photograph_list(text,integer,integer)'::regprocedure)) NOT ILIKE '%service%' AND (SELECT pg_get_function_result('public.owner_admin_photograph_list(text,integer,integer)'::regprocedure)) NOT ILIKE '%signed%', 'safe projection excludes Storage keys/buckets/hashes/scanner/service-role data');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_photograph_list('GENERAL') $$, '23514', 'Photograph category is invalid.', 'category validation rejects unrelated document type');
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH',1,0) $$, $$ VALUES ('same-time-b.jpg'::text) $$, 'pagination limit works');
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH',1,1) $$, $$ VALUES ('progress-ready.jpg'::text) $$, 'pagination offset works');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH',101,0) $$, '23514', 'Invalid pagination request.', 'invalid limit rejected');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH',50,-1) $$, '23514', 'Invalid pagination request.', 'negative offset rejected');
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') ORDER BY uploaded_at DESC, id DESC $$, $$ VALUES ('same-time-b.jpg'::text), ('progress-ready.jpg'::text), ('replacement-progress.jpg'::text) $$, 'deterministic uploaded_at DESC, id DESC order');
SELECT ok((SELECT pg_get_functiondef('app.owner_admin_photograph_projection(uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.document_image_is_eligible%' AND (SELECT pg_get_functiondef('app.owner_admin_photograph_projection(uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.document_is_superseded%' AND (SELECT pg_get_functiondef('app.owner_admin_photograph_projection(uuid,text,integer,integer)'::regprocedure)) ILIKE '%require_active_owner_admin%', 'source uses authorization, image eligibility, and lifecycle helpers');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('PROGRESS_PHOTOGRAPH') AS l WHERE NOT app.document_image_is_eligible(l.id)),0,'result eligibility agrees behaviorally with app.document_image_is_eligible');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_photograph_list('TASK_ATTACHMENT') AS l WHERE NOT app.document_image_is_eligible(l.id)),0,'TASK_ATTACHMENT result eligibility agrees behaviorally with app.document_image_is_eligible');

SELECT * FROM finish();
ROLLBACK;
