BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(35);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000002301', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.23@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002302', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.23@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002303', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.client.23@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002304', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.23@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000002301', 'owner.23@example.test', 'Owner Twenty Three', decode('2323232323232323232323232323232323232323232323232323232323232323', 'hex'), 'req-23', 'corr-23');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002301', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES ('Contractor Test Company', 'Contractor Test', 'USD', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000002302', '00000000-0000-0000-0000-000000002302', 'client.23@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301')),
  ('10000000-0000-0000-0000-000000002303', '00000000-0000-0000-0000-000000002303', 'other.client.23@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301')),
  ('10000000-0000-0000-0000-000000002304', '00000000-0000-0000-0000-000000002304', 'pm.23@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000002302', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301')),
  ('10000000-0000-0000-0000-000000002303', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301')),
  ('10000000-0000-0000-0000-000000002304', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002301'));

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002301', 'Phase Client A', NULL, 'client.a.23@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002301', 'Phase Client B', NULL, 'client.b.23@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.clients WHERE display_name = 'Phase Client A'), '10000000-0000-0000-0000-000000002302', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.clients WHERE display_name = 'Phase Client B'), '10000000-0000-0000-0000-000000002303', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.clients WHERE display_name = 'Phase Client A'), 'Phase Project One', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.clients WHERE display_name = 'Phase Client A'), 'Phase Project Two', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.clients WHERE display_name = 'Phase Client A'), 'Phase Project Three', 'USD');

