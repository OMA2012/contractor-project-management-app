BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(32);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000002001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.20@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.20@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'supervisor.20@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.20@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.20@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inactive.pm.20@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000002001', 'owner.20@example.test', 'Owner Twenty', decode('2020202020202020202020202020202020202020202020202020202020202020', 'hex'), 'req-20', 'corr-20');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002001', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES ('Contractor Test Company', 'Contractor Test', 'USD', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000002002', '00000000-0000-0000-0000-000000002002', 'pm.20@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002003', '00000000-0000-0000-0000-000000002003', 'supervisor.20@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002004', '00000000-0000-0000-0000-000000002004', 'accountant.20@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002005', '00000000-0000-0000-0000-000000002005', 'client.20@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002006', '00000000-0000-0000-0000-000000002006', 'inactive.pm.20@example.test', 'STAFF', 'SUSPENDED', false, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000002002', 'Project Manager Twenty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002003', 'Site Supervisor Twenty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002004', 'Accountant Twenty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002006', 'Inactive PM Twenty', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000002002', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002003', 'site_supervisor', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002004', 'accountant', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002005', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001')),
  ('10000000-0000-0000-0000-000000002006', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'));

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002001', 'Client A 20', NULL, 'client.a.20@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002001', 'Client B 20', NULL, 'client.b.20@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.clients WHERE display_name = 'Client A 20'), '10000000-0000-0000-0000-000000002005', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.clients WHERE display_name = 'Client A 20'), 'Project Assignment One', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.clients WHERE display_name = 'Client A 20'), 'Project Assignment Two', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.clients WHERE display_name = 'Client A 20'), 'Project Assignment Three', 'USD');

