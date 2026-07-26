BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(41);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000002601', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.26@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002602', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.26@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002603', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.client.26@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002604', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.26@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000002601', 'owner.26@example.test', 'Owner Twenty Six', decode('2626262626262626262626262626262626262626262626262626262626262626', 'hex'), 'req-26', 'corr-26');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002601', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES ('Contractor Test Company', 'Contractor Test', 'USD', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000002602', '00000000-0000-0000-0000-000000002602', 'client.26@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601')),
  ('10000000-0000-0000-0000-000000002603', '00000000-0000-0000-0000-000000002603', 'other.client.26@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601')),
  ('10000000-0000-0000-0000-000000002604', '00000000-0000-0000-0000-000000002604', 'pm.26@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000002602', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601')),
  ('10000000-0000-0000-0000-000000002603', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601')),
  ('10000000-0000-0000-0000-000000002604', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002601'));

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002601', 'Milestone Client A', NULL, 'client.a.26@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002601', 'Milestone Client B', NULL, 'client.b.26@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), '10000000-0000-0000-0000-000000002602', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client B'), '10000000-0000-0000-0000-000000002603', 1);

SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), 'Milestone Project One', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), 'Milestone Project Two', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), 'Milestone Project Three', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), 'Milestone Project Four', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), 'Milestone Project Five', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), 'Milestone Project Six', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.clients WHERE display_name = 'Milestone Client A'), 'Milestone Project Seven', 'USD');

SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Phase Alpha', NULL, DATE '2026-02-01', DATE '2026-03-31', true);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Hidden Milestone Phase', NULL, DATE '2026-04-01', DATE '2026-04-30', false);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Two'), 'Other Project Phase', NULL, DATE '2026-02-01', DATE '2026-03-31', true);

