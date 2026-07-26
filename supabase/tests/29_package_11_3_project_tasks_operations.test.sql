BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(39);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000002901', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.29@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002902', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.29@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002903', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.client.29@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000002904', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.29@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000002901', 'owner.29@example.test', 'Owner Twenty Nine', decode('2929292929292929292929292929292929292929292929292929292929292929', 'hex'), 'req-29', 'corr-29');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002901', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES ('Task Contractor Test Company', 'Task Contractor Test', 'USD', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000002902', '00000000-0000-0000-0000-000000002902', 'client.29@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901')),
  ('10000000-0000-0000-0000-000000002903', '00000000-0000-0000-0000-000000002903', 'other.client.29@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901')),
  ('10000000-0000-0000-0000-000000002904', '00000000-0000-0000-0000-000000002904', 'pm.29@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000002902', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901')),
  ('10000000-0000-0000-0000-000000002903', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901')),
  ('10000000-0000-0000-0000-000000002904', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'));

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002901', 'Task Client A', NULL, 'client.a.29@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000002901', 'Task Client B', NULL, 'client.b.29@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.clients WHERE display_name = 'Task Client A'), '10000000-0000-0000-0000-000000002902', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.clients WHERE display_name = 'Task Client B'), '10000000-0000-0000-0000-000000002903', 1);

SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.clients WHERE display_name = 'Task Client A'), 'Task Project One', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.clients WHERE display_name = 'Task Client A'), 'Task Project Two', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.clients WHERE display_name = 'Task Client B'), 'Task Project Other Client', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.clients WHERE display_name = 'Task Client A'), 'Task Project Archive Guard', 'USD');

SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Task Phase Visible', NULL, DATE '2026-02-01', DATE '2026-05-31', true);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Task Phase Hidden', NULL, DATE '2026-06-01', DATE '2026-07-31', false);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project Two'), 'Task Other Phase', NULL, DATE '2026-02-01', DATE '2026-05-31', true);
SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Task Milestone Visible', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Visible'), NULL, DATE '2026-03-01', true);
SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Task Milestone Hidden', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Hidden'), NULL, DATE '2026-06-15', true);