SELECT results_eq(
  $$ SELECT new_client_id, version_number FROM public.server_change_project_client('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Three'), (SELECT id FROM app.clients WHERE display_name = 'Client B 20'), 1) $$,
  $$ VALUES ((SELECT id FROM app.clients WHERE display_name = 'Client B 20'), 2) $$,
  'Client reassignment succeeds before assignment history'
);
SELECT results_eq(
  $$ SELECT assignment_role_code, status FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), '10000000-0000-0000-0000-000000002002', 'project_manager', 'sensitive assignment notes', 'req', 'corr') $$,
  $$ VALUES ('project_manager'::text, 'ACTIVE'::text) $$,
  'Owner creates active Project Manager assignment'
);
SELECT ok(app.has_active_project_assignment('10000000-0000-0000-0000-000000002002', (SELECT id FROM app.projects WHERE name = 'Project Assignment One')), 'helper true after assignment');
SELECT ok(app.has_active_project_assignment_role('10000000-0000-0000-0000-000000002002', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), 'project_manager'), 'role helper true for matching assignment');
SELECT throws_ok(
  $$ SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), '10000000-0000-0000-0000-000000002002', 'project_manager') $$,
  '23505',
  'Project staff assignment already exists.',
  'duplicate active assignment rejected deterministically'
);
SELECT results_eq(
  $$ SELECT count(*)::integer FROM public.server_owner_project_staff_assignment_list('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), true) $$,
  $$ VALUES (1) $$,
  'Owner lists Project assignment'
);
SELECT results_eq(
  $$ SELECT staff_full_name, notes FROM public.server_owner_project_staff_assignment_detail('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.project_staff_assignments WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Project Assignment One') AND status = 'ACTIVE')) $$,
  $$ VALUES ('Project Manager Twenty'::text, 'sensitive assignment notes'::text) $$,
  'Owner detail includes staff name and notes'
);
SELECT results_eq(
  $$ SELECT role_code FROM public.server_owner_eligible_project_staff_list('00000000-0000-0000-0000-000000002001', NULL, 500, -1) ORDER BY role_code $$,
  $$ VALUES ('project_manager'::text), ('site_supervisor'::text) $$,
  'eligible staff list returns active PM and supervisor only'
);
SELECT throws_ok($$ SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), '10000000-0000-0000-0000-000000002005', 'project_manager') $$, '42501', 'Privileged operation denied.', 'Client target denied');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), 'project_manager') $$, '42501', 'Privileged operation denied.', 'Owner/self target denied');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), '10000000-0000-0000-0000-000000002004', 'accountant') $$, '23514', 'Project staff assignment role is not allowed.', 'Accountant assignment role denied');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), '10000000-0000-0000-0000-000000002006', 'project_manager') $$, '42501', 'Privileged operation denied.', 'inactive staff target denied');
SELECT results_eq(
  $$ SELECT status FROM public.server_remove_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.project_staff_assignments WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Project Assignment One') AND status = 'ACTIVE')) $$,
  $$ VALUES ('REMOVED'::text) $$,
  'Owner removes active assignment'
);
SELECT ok(NOT app.has_active_project_assignment('10000000-0000-0000-0000-000000002002', (SELECT id FROM app.projects WHERE name = 'Project Assignment One')), 'helper false after removal');
SELECT throws_ok($$ SELECT * FROM public.server_remove_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.project_staff_assignments WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Project Assignment One') AND status = 'REMOVED')) $$, '23514', 'Project staff assignment is already removed.', 'already removed rejected safely');
SELECT throws_ok($$ UPDATE app.project_staff_assignments SET notes = 'changed' WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Project Assignment One') $$, '23514', 'Removed Project staff assignments are immutable.', 'removed row immutable');
SELECT results_eq(
  $$ SELECT status FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), '10000000-0000-0000-0000-000000002002', 'project_manager') $$,
  $$ VALUES ('ACTIVE'::text) $$,
  'removed history does not prevent reassignment'
);
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), (SELECT id FROM app.clients WHERE display_name = 'Client B 20'), 1) $$, '23514', 'Project Client cannot be changed after staff assignment history exists.', 'Client reassignment blocked by active assignment history');
SELECT * FROM public.server_remove_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.project_staff_assignments WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Project Assignment One') AND status = 'ACTIVE'));
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), (SELECT id FROM app.clients WHERE display_name = 'Client B 20'), 1) $$, '23514', 'Project Client cannot be changed after staff assignment history exists.', 'Client reassignment remains blocked after removed history');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two'), 1, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two'), 2, 'ACTIVE');
SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two'), '10000000-0000-0000-0000-000000002003', 'site_supervisor');
SELECT * FROM public.server_complete_project_record('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two'), 3);
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_record('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two'), 4) $$, '23514', 'Project cannot be archived while active staff assignments exist.', 'archive blocked while active assignment exists');
SELECT * FROM public.server_remove_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.project_staff_assignments WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Project Assignment Two') AND status = 'ACTIVE'));
SELECT results_eq(
  $$ SELECT status FROM public.server_archive_project_record('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two'), 4) $$,
  $$ VALUES ('ARCHIVED'::text) $$,
  'archive succeeds after active assignments removed'
);
SELECT throws_ok($$ SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two'), '10000000-0000-0000-0000-000000002003', 'site_supervisor') $$, '23514', 'Project staff assignment is not allowed in this status.', 'invalid archived Project status denied');
SELECT ok(NOT app.has_active_project_assignment('10000000-0000-0000-0000-000000002003', (SELECT id FROM app.projects WHERE name = 'Project Assignment Two')), 'helper false after Project archive and removal');
SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000002001', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), '10000000-0000-0000-0000-000000002002', 'project_manager');
UPDATE app.users SET status = 'SUSPENDED', is_active = false WHERE id = '10000000-0000-0000-0000-000000002002';
SELECT ok(NOT app.has_active_project_assignment('10000000-0000-0000-0000-000000002002', (SELECT id FROM app.projects WHERE name = 'Project Assignment One')), 'helper false after user deactivation');
UPDATE app.users SET status = 'ACTIVE', is_active = true WHERE id = '10000000-0000-0000-0000-000000002002';
UPDATE app.user_roles SET is_active = false, revoked_at = now(), revoked_by = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002001'), revoke_reason = 'test revocation' WHERE user_id = '10000000-0000-0000-0000-000000002002' AND role_code = 'project_manager';
SELECT ok(NOT app.has_active_project_assignment_role('10000000-0000-0000-0000-000000002002', (SELECT id FROM app.projects WHERE name = 'Project Assignment One'), 'project_manager'), 'helper false after matching role removal');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002005', true);
SELECT ok(NOT EXISTS (SELECT 1 FROM public.current_client_project_records() AS p WHERE p.project_number IS NULL), 'Client Project read exposes no assignment fields');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002003', true);
SELECT results_eq($$ SELECT access_allowed, active_role_codes FROM public.current_account() $$, $$ VALUES (false, ARRAY[]::varchar(40)[]) $$, 'reserved role remains unusable in current_account');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_staff_project_records', 'current_project_manager_project_records', 'current_site_supervisor_project_records') $$, 'no public staff Project RPC exists');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002001', true);
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_staff_assignment_created'), 4, 'assignment create activity logs written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_staff_assignment_removed'), 3, 'assignment remove activity logs written');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM app.activity_logs
  WHERE action LIKE 'project_staff_assignment_%'
    AND (
      previous_values::text LIKE '%pm.20@example.test%'
      OR new_values::text LIKE '%pm.20@example.test%'
      OR previous_values::text LIKE '%sensitive assignment notes%'
      OR new_values::text LIKE '%sensitive assignment notes%'
      OR metadata::text LIKE '%client.a.20@example.test%'
    )
), 'assignment activity metadata masks staff email, notes and Client identity');
SELECT lives_ok($$ SELECT public.server_record_denied_privileged_operation('00000000-0000-0000-0000-000000002001', 'create_project_staff_assignment', 'project_staff_assignment', NULL, 'authorization_denied') $$, 'denied assignment action code is accepted');

SELECT * FROM finish();
ROLLBACK;