SELECT results_eq(
  $$ SELECT phase_id, is_active, completed_at, version_number FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), ' Standalone Milestone ', NULL, 'secret milestone description', DATE '2026-05-01', true, 'req', 'corr') $$,
  $$ VALUES (NULL::uuid, true, NULL::timestamptz, 1) $$,
  'Owner creates milestone without phase'
);
SELECT results_eq(
  $$ SELECT phase_id, is_active, version_number FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Phase Milestone', (SELECT id FROM app.project_phases WHERE name = 'Phase Alpha'), NULL, DATE '2026-02-15', true) $$,
  $$ VALUES ((SELECT id FROM app.project_phases WHERE name = 'Phase Alpha'), true, 1) $$,
  'Owner creates milestone with active same-Project phase'
);
SELECT lives_ok($$ SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Phase Milestone', NULL) $$, 'duplicate milestone names are allowed');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), ' ', NULL) $$, '23514', 'Invalid Project milestone.', 'blank milestone name rejected');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Wrong Phase', (SELECT id FROM app.project_phases WHERE name = 'Other Project Phase')) $$, '23514', 'Project milestone phase must belong to the same Project.', 'cross-Project phase rejected');
SELECT * FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_phases WHERE name = 'Other Project Phase'), 1);
SELECT throws_ok($$ SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Two'), 'Inactive Phase Milestone', (SELECT id FROM app.project_phases WHERE name = 'Other Project Phase')) $$, '23514', 'Project milestone requires an active phase.', 'inactive phase rejected during create');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Past Due', NULL, NULL, DATE '2025-12-31') $$, '23514', 'Project milestone due date must fit inside Project dates.', 'Project-bound due date validation works');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Phase Past Due', (SELECT id FROM app.project_phases WHERE name = 'Phase Alpha'), NULL, DATE '2026-04-01') $$, '23514', 'Project milestone due date must fit inside phase dates.', 'phase-bound due date validation works');
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone' AND phase_id IS NOT NULL), 1, 'Phase Milestone Updated', (SELECT id FROM app.project_phases WHERE name = 'Phase Alpha'), 'updated secret description', DATE '2026-02-20', false) $$,
  $$ VALUES (2) $$,
  'Owner update increments milestone version once'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 2, 'Phase Milestone Updated', (SELECT id FROM app.project_phases WHERE name = 'Phase Alpha'), 'updated secret description', DATE '2026-02-20', false) $$,
  $$ VALUES (2) $$,
  'no-change milestone update is deterministic'
);
SELECT throws_ok($$ SELECT * FROM public.server_update_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 1, 'Stale Milestone', NULL) $$, '40001', 'Project milestone version conflict.', 'stale milestone update rejected');
SELECT throws_ok($$ SELECT * FROM public.server_complete_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 2) $$, '23514', 'Project milestone completion is not allowed in this Project status.', 'completion denied outside ACTIVE or ON_HOLD');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 1, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 2, 'ACTIVE');
SELECT results_eq(
  $$ SELECT completed_at IS NOT NULL, version_number FROM public.server_complete_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 2) $$,
  $$ VALUES (true, 3) $$,
  'Owner completes active milestone'
);
SELECT throws_ok($$ SELECT * FROM public.server_complete_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 3) $$, '23514', 'Project milestone cannot be completed.', 'repeated completion rejected');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 3, 'Completed Edit', NULL) $$, '23514', 'Project milestone cannot be updated.', 'completed milestone update rejected');
SELECT results_eq(
  $$ SELECT is_active, completed_at IS NOT NULL, version_number FROM public.server_archive_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 3) $$,
  $$ VALUES (false, true, 4) $$,
  'archive preserves completed timestamp'
);
SELECT throws_ok($$ SELECT * FROM public.server_update_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Phase Milestone Updated'), 4, 'Inactive Edit', NULL) $$, '23514', 'Project milestone cannot be updated.', 'inactive milestone update rejected');
SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 'Hidden Phase Milestone', (SELECT id FROM app.project_phases WHERE name = 'Hidden Milestone Phase'), NULL, DATE '2026-04-10', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002602', true);
SELECT results_eq(
  $$ SELECT name FROM public.current_client_project_milestones((SELECT id FROM app.projects WHERE name = 'Milestone Project One')) ORDER BY name $$,
  $$ VALUES ('Phase Milestone'::text), ('Standalone Milestone'::text) $$,
  'Client reads own active visible milestones and not hidden-phase milestones'
);
SELECT is((SELECT count(*)::integer FROM public.current_client_project_milestone((SELECT id FROM app.project_milestones WHERE name = 'Hidden Phase Milestone'))), 0, 'Client cannot read milestone linked to hidden phase');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002603', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_project_milestones((SELECT id FROM app.projects WHERE name = 'Milestone Project One'))), 0, 'cross-Client Project manipulation returns no milestones');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002604', true);
SELECT results_eq($$ SELECT access_allowed, active_role_codes FROM public.current_account() $$, $$ VALUES (false, ARRAY[]::varchar(40)[]) $$, 'Project Manager remains unusable in current_account');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_staff_project_milestones', 'current_project_manager_project_milestones', 'current_site_supervisor_project_milestones') $$, 'no public staff milestone function exists');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002601', true);
SELECT results_eq(
  $$ SELECT new_client_id, version_number FROM public.server_change_project_client('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Three'), (SELECT id FROM app.clients WHERE display_name = 'Milestone Client B'), 1) $$,
  $$ VALUES ((SELECT id FROM app.clients WHERE display_name = 'Milestone Client B'), 2) $$,
  'Client reassignment succeeds before milestone history'
);
SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Seven'), 'Reassignment Guard Milestone', NULL);
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Seven'), (SELECT id FROM app.clients WHERE display_name = 'Milestone Client B'), 1) $$, '23514', 'Project Client cannot be changed after milestone history exists.', 'Client reassignment fails after active milestone history');
SELECT * FROM public.server_archive_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Standalone Milestone'), 1);
SELECT * FROM public.server_archive_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Reassignment Guard Milestone'), 1);
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Seven'), (SELECT id FROM app.clients WHERE display_name = 'Milestone Client B'), 1) $$, '23514', 'Project Client cannot be changed after milestone history exists.', 'Client reassignment remains blocked after inactive milestone history');
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Four'), 'Archive Block Phase', NULL);
SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Four'), 'Archive Block Milestone', (SELECT id FROM app.project_phases WHERE name = 'Archive Block Phase'));
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_phases WHERE name = 'Archive Block Phase'), 1) $$, '23514', 'Project phase cannot be archived while active milestones reference it.', 'phase archive blocked by active milestone');
SELECT * FROM public.server_archive_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Archive Block Milestone'), 1);
SELECT results_eq(
  $$ SELECT is_active FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_phases WHERE name = 'Archive Block Phase'), 1) $$,
  $$ VALUES (false) $$,
  'phase archive succeeds after milestone archive'
);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Five'), 'Project Archive Phase', NULL);
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Five'), 1, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Five'), 2, 'ACTIVE');
SELECT * FROM public.server_complete_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Five'), 3);
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Five'), 4) $$, '23514', 'Project cannot be archived while active phases exist.', 'Project archive blocked by active phase');
SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Six'), 'Project Archive Milestone', NULL);
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Six'), 1, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Six'), 2, 'ACTIVE');
SELECT * FROM public.server_complete_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Six'), 3);
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Six'), 4) $$, '23514', 'Project cannot be archived while active milestones exist.', 'Project archive blocked by active milestone');
SELECT * FROM public.server_archive_project_milestone('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_milestones WHERE name = 'Project Archive Milestone'), 1);
SELECT results_eq(
  $$ SELECT status FROM public.server_archive_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project Six'), 4) $$,
  $$ VALUES ('ARCHIVED'::text) $$,
  'Project archive succeeds after active children are archived'
);
SELECT throws_ok($$ SELECT * FROM public.server_update_project_record('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.projects WHERE name = 'Milestone Project One'), 3, 'Milestone Project One', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-02-01') $$, '23514', 'Project dates cannot exclude existing phase history.', 'Project date reduction blocked by phase history');
SELECT is((SELECT version_number FROM app.projects WHERE name = 'Milestone Project One'), 3, 'Project guard rejection does not increment version');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_phase('00000000-0000-0000-0000-000000002601', (SELECT id FROM app.project_phases WHERE name = 'Phase Alpha'), 1, 'Phase Alpha', NULL, DATE '2026-02-01', DATE '2026-02-10', true) $$, '23514', 'Project phase dates cannot exclude existing milestone history.', 'phase date reduction blocked by milestone history');
SELECT is((SELECT version_number FROM app.project_phases WHERE name = 'Phase Alpha'), 1, 'phase guard rejection does not increment version');
SELECT throws_ok($$ DELETE FROM app.project_milestones WHERE name = 'Phase Milestone Updated' $$, '23514', 'Project milestones cannot be deleted.', 'hard delete rejected');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_milestone_created'), 7, 'milestone create activity logs written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_milestone_updated'), 1, 'milestone update activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_milestone_completed'), 1, 'milestone complete activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_milestone_archived'), 5, 'milestone archive activity logs written');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM app.activity_logs
  WHERE action LIKE 'project_milestone_%'
    AND (
      previous_values::text LIKE '%secret milestone description%'
      OR new_values::text LIKE '%secret milestone description%'
      OR metadata::text LIKE '%client.a.26@example.test%'
      OR metadata::text LIKE '%00000000-0000-0000-0000-000000002601%'
    )
), 'milestone activity metadata masks descriptions, Auth subjects and Client identity');
SELECT lives_ok($$ SELECT public.server_record_denied_privileged_operation('00000000-0000-0000-0000-000000002601', 'create_project_milestone', 'project_milestone', NULL, 'authorization_denied') $$, 'denied milestone action code is accepted');

SELECT * FROM finish();
ROLLBACK;