SELECT results_eq(
  $$ SELECT task_number, status, completion_percent, is_active, version_number FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), ' First Task ', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Visible'), (SELECT id FROM app.project_milestones WHERE name = 'Task Milestone Visible'), 'secret task description', 'client summary one', NULL, true, DATE '2026-02-05', DATE '2026-03-10', true, 'req-task', 'corr-task') $$,
  $$ VALUES ('TSK-0001'::text, 'TODO'::text, 0::numeric, true, 1) $$,
  'Owner creates first task with initial workflow state'
);
SELECT results_eq(
  $$ SELECT task_number FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Second Task') $$,
  $$ VALUES ('TSK-0002'::text) $$,
  'second task receives next Project-local number'
);
SELECT results_eq(
  $$ SELECT task_number FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project Two'), 'Other Project First Task') $$,
  $$ VALUES ('TSK-0001'::text) $$,
  'task numbering restarts independently per Project'
);
SELECT ok((SELECT count(*) FROM app.project_task_number_counters WHERE project_id IN (SELECT id FROM app.projects WHERE name IN ('Task Project One','Task Project Two'))) = 2, 'counter table tracks independent Projects');
SELECT throws_ok($$ INSERT INTO app.tasks (project_id, task_number, title, created_by, updated_by) VALUES ((SELECT id FROM app.projects WHERE name = 'Task Project One'), 'TSK-0001', 'Duplicate Task Number', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901')) $$, '23505', NULL, 'duplicate task number rejected within one Project');
SELECT lives_ok($$ INSERT INTO app.tasks (project_id, task_number, title, created_by, updated_by) VALUES ((SELECT id FROM app.projects WHERE name = 'Task Project Other Client'), 'TSK-0001', 'Same Local Number Different Project', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000002901')) $$, 'same task number is allowed in a different Project');
SELECT throws_ok($$ UPDATE app.tasks SET task_number = 'TSK-9999' WHERE title = 'First Task' $$, '23514', 'Project task identity fields are immutable.', 'task numbers are immutable');
SELECT lives_ok($$ SELECT app.generate_project_task_number((SELECT id FROM app.projects WHERE name = 'Task Project One')) $$, 'counter generator is callable only as trusted database support in tests');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'No Count Weighted', NULL, NULL, NULL, NULL, 10, false) $$, '23514', 'Project task weight is not allowed when completion counting is disabled.', 'non-null weight rejected when counting is disabled');
SELECT results_eq(
  $$ SELECT task_number FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'No Count Unweighted', NULL, NULL, NULL, NULL, NULL, false) $$,
  $$ VALUES ('TSK-0004'::text) $$,
  'null weight is accepted when counting is disabled'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.tasks WHERE title = 'First Task'), 1, 'First Task Updated', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Visible'), (SELECT id FROM app.project_milestones WHERE name = 'Task Milestone Visible'), 'secret task description updated', 'client summary updated', 25, true, DATE '2026-02-10', DATE '2026-03-15', true) $$,
  $$ VALUES (2) $$,
  'Owner structural update increments version once'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.tasks WHERE title = 'First Task Updated'), 2, 'First Task Updated', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Visible'), (SELECT id FROM app.project_milestones WHERE name = 'Task Milestone Visible'), 'secret task description updated', 'client summary updated', 25, true, DATE '2026-02-10', DATE '2026-03-15', true) $$,
  $$ VALUES (2) $$,
  'no-change structural update is deterministic'
);
SELECT throws_ok($$ SELECT * FROM public.server_update_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.tasks WHERE title = 'First Task Updated'), 1, 'Stale Task') $$, '40001', 'Project task version conflict.', 'stale task update rejected');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Cross Project Phase', (SELECT id FROM app.project_phases WHERE name = 'Task Other Phase')) $$, '23514', 'Project task phase must belong to the same Project.', 'cross-Project phase rejected safely');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Mismatched Milestone Phase', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Hidden'), (SELECT id FROM app.project_milestones WHERE name = 'Task Milestone Visible')) $$, '23514', 'Project task phase must match the milestone phase.', 'milestone phase compatibility enforced');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Project Date Outside', NULL, NULL, NULL, NULL, NULL, true, DATE '2025-12-31') $$, '23514', 'Project task dates must fit inside Project dates.', 'Project-bound task date validation works');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Phase Date Outside', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Visible'), NULL, NULL, NULL, NULL, true, NULL, DATE '2026-06-01', true) $$, '23514', 'Project task dates must fit inside Project phase dates.', 'phase-bound task date validation works');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Hidden Phase Task', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Hidden'), NULL, NULL, 'hidden phase task summary', NULL, true, DATE '2026-06-10', DATE '2026-06-20', true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 'Hidden Milestone Task', NULL, (SELECT id FROM app.project_milestones WHERE name = 'Task Milestone Hidden'), NULL, 'hidden milestone task summary');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002902', true);
SELECT results_eq(
  $$ SELECT title FROM public.current_client_project_tasks((SELECT id FROM app.projects WHERE name = 'Task Project One')) ORDER BY title $$,
  $$ VALUES ('First Task Updated'::text), ('No Count Unweighted'::text), ('Second Task'::text) $$,
  'Client reads only own active visible tasks without hidden phase or hidden milestone leakage'
);
SELECT is((SELECT count(*)::integer FROM public.current_client_project_task((SELECT id FROM app.tasks WHERE title = 'Hidden Phase Task'))), 0, 'Client cannot read task linked to hidden phase');
SELECT is((SELECT count(*)::integer FROM public.current_client_project_task((SELECT id FROM app.tasks WHERE title = 'Hidden Milestone Task'))), 0, 'Client cannot read task linked to hidden milestone phase');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002903', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_project_tasks((SELECT id FROM app.projects WHERE name = 'Task Project One'))), 0, 'cross-Client Project manipulation returns no tasks');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002904', true);
SELECT results_eq($$ SELECT access_allowed, active_role_codes FROM public.current_account() $$, $$ VALUES (false, ARRAY[]::varchar(40)[]) $$, 'Project Manager remains unusable in current_account');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002901', true);
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), (SELECT id FROM app.clients WHERE display_name = 'Task Client B'), 1) $$, '23514', 'Project Client cannot be changed after phase history exists.', 'Client reassignment still blocked before task guard by phase history when present');
SELECT throws_ok($$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project Other Client'), (SELECT id FROM app.clients WHERE display_name = 'Task Client A'), 1) $$, '23514', 'Project Client cannot be changed after task history exists.', 'Client reassignment blocked after task history');
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Visible'), 1) $$, '23514', 'Project phase cannot be archived while active milestones reference it.', 'phase archive existing milestone guard remains before task guard');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project Two'), 'Phase Only Guard Task', (SELECT id FROM app.project_phases WHERE name = 'Task Other Phase'));
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.project_phases WHERE name = 'Task Other Phase'), 1) $$, '23514', 'Project phase cannot be archived while active tasks reference it.', 'phase archive blocked by active task');
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_milestone('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.project_milestones WHERE name = 'Task Milestone Hidden'), 1) $$, '23514', 'Project milestone cannot be archived while active tasks reference it.', 'milestone archive blocked by active task');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_record('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.projects WHERE name = 'Task Project One'), 1, 'Task Project One', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-02-01') $$, '23514', 'Project dates cannot exclude existing phase history.', 'Project date guard preserves existing phase guard before task dates');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_phase('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.project_phases WHERE name = 'Task Phase Visible'), 1, 'Task Phase Visible', NULL, DATE '2026-02-01', DATE '2026-02-01', true) $$, '23514', 'Project phase dates cannot exclude existing milestone history.', 'phase date guard preserves milestone guard before task dates');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_milestone('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.project_milestones WHERE name = 'Task Milestone Visible'), 1, 'Task Milestone Visible', NULL, NULL, DATE '2026-03-01', true) $$, '23514', 'Project milestone phase cannot change while task history would become inconsistent.', 'milestone phase reassignment blocked by task history');
SELECT results_eq(
  $$ SELECT is_active, version_number FROM public.server_archive_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.tasks WHERE title = 'First Task Updated'), 2) $$,
  $$ VALUES (false, 3) $$,
  'Owner archives task and increments version once'
);
SELECT throws_ok($$ SELECT * FROM public.server_update_project_task('00000000-0000-0000-0000-000000002901', (SELECT id FROM app.tasks WHERE title = 'First Task Updated'), 3, 'Inactive Edit') $$, '23514', 'Project task cannot be updated.', 'inactive task update rejected');
SELECT throws_ok($$ DELETE FROM app.tasks WHERE title = 'First Task Updated' $$, '23514', 'Project tasks cannot be deleted.', 'task hard delete rejected');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('server_complete_project_task','server_change_project_task_status','server_update_project_task_progress')), 'no task workflow gateway exists in 11.3');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_task_created'), 7, 'task create activity logs written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_task_updated'), 1, 'task update activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_task_archived'), 1, 'task archive activity log written');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM app.activity_logs
  WHERE action LIKE 'project_task_%'
    AND (
      previous_values::text LIKE '%secret task description%'
      OR new_values::text LIKE '%secret task description%'
      OR metadata::text LIKE '%client.a.29@example.test%'
      OR metadata::text LIKE '%00000000-0000-0000-0000-000000002901%'
    )
), 'task activity metadata masks descriptions, Auth subjects and Client identity');
SELECT lives_ok($$ SELECT public.server_record_denied_privileged_operation('00000000-0000-0000-0000-000000002901', 'create_project_task', 'project_task', NULL, 'authorization_denied') $$, 'denied task action code is accepted');

SELECT * FROM finish();
ROLLBACK;
