BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(51);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000003501', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.35@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003502', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.35@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003503', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.35@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000003501', 'owner.35@example.test', 'Owner Thirty Five', decode('3535353535353535353535353535353535353535353535353535353535353535', 'hex'), 'req-35', 'corr-35');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003501', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES ('Task Workflow Contractor', 'Task Workflow Contractor', 'USD', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000003502', '00000000-0000-0000-0000-000000003502', 'pm.35@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501')),
  ('10000000-0000-0000-0000-000000003503', '00000000-0000-0000-0000-000000003503', 'client.35@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000003502', 'Project Manager Thirty Five', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000003502', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501')),
  ('10000000-0000-0000-0000-000000003503', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003501'));

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000003501', 'Workflow Client', NULL, 'client.35a@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.clients WHERE display_name = 'Workflow Client'), '10000000-0000-0000-0000-000000003503', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.clients WHERE display_name = 'Workflow Client'), 'Workflow Project', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.projects WHERE name = 'Workflow Project'), 1, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.projects WHERE name = 'Workflow Project'), 2, 'ACTIVE');
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.projects WHERE name = 'Workflow Project'), 'Workflow Task', NULL, NULL, NULL, NULL, 20, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.projects WHERE name = 'Workflow Project'), 'Blocked Completion Task', NULL, NULL, NULL, NULL, 20, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.projects WHERE name = 'Workflow Project'), 'Cancel Todo Task', NULL, NULL, NULL, NULL, 20, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.projects WHERE name = 'Workflow Project'), 'Assignment Guard Task', NULL, NULL, NULL, NULL, 20, true);
SELECT * FROM public.server_create_project_staff_assignment('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.projects WHERE name = 'Workflow Project'), '10000000-0000-0000-0000-000000003502', 'project_manager');
SELECT * FROM public.server_assign_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), (SELECT id FROM app.project_staff_assignments WHERE user_id = '10000000-0000-0000-0000-000000003502'));

