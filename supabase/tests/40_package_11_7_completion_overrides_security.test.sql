BEGIN;
SELECT plan(20);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.40a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.40b@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.40@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.40@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000004001', 'owner.40a@example.test', 'Owner Forty A', decode('4040404040404040404040404040404040404040404040404040404040404040', 'hex'), 'req-40', 'corr-40');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004001', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Override Security Contractor', 'Override Security Contractor', 'USD', 'Asia/Kuching', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004002', '00000000-0000-0000-0000-000000004002', 'owner.40b@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001')),
  ('10000000-0000-0000-0000-000000004003', '00000000-0000-0000-0000-000000004003', 'client.40@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001')),
  ('10000000-0000-0000-0000-000000004004', '00000000-0000-0000-0000-000000004004', 'pm.40@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004002', 'Owner Forty B', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001')),
  ('10000000-0000-0000-0000-000000004003', 'Client Forty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001')),
  ('10000000-0000-0000-0000-000000004004', 'PM Forty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000004002', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), true),
  ('10000000-0000-0000-0000-000000004003', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), true),
  ('10000000-0000-0000-0000-000000004004', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004001'), true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000004001', 'Override Security Client', NULL, 'client.40a@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000004001', (SELECT id FROM app.clients WHERE display_name = 'Override Security Client'), '10000000-0000-0000-0000-000000004003', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000004001', (SELECT id FROM app.clients WHERE display_name = 'Override Security Client'), 'Override Security Project', 'USD');

SELECT ok(
  has_table_privilege('authenticated', 'app.project_completion_overrides', 'SELECT') = false
  AND has_table_privilege('service_role', 'app.project_completion_overrides', 'SELECT') = false,
  'direct table SELECT denied to application roles'
);
SELECT ok(
  has_table_privilege('authenticated', 'app.project_completion_overrides', 'INSERT') = false
  AND has_table_privilege('service_role', 'app.project_completion_overrides', 'UPDATE') = false
  AND has_table_privilege('service_role', 'app.project_completion_overrides', 'DELETE') = false,
  'direct table writes denied to application roles'
);
SELECT ok(
  has_function_privilege('authenticated', 'app.current_project_official_completion(uuid)', 'EXECUTE') = false
  AND has_function_privilege('service_role', 'app.current_project_official_completion(uuid)', 'EXECUTE') = false,
  'private official completion helper is revoked'
);
SELECT ok(
  has_function_privilege('authenticated', 'app.owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet)', 'EXECUTE') = false
  AND has_function_privilege('service_role', 'app.owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet)', 'EXECUTE') = false,
  'private request function is revoked'
);
SELECT ok(
  has_function_privilege('service_role', 'public.server_owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet)', 'EXECUTE')
  AND has_function_privilege('authenticated', 'public.server_owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet)', 'EXECUTE') = false,
  'Owner request gateway is service-only'
);
SELECT ok(
  has_function_privilege('service_role', 'public.server_owner_approve_project_completion_override(uuid, uuid, text, text, text, inet)', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.server_owner_revoke_project_completion_override(uuid, uuid, text, text, text, text, inet)', 'EXECUTE'),
  'approve and revoke gateways are service-only'
);
SELECT ok(
  has_function_privilege('authenticated', 'public.current_client_project_completion(uuid)', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.current_client_project_completion(uuid)', 'EXECUTE') = false,
  'Client official completion gateway is authenticated-only'
);
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'current_staff_project_completion' $$, 'no staff completion gateway exists');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'current_project_manager_completion' $$, 'no Project Manager completion gateway exists');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'current_site_supervisor_completion' $$, 'no Site Supervisor completion gateway exists');

SELECT throws_ok($$ SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004003', (SELECT id FROM app.projects WHERE name = 'Override Security Project'), 50, 'Client cannot request', transaction_timestamp()) $$, '42501', 'Privileged operation denied.', 'Client cannot request override');
SELECT throws_ok($$ SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004004', (SELECT id FROM app.projects WHERE name = 'Override Security Project'), 50, 'PM cannot request', transaction_timestamp()) $$, '42501', 'Privileged operation denied.', 'Project Manager cannot request override');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004004', true);
SELECT ok(pg_get_functiondef('public.current_account()'::regprocedure) NOT ILIKE '%project_manager%access_allowed%true%', 'public.current_account does not activate reserved roles');
SELECT is_empty($$ SELECT * FROM public.current_client_project_completion((SELECT id FROM app.projects WHERE name = 'Override Security Project')) $$, 'Project Manager cannot use Client completion read');

SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004001', (SELECT id FROM app.projects WHERE name = 'Override Security Project'), 44, 'Owner security request reason', transaction_timestamp());
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004003', true);
SELECT results_eq($$ SELECT calculated_completion_percent, official_completion_percent, is_overridden FROM public.current_client_project_completion((SELECT id FROM app.projects WHERE name = 'Override Security Project')) $$, $$ VALUES (0.00::numeric(5,2), 0.00::numeric(5,2), false) $$, 'pending request is hidden from Client and has no official effect');
SELECT * FROM public.server_owner_approve_project_completion_override('00000000-0000-0000-0000-000000004002', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Owner security request reason'));
SELECT results_eq($$ SELECT calculated_completion_percent, official_completion_percent, is_overridden FROM public.current_client_project_completion((SELECT id FROM app.projects WHERE name = 'Override Security Project')) $$, $$ VALUES (0.00::numeric(5,2), 44.00::numeric(5,2), true) $$, 'Client sees aggregate official completion only');
SELECT ok(
  pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%active_override_id%'
  AND pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%reason%'
  AND pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%created_by%'
  AND pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%approved_by%',
  'Client completion output excludes override private fields'
);
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action IN ('view_project_completion','view_project_completion_override') AND outcome = 'success'), 'successful reads create no activity entries');
SELECT hasnt_table('app', 'notifications', 'notifications remain absent');
SELECT hasnt_table('app', 'financial_transactions', 'financial objects remain absent');

SELECT * FROM finish();
ROLLBACK;