SELECT results_eq(
  $$ SELECT sequence_no, is_active, version_number FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), ' Phase A ', 'secret description', DATE '2026-01-02', DATE '2026-02-01', true, NULL, 'req', 'corr') $$,
  $$ VALUES (1, true, 1) $$,
  'Owner appends first phase'
);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), 'Phase B', NULL, DATE '2026-03-01', DATE '2026-04-01', true);
SELECT results_eq(
  $$ SELECT name, sequence_no FROM app.project_phases WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Phase Project One') ORDER BY sequence_no $$,
  $$ VALUES ('Phase A'::varchar(160), 1), ('Phase B'::varchar(160), 2) $$,
  'append creates contiguous ordering'
);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), 'Phase Insert', NULL, NULL, NULL, true, 2);
SELECT results_eq(
  $$ SELECT name, sequence_no, version_number FROM app.project_phases WHERE name = 'Phase Insert' $$,
  $$ VALUES ('Phase Insert'::varchar(160), 2, 1) $$,
  'Owner inserts phase at approved position'
);
SELECT results_eq(
  $$ SELECT name, sequence_no FROM app.project_phases WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Phase Project One') ORDER BY sequence_no $$,
  $$ VALUES ('Phase A'::varchar(160), 1), ('Phase Insert'::varchar(160), 2), ('Phase B'::varchar(160), 3) $$,
  'insert shifts later phases atomically'
);
SELECT is((SELECT version_number FROM app.project_phases WHERE name = 'Phase B'), 2, 'shifted phase version incremented once');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), 'Bad Dates', NULL, DATE '2025-12-01', NULL, true) $$, '23514', 'Project phase dates must fit inside Project dates.', 'Project-bound start date validation works');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), 'Bad Position', NULL, NULL, NULL, true, 99) $$, '23514', 'Invalid Project phase insertion position.', 'invalid insertion position rejected');
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.project_phases WHERE name = 'Phase Insert'), 1, 'Phase Insert Updated', 'updated secret description', NULL, NULL, false) $$,
  $$ VALUES (2) $$,
  'Owner update increments phase version once'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.project_phases WHERE name = 'Phase Insert Updated'), 2, 'Phase Insert Updated', 'updated secret description', NULL, NULL, false) $$,
  $$ VALUES (2) $$,
  'no-change update is deterministic'
);
SELECT throws_ok($$ SELECT * FROM public.server_update_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.project_phases WHERE name = 'Phase Insert Updated'), 1, 'Stale', NULL, NULL, NULL, true) $$, '40001', 'Project phase version conflict.', 'stale update rejected');
SELECT throws_ok($$ SELECT * FROM public.server_reorder_project_phases('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), ARRAY[(SELECT id FROM app.project_phases WHERE name = 'Phase B')], ARRAY[2]) $$, '23514', 'Invalid Project phase order.', 'reorder requires every active phase');
SELECT results_eq(
  $$ SELECT reordered_count FROM public.server_reorder_project_phases(
       '00000000-0000-0000-0000-000000002301',
       (SELECT id FROM app.projects WHERE name = 'Phase Project One'),
       ARRAY[(SELECT id FROM app.project_phases WHERE name = 'Phase B'), (SELECT id FROM app.project_phases WHERE name = 'Phase A'), (SELECT id FROM app.project_phases WHERE name = 'Phase Insert Updated')],
       ARRAY[(SELECT version_number FROM app.project_phases WHERE name = 'Phase B'), (SELECT version_number FROM app.project_phases WHERE name = 'Phase A'), (SELECT version_number FROM app.project_phases WHERE name = 'Phase Insert Updated')]
     ) $$,
  $$ VALUES (3) $$,
  'Owner reorders active phases'
);
SELECT results_eq(
  $$ SELECT name, sequence_no FROM app.project_phases WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Phase Project One') ORDER BY sequence_no $$,
  $$ VALUES ('Phase B'::varchar(160), 1), ('Phase A'::varchar(160), 2), ('Phase Insert Updated'::varchar(160), 3) $$,
  'reorder produces requested contiguous order'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_reorder_project_phases(
       '00000000-0000-0000-0000-000000002301',
       (SELECT id FROM app.projects WHERE name = 'Phase Project One'),
       ARRAY[(SELECT id FROM app.project_phases WHERE name = 'Phase B'), (SELECT id FROM app.project_phases WHERE name = 'Phase A'), (SELECT id FROM app.project_phases WHERE name = 'Phase Insert Updated')],
       ARRAY[1,1,1]
     ) $$,
  '40001',
  'Project phase order version conflict.',
  'stale reorder rejected before persistent change'
);
SELECT results_eq(
  $$ SELECT sequence_no, is_active FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.project_phases WHERE name = 'Phase A'), (SELECT version_number FROM app.project_phases WHERE name = 'Phase A')) $$,
  $$ VALUES (3, false) $$,
  'Owner archives active phase to end'
);
SELECT results_eq(
  $$ SELECT name, sequence_no, is_active FROM app.project_phases WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Phase Project One') ORDER BY sequence_no $$,
  $$ VALUES ('Phase B'::varchar(160), 1, true), ('Phase Insert Updated'::varchar(160), 2, true), ('Phase A'::varchar(160), 3, false) $$,
  'archive closes active gap and keeps inactive after active'
);
SELECT throws_ok($$ SELECT * FROM public.server_update_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.project_phases WHERE name = 'Phase A'), (SELECT version_number FROM app.project_phases WHERE name = 'Phase A'), 'Nope', NULL, NULL, NULL, true) $$, '23514', 'Project phase cannot be updated.', 'inactive phase update rejected');
SELECT throws_ok($$ UPDATE app.project_phases SET name = 'Direct Nope' WHERE name = 'Phase A' $$, '23514', 'Inactive Project phase content is immutable.', 'inactive content immutable');
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), 'Hidden Phase', NULL, NULL, NULL, false);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002302', true);
SELECT results_eq(
  $$ SELECT name, sequence_no FROM public.current_client_project_phases((SELECT id FROM app.projects WHERE name = 'Phase Project One')) ORDER BY sequence_no $$,
  $$ VALUES ('Phase B'::text, 1) $$,
  'Client reads own active visible phases only'
);
SELECT is((SELECT count(*)::integer FROM public.current_client_project_phase((SELECT id FROM app.project_phases WHERE name = 'Hidden Phase'))), 0, 'Client cannot read hidden phase detail');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002303', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_project_phases((SELECT id FROM app.projects WHERE name = 'Phase Project One'))), 0, 'cross-Client Project manipulation returns no phases');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002304', true);
SELECT results_eq($$ SELECT access_allowed, active_role_codes FROM public.current_account() $$, $$ VALUES (false, ARRAY[]::varchar(40)[]) $$, 'Project Manager remains unusable in current_account');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_staff_project_phases', 'current_project_manager_project_phases', 'current_site_supervisor_project_phases') $$, 'no public staff phase function exists');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002301', true);
SELECT results_eq(
  $$ SELECT new_client_id, version_number FROM public.server_change_project_client('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project Three'), (SELECT id FROM app.clients WHERE display_name = 'Phase Client B'), 1) $$,
  $$ VALUES ((SELECT id FROM app.clients WHERE display_name = 'Phase Client B'), 2) $$,
  'Client reassignment succeeds before phase history'
);
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), (SELECT id FROM app.clients WHERE display_name = 'Phase Client B'), 1) $$, '23514', 'Project Client cannot be changed after phase history exists.', 'Client reassignment fails after active phase history');
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project One'), (SELECT id FROM app.clients WHERE display_name = 'Phase Client B'), 1) $$, '23514', 'Project Client cannot be changed after phase history exists.', 'Client reassignment remains blocked after inactive phase history');
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project Two'), 'Closeout Phase', NULL);
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project Two'), 1, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project Two'), 2, 'ACTIVE');
SELECT * FROM public.server_complete_project_record('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project Two'), 3);
SELECT results_eq(
  $$ SELECT is_active FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.project_phases WHERE name = 'Closeout Phase'), 1) $$,
  $$ VALUES (false) $$,
  'phase archive allowed during completed closeout'
);
SELECT * FROM public.server_archive_project_record('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project Two'), 4);
SELECT throws_ok($$ SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002301', (SELECT id FROM app.projects WHERE name = 'Phase Project Two'), 'No Archived Project Phase', NULL) $$, '23514', 'Project phase changes are not allowed in this Project status.', 'phase create denied for archived Project');
SELECT throws_ok($$ DELETE FROM app.project_phases WHERE name = 'Phase B' $$, '23514', 'Project phases cannot be deleted.', 'hard delete rejected');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_phase_created'), 5, 'phase create activity logs written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_phase_updated'), 1, 'phase update activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_phases_reordered'), 1, 'phase reorder activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_phase_archived'), 2, 'phase archive activity logs written');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM app.activity_logs
  WHERE action LIKE 'project_phase_%'
    AND (
      previous_values::text LIKE '%secret description%'
      OR new_values::text LIKE '%secret description%'
      OR previous_values::text LIKE '%client.a.23@example.test%'
      OR new_values::text LIKE '%client.a.23@example.test%'
      OR metadata::text LIKE '%00000000-0000-0000-0000-000000002301%'
    )
), 'phase activity metadata masks descriptions, Auth subjects and Client identity');
SELECT lives_ok($$ SELECT public.server_record_denied_privileged_operation('00000000-0000-0000-0000-000000002301', 'create_project_phase', 'project_phase', NULL, 'authorization_denied') $$, 'denied phase action code is accepted');

SELECT * FROM finish();
ROLLBACK;
