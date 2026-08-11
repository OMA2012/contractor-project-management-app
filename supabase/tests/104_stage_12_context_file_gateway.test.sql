BEGIN;
SELECT plan(39);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010401','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.104@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010402','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.104@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010403','00000000-0000-0000-0000-000000000000','authenticated','authenticated','inactive.104@example.test','',now(),'{}','{}',now(),now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010401','owner.104@example.test','Owner 104',decode('1041041041041041041041041041041041041041041041041041041041041041','hex'),'req-104','corr-104');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010401',true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Context Contractor 104','Context Contractor 104','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010402','00000000-0000-0000-0000-000000010402','client.104@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('10000000-0000-0000-0000-000000010403','00000000-0000-0000-0000-000000010403','inactive.104@example.test','STAFF','INVITED',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010402','Client 104',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('10000000-0000-0000-0000-000000010403','Inactive 104',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active, revoked_at, revoked_by, revoke_reason)
VALUES
  ('10000000-0000-0000-0000-000000010402','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),true,NULL,NULL,NULL),
  ('10000000-0000-0000-0000-000000010403','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),false,now(),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'inactive');

INSERT INTO app.clients (id, portal_user_id, display_name, email, created_by, updated_by)
VALUES ('20000000-0000-0000-0000-000000010401','10000000-0000-0000-0000-000000010402','Client 104','client.104@example.test',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
       ('20000000-0000-0000-0000-000000010499',NULL,'Other Client 104','other.104@example.test',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));
INSERT INTO app.projects (id, project_number, client_id, name, status, reporting_currency_code, created_by, updated_by)
VALUES
  ('30000000-0000-0000-0000-000000010401','PRJ-2026-1041','20000000-0000-0000-0000-000000010401','Project 104','ACTIVE','USD',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('30000000-0000-0000-0000-000000010499','PRJ-2026-1499','20000000-0000-0000-0000-000000010499','Other Project 104','ACTIVE','USD',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));
INSERT INTO app.tasks (id, project_id, task_number, title, weight_percent, created_by, updated_by)
VALUES
  ('40000000-0000-0000-0000-000000010401','30000000-0000-0000-0000-000000010401','TSK-1041','Task 104',10,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('40000000-0000-0000-0000-000000010499','30000000-0000-0000-0000-000000010499','TSK-1499','Other Task 104',10,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));
INSERT INTO app.progress_updates (id, project_id, title, summary, status, client_visible, submitted_at, submitted_by, approved_at, approved_by, published_at, created_at, created_by, updated_by)
VALUES
  ('50000000-0000-0000-0000-000000010401','30000000-0000-0000-0000-000000010401','Progress 104','Safe summary','APPROVED',true,'2026-08-10 01:00+00','10000000-0000-0000-0000-000000010402','2026-08-10 02:00+00',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-10 03:00+00','2026-08-10 00:00+00','10000000-0000-0000-0000-000000010402',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('50000000-0000-0000-0000-000000010402','30000000-0000-0000-0000-000000010401','Private Progress 104','Safe summary','DRAFT',false,NULL,NULL,NULL,NULL,NULL,'2026-08-10 00:00+00',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('50000000-0000-0000-0000-000000010499','30000000-0000-0000-0000-000000010499','Other Progress 104','Safe summary','APPROVED',true,'2026-08-10 01:00+00','10000000-0000-0000-0000-000000010402','2026-08-10 02:00+00',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-10 03:00+00','2026-08-10 00:00+00','10000000-0000-0000-0000-000000010402',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));

SELECT set_config('app.document_metadata_context','owner_metadata_mutation',true);
INSERT INTO app.documents (id, storage_bucket, storage_object_key, original_file_name, mime_type, file_size_bytes, sha256_hash, document_type_code, client_visible, uploaded_by, uploaded_at, status, archived_at, archived_by)
VALUES
  ('60000000-0000-0000-0000-000000010401','documents-private','objects/104/project.pdf','project.pdf','application/pdf',101,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 10:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010402','documents-private','objects/104/task.pdf','task.pdf','application/pdf',102,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'TASK_ATTACHMENT',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 09:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010403','documents-private','objects/104/progress.jpg','progress.jpg','image/jpeg',103,decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),'PROGRESS_PHOTOGRAPH',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 08:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010404','documents-private','objects/104/private.pdf','private.pdf','application/pdf',104,decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','hex'),'GENERAL',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 07:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010405','documents-private','objects/104/archived.pdf','archived.pdf','application/pdf',105,decode('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 06:00+00','ARCHIVED',now(),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010406','documents-private','objects/104/superseded.pdf','superseded.pdf','application/pdf',106,decode('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 05:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010407','documents-private','objects/104/replacement.pdf','replacement.pdf','application/pdf',107,decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 04:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010408','documents-private','objects/104/private-progress.pdf','private-progress.pdf','application/pdf',108,decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 03:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010409','documents-private','objects/104/readable-progress-private-file.pdf','readable-progress-private-file.pdf','application/pdf',110,decode('4444444444444444444444444444444444444444444444444444444444444444','hex'),'GENERAL',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 01:00+00','ACTIVE',NULL,NULL),
  ('60000000-0000-0000-0000-000000010499','documents-private','objects/104/other.pdf','other.pdf','application/pdf',109,decode('3333333333333333333333333333333333333333333333333333333333333333','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'),'2026-08-11 02:00+00','ACTIVE',NULL,NULL);
SELECT set_config('app.document_metadata_context','',true);

INSERT INTO app.document_links (document_id, project_id, task_id, progress_update_id, created_by)
VALUES
  ('60000000-0000-0000-0000-000000010401','30000000-0000-0000-0000-000000010401',NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010402',NULL,'40000000-0000-0000-0000-000000010401',NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010403',NULL,NULL,'50000000-0000-0000-0000-000000010401',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010404','30000000-0000-0000-0000-000000010401',NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010405','30000000-0000-0000-0000-000000010401',NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010406','30000000-0000-0000-0000-000000010401',NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010407','30000000-0000-0000-0000-000000010401',NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010408',NULL,NULL,'50000000-0000-0000-0000-000000010402',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010409',NULL,NULL,'50000000-0000-0000-0000-000000010401',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401')),
  ('60000000-0000-0000-0000-000000010499','30000000-0000-0000-0000-000000010499',NULL,NULL,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));

SELECT set_config('app.document_lifecycle_context','owner_document_lifecycle_mutation',true);
INSERT INTO app.document_replacements (superseded_document_id, replacement_document_id, created_by)
VALUES ('60000000-0000-0000-0000-000000010406','60000000-0000-0000-0000-000000010407',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010401'));
SELECT set_config('app.document_lifecycle_context','',true);

INSERT INTO app.document_image_derivatives (document_id, processing_status, source_sha256_hash, source_width, source_height, thumbnail_storage_object_key, thumbnail_width, thumbnail_height, thumbnail_file_size_bytes, thumbnail_sha256_hash, preview_storage_object_key, preview_width, preview_height, preview_file_size_bytes, preview_sha256_hash, processor_version, processing_completed_at)
VALUES ('60000000-0000-0000-0000-000000010403','READY',decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),4,3,'derivatives/60000000-0000-0000-0000-000000010403/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/thumbnail.webp',3,2,60,decode('4444444444444444444444444444444444444444444444444444444444444444','hex'),'derivatives/60000000-0000-0000-0000-000000010403/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/preview.webp',4,3,70,decode('5555555555555555555555555555555555555555555555555555555555555555','hex'),'test',now());

SELECT has_function('public','owner_admin_context_file_list',ARRAY['text','uuid','text','integer','integer'], 'Owner/Admin context RPC exists');
SELECT has_function('public','current_client_context_file_list',ARRAY['text','uuid','text','integer','integer'], 'Client context RPC exists');
SELECT ok(has_function_privilege('authenticated','public.owner_admin_context_file_list(text,uuid,text,integer,integer)','EXECUTE'), 'authenticated can execute Owner/Admin RPC');
SELECT ok(has_function_privilege('authenticated','public.current_client_context_file_list(text,uuid,text,integer,integer)','EXECUTE'), 'authenticated can execute Client RPC');
SELECT ok(NOT has_function_privilege('anon','public.owner_admin_context_file_list(text,uuid,text,integer,integer)','EXECUTE'), 'anonymous Owner/Admin grant absent');
SELECT ok(NOT has_function_privilege('service_role','public.owner_admin_context_file_list(text,uuid,text,integer,integer)','EXECUTE'), 'service_role Owner/Admin grant absent');
SELECT ok(NOT has_function_privilege('authenticated','app.owner_admin_context_file_projection(uuid,text,uuid,text,integer,integer)','EXECUTE'), 'private Owner/Admin helper unavailable');
SELECT ok(NOT has_function_privilege('authenticated','app.current_client_context_file_projection(text,uuid,text,integer,integer)','EXECUTE'), 'private Client helper unavailable');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010402',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') $$, '42501', 'Privileged operation denied.', 'Client denied from Owner/Admin RPC');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010401',true);
SELECT is((SELECT count(*)::integer FROM public.current_client_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT')),0,'Owner/Admin receives no Client RPC data');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010403',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') $$, '42501', 'Privileged operation denied.', 'inactive/untrusted account denied');
SELECT set_config('request.jwt.claim.sub','',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') $$, '42501', 'Privileged operation denied.', 'anonymous denied');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010401',true);
SELECT lives_ok($$ SELECT * FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') $$, 'PROJECT context accepted');
SELECT lives_ok($$ SELECT * FROM public.owner_admin_context_file_list('TASK','40000000-0000-0000-0000-000000010401','DOCUMENT') $$, 'TASK context accepted');
SELECT lives_ok($$ SELECT * FROM public.owner_admin_context_file_list('PROGRESS_UPDATE','50000000-0000-0000-0000-000000010401','PHOTOGRAPH') $$, 'PROGRESS_UPDATE context accepted');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_context_file_list('CLIENT','20000000-0000-0000-0000-000000010401','DOCUMENT') $$, '23514', 'Context type is invalid.', 'CLIENT context rejected');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_context_file_list('CLIENT_PAYMENT','20000000-0000-0000-0000-000000010401','DOCUMENT') $$, '23514', 'Context type is invalid.', 'finance context rejected');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','VIDEO') $$, '23514', 'Content kind is invalid.', 'invalid content kind rejected');
SELECT throws_ok($$ SELECT * FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT',0,0) $$, '23514', 'Invalid pagination request.', 'bad pagination rejected');

SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') $$, $$ VALUES ('project.pdf'::text),('task.pdf'::text),('private.pdf'::text),('replacement.pdf'::text),('private-progress.pdf'::text),('readable-progress-private-file.pdf'::text) $$, 'Project context aggregates direct, Task, and Progress files and excludes archived/superseded/photo partition');
SELECT is((SELECT count(*)::integer FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') WHERE original_file_name='other.pdf'),0,'other Project excluded');
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_context_file_list('TASK','40000000-0000-0000-0000-000000010401','DOCUMENT') $$, $$ VALUES ('task.pdf'::text) $$, 'Task context returns only direct Task files');
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_context_file_list('PROGRESS_UPDATE','50000000-0000-0000-0000-000000010401','PHOTOGRAPH') $$, $$ VALUES ('progress.jpg'::text) $$, 'Progress context returns only direct Progress photograph');
SELECT results_eq($$ SELECT project_number, project_name, task_title, progress_update_title FROM public.owner_admin_context_file_list('TASK','40000000-0000-0000-0000-000000010401','DOCUMENT') $$, $$ VALUES ('PRJ-2026-1041'::text,'Project 104'::text,'Task 104'::text,NULL::text) $$, 'human-readable Project and Task labels populated');
SELECT results_eq($$ SELECT project_number, project_name, task_title, progress_update_title FROM public.owner_admin_context_file_list('PROGRESS_UPDATE','50000000-0000-0000-0000-000000010401','PHOTOGRAPH') $$, $$ VALUES ('PRJ-2026-1041'::text,'Project 104'::text,NULL::text,'Progress 104'::text) $$, 'human-readable Progress label populated');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010402',true);
SELECT results_eq($$ SELECT original_file_name FROM public.current_client_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') $$, $$ VALUES ('project.pdf'::text),('task.pdf'::text),('replacement.pdf'::text) $$, 'Client sees own Project readable visible documents only');
SELECT is((SELECT count(*)::integer FROM public.current_client_context_file_list('PROJECT','30000000-0000-0000-0000-000000010499','DOCUMENT')),0,'cross-client Project excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') WHERE original_file_name IN ('private.pdf','archived.pdf','superseded.pdf','private-progress.pdf')),0,'client private, archived, superseded, and private parent files excluded');
SELECT results_eq($$ SELECT original_file_name, photograph_processing_status, thumbnail_available, preview_available FROM public.current_client_context_file_list('PROGRESS_UPDATE','50000000-0000-0000-0000-000000010401','PHOTOGRAPH') $$, $$ VALUES ('progress.jpg'::text,'READY'::text,true,true) $$, 'Client readable parent plus visible eligible photograph allowed with safe derivative facts');
SELECT is((SELECT count(*)::integer FROM public.current_client_context_file_list('PROGRESS_UPDATE','50000000-0000-0000-0000-000000010401','DOCUMENT') WHERE original_file_name = 'readable-progress-private-file.pdf'),0,'readable published Progress parent does not override private file visibility');
SELECT is((SELECT count(*)::integer FROM public.current_client_context_file_list('PROGRESS_UPDATE','50000000-0000-0000-0000-000000010402','DOCUMENT')),0,'private/unpublished Progress parent exposes no file metadata');
SELECT is((SELECT count(*)::integer FROM public.current_client_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','PHOTOGRAPH') WHERE NOT app.document_image_is_eligible(id)),0,'PHOTOGRAPH uses authoritative eligibility');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010401',true);
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT',1,0) $$, $$ VALUES ('project.pdf'::text) $$, 'limit works after filtering');
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT',1,1) $$, $$ VALUES ('task.pdf'::text) $$, 'offset works after filtering');
SELECT results_eq($$ SELECT original_file_name FROM public.owner_admin_context_file_list('PROJECT','30000000-0000-0000-0000-000000010401','DOCUMENT') $$, $$ VALUES ('project.pdf'::text),('task.pdf'::text),('private.pdf'::text),('replacement.pdf'::text),('private-progress.pdf'::text),('readable-progress-private-file.pdf'::text) $$, 'ordering is uploaded_at DESC, id DESC');
SELECT ok((SELECT pg_get_function_result('public.owner_admin_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%bucket%' AND (SELECT pg_get_function_result('public.owner_admin_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%storage%' AND (SELECT pg_get_function_result('public.owner_admin_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%hash%' AND (SELECT pg_get_function_result('public.owner_admin_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%signed%' AND (SELECT pg_get_function_result('public.owner_admin_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%scanner%' AND (SELECT pg_get_function_result('public.owner_admin_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%service%', 'safe projection excludes storage keys, hashes, signed URLs, scanner and service metadata');
SELECT ok((SELECT pg_get_function_result('public.current_client_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%client_visible%' AND (SELECT pg_get_function_result('public.current_client_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%task_number%' AND (SELECT pg_get_function_result('public.current_client_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%summary%' AND (SELECT pg_get_function_result('public.current_client_context_file_list(text,uuid,text,integer,integer)'::regprocedure)) NOT ILIKE '%progress_update_date%', 'Client projection has no client_visible, invented task number, summary, or invented progress date field');
SELECT ok((SELECT pg_get_functiondef('app.current_client_context_file_projection(text,uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.current_client_project_task_for_authenticated_user%' AND (SELECT pg_get_functiondef('app.current_client_context_file_projection(text,uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.current_client_progress_update_detail_for_authenticated_user%' AND (SELECT pg_get_functiondef('app.current_client_context_file_projection(text,uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.document_image_client_parent_visible%' AND (SELECT pg_get_functiondef('app.current_client_context_file_projection(text,uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.document_image_is_eligible%', 'Client gateway reuses existing parent visibility and image eligibility helpers');
SELECT ok((SELECT pg_get_functiondef('app.owner_admin_context_file_projection(uuid,text,uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.require_active_owner_admin%' AND (SELECT pg_get_functiondef('app.owner_admin_context_file_projection(uuid,text,uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.document_is_superseded%' AND (SELECT pg_get_functiondef('app.owner_admin_context_file_projection(uuid,text,uuid,text,integer,integer)'::regprocedure)) ILIKE '%app.document_image_is_eligible%', 'Owner/Admin gateway uses authorization, lifecycle, and image eligibility helpers');

SELECT * FROM finish();
ROLLBACK;
