BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(30);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000003201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.32@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003202', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.32@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003203', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'supervisor.32@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003204', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.32@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003205', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.32@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000003201', 'owner.32@example.test', 'Owner Thirty Two', decode('3232323232323232323232323232323232323232323232323232323232323232', 'hex'), 'req-32', 'corr-32');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES ('Task Assignment Contractor', 'Task Assignment Contractor', 'USD', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000003202', '00000000-0000-0000-0000-000000003202', 'pm.32@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003203', '00000000-0000-0000-0000-000000003203', 'supervisor.32@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003204', '00000000-0000-0000-0000-000000003204', 'accountant.32@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003205', '00000000-0000-0000-0000-000000003205', 'client.32@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000003202', 'Project Manager Thirty Two', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003203', 'Site Supervisor Thirty Two', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003204', 'Accountant Thirty Two', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000003202', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003203', 'site_supervisor', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003204', 'accountant', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201')),
  ('10000000-0000-0000-0000-000000003205', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003201'));

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000003201', 'Task Assignment Client', NULL, 'client.32a@example.test');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.clients WHERE display_name = 'Task Assignment Client'), 'Task Assignment Project', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.clients WHERE display_name = 'Task Assignment Client'), 'Task Assignment Other Project', 'USD');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'), 'Assignable Task', NULL, NULL, 'private description', 'client summary', 20, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Other Project'), 'Other Task', NULL, NULL, NULL, NULL, 20, true);
SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'), '10000000-0000-0000-0000-000000003202', 'project_manager');
SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'), '10000000-0000-0000-0000-000000003203', 'site_supervisor');
SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Other Project'), '10000000-0000-0000-0000-000000003203', 'site_supervisor');

SELECT results_eq(
  $$ SELECT is_active FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))) $$,
  $$ VALUES (true) $$,
  'Owner assigns Project Manager to task'
);
SELECT results_eq(
  $$ SELECT count(*)::integer FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003203' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))) $$,
  $$ VALUES (1) $$,
  'different active staff assignment can share one task'
);
SELECT is((SELECT count(*)::integer FROM app.task_assignments WHERE task_id = (SELECT id FROM app.tasks WHERE title = 'Assignable Task') AND is_active), 2, 'multiple active assignees are allowed');
SELECT throws_ok($$ SELECT * FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))) $$, '23505', 'Project task assignment already exists.', 'duplicate active same-pair assignment rejected');
SELECT throws_ok($$ SELECT * FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003203' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Other Project'))) $$, '42501', 'Privileged operation denied.', 'cross-Project task assignment rejected');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'), '10000000-0000-0000-0000-000000003204', 'accountant') $$, '23514', 'Project staff assignment role is not allowed.', 'accountant cannot become Project task assignee source');
SELECT lives_ok($$ SELECT * FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Other Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003203' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Other Project'))) $$, 'active task assignment created for Project archive guard');
SELECT results_eq(
  $$ SELECT is_active, removed_at IS NOT NULL FROM public.server_remove_project_task_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.task_assignments WHERE project_staff_assignment_id = (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project')) AND is_active)) $$,
  $$ VALUES (false, true) $$,
  'Owner removes task assignment with trusted timestamp'
);
SELECT throws_ok($$ SELECT * FROM public.server_remove_project_task_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.task_assignments WHERE project_staff_assignment_id = (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project')) AND NOT is_active)) $$, '23514', 'Project task assignment is already removed.', 'repeated removal rejected');
SELECT lives_ok($$ SELECT * FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))) $$, 'same pair can be assigned again after removal using new history row');
SELECT is((SELECT count(*)::integer FROM app.task_assignments WHERE project_staff_assignment_id = (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))), 2, 'new assignment creates a separate history row');
SELECT throws_ok($$ UPDATE app.task_assignments SET assigned_at = now() WHERE NOT is_active $$, '23514', 'Inactive Project task assignments are immutable.', 'inactive history immutable');
SELECT throws_ok($$ UPDATE app.task_assignments SET is_active = true, removed_at = NULL WHERE NOT is_active $$, '23514', 'Inactive Project task assignments are immutable.', 'reactivation blocked');
SELECT throws_ok($$ DELETE FROM app.task_assignments WHERE true $$, '23514', 'Project task assignments cannot be deleted.', 'hard delete blocked');
SELECT * FROM public.server_cancel_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), 1, 'Terminal archive fixture');
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), 2) $$, '23514', 'Project task cannot be archived while active assignments exist.', 'task archive blocked by active task assignments');
SELECT * FROM public.server_remove_project_task_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.task_assignments WHERE is_active AND project_staff_assignment_id = (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))));
SELECT * FROM public.server_remove_project_task_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.task_assignments WHERE is_active AND project_staff_assignment_id = (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003203' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))));
SELECT results_eq($$ SELECT is_active FROM public.server_archive_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), 2) $$, $$ VALUES (false) $$, 'task archive succeeds after active assignments are removed');
SELECT throws_ok($$ SELECT * FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Assignable Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003202' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'))) $$, '23514', 'Project task is not available for assignment.', 'inactive task cannot receive assignments');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Project'), 'Cascade Task', NULL, NULL, NULL, NULL, 20, true);
SELECT * FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.tasks WHERE title = 'Cascade Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003203' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project')));
SELECT results_eq($$ SELECT status FROM public.server_remove_project_staff_assignment('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003203' AND project_id = (SELECT id FROM app.projects WHERE name = 'Task Assignment Project') AND status = 'ACTIVE')) $$, $$ VALUES ('REMOVED'::text) $$, 'Project staff assignment removal succeeds');
SELECT is((SELECT count(*)::integer FROM app.task_assignments WHERE task_id = (SELECT id FROM app.tasks WHERE title = 'Cascade Task') AND is_active), 0, 'Project staff assignment removal deactivates child task assignments');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_task_assignment_removed' AND metadata->>'removal_cause' = 'project_access_removed'), 1, 'one child activity event is written for cascaded removal');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_staff_assignment_removed' AND (new_values->>'affected_active_assignment_count')::integer = 1), 'parent removal activity includes affected child count');
SELECT is((SELECT version_number FROM app.tasks WHERE title = 'Cascade Task'), 1, 'task version is unchanged by assignment removal cascade');
SELECT is((SELECT status::text FROM app.tasks WHERE title = 'Cascade Task'), 'TODO', 'task status is unchanged by assignment removal cascade');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003203', true);
SELECT results_eq($$ SELECT access_allowed, active_role_codes FROM public.current_account() $$, $$ VALUES (false, ARRAY[]::varchar(40)[]) $$, 'reserved role remains unusable');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_staff_task_assignments','current_assigned_tasks') $$, 'no public assigned-staff task RPC exists');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
SELECT * FROM public.server_cancel_project_record('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Other Project'), 1, 'Archive guard fixture cancellation');
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_record('00000000-0000-0000-0000-000000003201', (SELECT id FROM app.projects WHERE name = 'Task Assignment Other Project'), 2) $$, '23514', 'Project cannot be archived while active task assignments exist.', 'Project archive blocked by active task assignments');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_task_assigned'), 5, 'task assignment create activity logs written');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM app.activity_logs
  WHERE action LIKE 'project_task_assignment%'
    AND (
      previous_values::text LIKE '%pm.32@example.test%'
      OR new_values::text LIKE '%supervisor.32@example.test%'
      OR metadata::text LIKE '%00000000-0000-0000-0000-000000003202%'
      OR metadata::text LIKE '%client.32@example.test%'
    )
), 'task assignment activity masks emails, Auth subjects and Client identity');
SELECT has_table('app', 'task_updates', 'task updates are implemented in Package 11.5');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('notifications','financial_transactions','ledger_entries','documents')), 'notifications, finance and documents remain absent');

SELECT * FROM finish();
ROLLBACK;
