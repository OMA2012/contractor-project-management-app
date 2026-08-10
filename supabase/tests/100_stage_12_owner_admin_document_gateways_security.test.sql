BEGIN;
SELECT plan(9);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.100@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.100@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','inactive.100@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pm.100@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','accountant.100@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','supervisor.100@example.test','',now(),'{}','{}',now(),now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010001','owner.100@example.test','Owner 100',decode('1010101010101010101010101010101010101010101010101010101010101010','hex'),'req-100','corr-100');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010001',true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010002','00000000-0000-0000-0000-000000010002','client.100@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001')),
  ('10000000-0000-0000-0000-000000010003','00000000-0000-0000-0000-000000010003','inactive.100@example.test','STAFF','INVITED',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001')),
  ('10000000-0000-0000-0000-000000010004','00000000-0000-0000-0000-000000010004','pm.100@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001')),
  ('10000000-0000-0000-0000-000000010005','00000000-0000-0000-0000-000000010005','accountant.100@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001')),
  ('10000000-0000-0000-0000-000000010006','00000000-0000-0000-0000-000000010006','supervisor.100@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001')
FROM app.users WHERE auth_subject::text LIKE '00000000-0000-0000-0000-00000001000%' AND auth_subject <> '00000000-0000-0000-0000-000000010001';
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000010002','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),true),
  ('10000000-0000-0000-0000-000000010004','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),true),
  ('10000000-0000-0000-0000-000000010005','accountant',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),true),
  ('10000000-0000-0000-0000-000000010006','site_supervisor',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010001'),true);

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010001',true);
SELECT lives_ok($$ SELECT * FROM public.owner_admin_document_list() $$, 'active Owner/Admin can execute list');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010002',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_list() $$, '42501', 'Privileged operation denied.', 'Client denied');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010003',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_list() $$, '42501', 'Privileged operation denied.', 'inactive Owner/Admin denied');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010004',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_list() $$, '42501', 'Privileged operation denied.', 'Project Manager denied');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010005',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_list() $$, '42501', 'Privileged operation denied.', 'Accountant denied');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010006',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_list() $$, '42501', 'Privileged operation denied.', 'Site Supervisor denied');
SELECT set_config('request.jwt.claim.sub','',true);
SELECT throws_ok($$ SELECT * FROM public.owner_admin_document_list() $$, '42501', 'Privileged operation denied.', 'anonymous denied');
SELECT ok((SELECT pg_get_functiondef('app.owner_admin_document_projection(uuid,uuid,uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) ILIKE '%require_active_owner_admin%', 'projection uses authoritative Owner/Admin helper');
SELECT ok((SELECT pg_get_functiondef('app.owner_admin_document_projection(uuid,uuid,uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%project_manager%' AND (SELECT pg_get_functiondef('app.owner_admin_document_projection(uuid,uuid,uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%accountant%' AND (SELECT pg_get_functiondef('app.owner_admin_document_projection(uuid,uuid,uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%site_supervisor%', 'no reserved staff role activation added');

SELECT * FROM finish();
ROLLBACK;