SELECT throws_ok($$ UPDATE app.tasks SET status = 'IN_PROGRESS' WHERE title = 'Workflow Task' $$, '23514', 'Project task workflow fields require trusted functions.', 'direct task status update is blocked');
SELECT results_eq($$ SELECT status, completion_percent, version_number FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 1, 'IN_PROGRESS') $$, $$ VALUES ('IN_PROGRESS'::text, 0::numeric, 2) $$, 'TODO to IN_PROGRESS transition succeeds');
SELECT throws_ok($$ SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 2, 'IN_PROGRESS') $$, '23514', 'Project task status is unchanged.', 'same-status transition rejected');
SELECT results_eq($$ SELECT completion_percent, version_number FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 2, 25.50, 'progress note redacted') $$, $$ VALUES (25.50::numeric, 3) $$, 'progress can increase with fractional value');
SELECT results_eq($$ SELECT completion_percent, version_number FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 3, 10.25) $$, $$ VALUES (10.25::numeric, 4) $$, 'progress can decrease as audited correction');
SELECT results_eq($$ SELECT completion_percent, version_number FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 4, 0) $$, $$ VALUES (0::numeric, 5) $$, 'zero progress is accepted');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 5, 100) $$, '23514', 'Invalid Project task progress update.', '100 rejected by progress-only operation');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 5, -1) $$, '23514', 'Invalid Project task progress update.', 'negative progress rejected');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 5, 101) $$, '23514', 'Invalid Project task progress update.', 'greater-than-100 progress rejected');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 5, 0) $$, '23514', 'Project task progress is unchanged.', 'no-change progress rejected');
SELECT results_eq($$ SELECT status, version_number FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 5, 'BLOCKED') $$, $$ VALUES ('BLOCKED'::text, 6) $$, 'IN_PROGRESS to BLOCKED succeeds');
SELECT results_eq($$ SELECT status, version_number FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 6, 'IN_PROGRESS') $$, $$ VALUES ('IN_PROGRESS'::text, 7) $$, 'BLOCKED to IN_PROGRESS succeeds');
SELECT results_eq($$ SELECT status, completion_percent, completed_at IS NOT NULL, version_number FROM public.server_complete_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 7) $$, $$ VALUES ('COMPLETED'::text, 100::numeric, true, 8) $$, 'IN_PROGRESS completion sets 100 and trusted timestamp');
SELECT throws_ok($$ SELECT * FROM public.server_complete_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 8) $$, '23514', 'Project task cannot be completed.', 'repeated completion rejected');
SELECT results_eq($$ SELECT status, completion_percent, completed_at IS NULL, version_number FROM public.server_reopen_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 8, 80, 'Need correction') $$, $$ VALUES ('IN_PROGRESS'::text, 80::numeric, true, 9) $$, 'completed task reopens with required reason');
SELECT throws_ok($$ SELECT * FROM public.server_reopen_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 9, 50, ' ') $$, '23514', 'Invalid Project task reopening.', 'reopening requires reason');
SELECT results_eq($$ SELECT status, completion_percent, version_number FROM public.server_cancel_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 9, 'Cancelled after review') $$, $$ VALUES ('CANCELLED'::text, 80::numeric, 10) $$, 'cancellation preserves completion percentage');
SELECT throws_ok($$ SELECT * FROM public.server_reopen_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Workflow Task'), 10, 20, 'Cannot reopen cancelled') $$, '23514', 'Project task cannot be reopened.', 'cancelled task is terminal');
SELECT throws_ok($$ SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Cancel Todo Task'), 1, 'COMPLETED') $$, '23514', 'Project task status transition is not allowed.', 'TODO to COMPLETED rejected');
SELECT results_eq($$ SELECT status FROM public.server_cancel_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Cancel Todo Task'), 1, 'Cancel from TODO') $$, $$ VALUES ('CANCELLED'::text) $$, 'cancellation from TODO succeeds');
SELECT throws_ok($$ SELECT * FROM public.server_cancel_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Blocked Completion Task'), 1, ' ') $$, '23514', 'Invalid Project task cancellation.', 'cancellation requires reason');
SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Blocked Completion Task'), 1, 'BLOCKED');
SELECT results_eq($$ SELECT status, completion_percent FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Blocked Completion Task'), 2, 40) $$, $$ VALUES ('BLOCKED'::text, 40::numeric) $$, 'progress update while BLOCKED succeeds');
SELECT results_eq($$ SELECT status, completion_percent FROM public.server_complete_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Blocked Completion Task'), 3) $$, $$ VALUES ('COMPLETED'::text, 100::numeric) $$, 'BLOCKED completion succeeds');
SELECT throws_ok($$ SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Blocked Completion Task'), 4, 'TODO') $$, '23514', 'Project task status transition is not allowed.', 'COMPLETED ordinary transition rejected');
SELECT throws_ok($$ SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), 1, 'COMPLETED') $$, '23514', 'Project task status transition is not allowed.', 'generic status function cannot complete');
SELECT throws_ok($$ SELECT * FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), 1, 10) $$, '23514', 'Project task progress cannot be updated.', 'progress rejected for TODO');
SELECT throws_ok($$ SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), 99, 'IN_PROGRESS') $$, '40001', 'Project task version conflict.', 'stale task version rejected');
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), 1) $$, '23514', 'Project task archival requires a terminal task status.', 'archive rejects non-terminal tasks');
SELECT * FROM public.server_cancel_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), 1, 'Terminal archive fixture');
SELECT throws_ok($$ SELECT * FROM public.server_archive_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), 2) $$, '23514', 'Project task cannot be archived while active assignments exist.', 'active-assignment archive guard remains');
SELECT * FROM public.server_remove_project_task_assignment('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.task_assignments WHERE task_id = (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task') AND is_active));
SELECT results_eq($$ SELECT is_active FROM public.server_archive_project_task('00000000-0000-0000-0000-000000003501', (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task'), 2) $$, $$ VALUES (false) $$, 'terminal task archives after active assignments are removed');
SELECT ok((SELECT count(*) FROM app.task_updates WHERE task_id = (SELECT id FROM app.tasks WHERE title = 'Assignment Guard Task')) = 1, 'task-update history remains after task archival');
SELECT throws_ok($$ UPDATE app.task_updates SET update_note = 'tamper' $$, '23514', 'Project task update history is append-only.', 'task update rows cannot be updated');
SELECT throws_ok($$ DELETE FROM app.task_updates WHERE true $$, '23514', 'Project task update history is append-only.', 'task update rows cannot be deleted');
SELECT throws_ok($$ TRUNCATE app.task_updates $$, '23514', 'Project task update history is append-only.', 'task update rows cannot be truncated');
SELECT is((SELECT count(*)::integer FROM app.task_updates), 14, 'one task-update row is inserted for each successful workflow mutation');
SELECT ok(EXISTS (
  SELECT 1
  FROM app.task_updates AS tu
  INNER JOIN app.tasks AS t ON t.id = tu.task_id
  WHERE t.title = 'Workflow Task'
    AND tu.new_status = t.status
    AND tu.new_completion_percent = t.completion_percent
), 'history contains the committed current state for the workflow task');
SELECT is((SELECT version_number FROM app.tasks WHERE title = 'Assignment Guard Task'), 3, 'task version increments only for workflow and archive mutations');
SELECT is((SELECT count(*)::integer FROM app.task_assignments WHERE task_id = (SELECT id FROM app.tasks WHERE title = 'Workflow Task')), 0, 'task assignments unchanged by workflow operations');
SELECT is((SELECT count(*)::integer FROM app.project_milestones WHERE completed_at IS NOT NULL), 0, 'workflow does not complete milestones automatically');
SELECT is((SELECT count(*)::integer FROM app.projects WHERE status = 'COMPLETED'), 0, 'workflow does not complete Projects automatically');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003503', true);
SELECT results_eq($$ SELECT status, completion_percent FROM public.current_client_project_task((SELECT id FROM app.tasks WHERE title = 'Workflow Task')) $$, $$ VALUES ('CANCELLED'::text, 80::numeric) $$, 'Client-safe current task read shows current state');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'current_client_task_updates'), 'Client has no task update history RPC');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003502', true);
SELECT results_eq($$ SELECT access_allowed, active_role_codes FROM public.current_account() $$, $$ VALUES (false, ARRAY[]::varchar(40)[]) $$, 'Project Manager remains denied by current_account');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003501', true);
SELECT lives_ok($$ SELECT public.server_record_denied_privileged_operation('00000000-0000-0000-0000-000000003501', 'complete_project_task', 'project_task', NULL, 'authorization_denied') $$, 'denied task workflow action code is accepted');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM app.activity_logs
  WHERE action IN ('project_task_progress_updated','project_task_status_changed','project_task_completed','project_task_reopened','project_task_cancelled')
    AND (metadata::text LIKE '%progress note redacted%' OR metadata::text LIKE '%Need correction%' OR metadata::text LIKE '%Cancelled after review%' OR metadata::text LIKE '%owner.35@example.test%' OR metadata::text LIKE '%client.35@example.test%')
), 'task workflow activity metadata masks notes, emails and Client identity');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_task_progress_updated'), 'progress activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_task_status_changed'), 'status-change activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_task_completed'), 'completion activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_task_reopened'), 'reopen activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_task_cancelled'), 'cancellation activity logged');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('financial_transactions','ledger_entries','documents')), 'finance and documents remain absent');

SELECT * FROM finish();
ROLLBACK;
