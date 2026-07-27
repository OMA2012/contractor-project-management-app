BEGIN;
SELECT plan(25);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000003801', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.38@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003802', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.38@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003803', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.client.38@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003804', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.38@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000003801', 'owner.38@example.test', 'Owner Thirty Eight', decode('3838383838383838383838383838383838383838383838383838383838383838', 'hex'), 'req-38', 'corr-38');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003801', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES ('Completion Contractor', 'Completion Contractor', 'USD', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000003802', '00000000-0000-0000-0000-000000003802', 'client.38@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801')),
  ('10000000-0000-0000-0000-000000003803', '00000000-0000-0000-0000-000000003803', 'other.client.38@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801')),
  ('10000000-0000-0000-0000-000000003804', '00000000-0000-0000-0000-000000003804', 'pm.38@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000003802', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'), true),
  ('10000000-0000-0000-0000-000000003803', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'), true),
  ('10000000-0000-0000-0000-000000003804', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000003801'), true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000003801', 'Completion Client', NULL, 'client.38a@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000003801', 'Completion Other Client', NULL, 'client.38b@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.clients WHERE display_name = 'Completion Client'), '10000000-0000-0000-0000-000000003802', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.clients WHERE display_name = 'Completion Other Client'), '10000000-0000-0000-0000-000000003803', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.clients WHERE display_name = 'Completion Client'), 'Completion Project', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.clients WHERE display_name = 'Completion Other Client'), 'Completion Other Project', 'USD', NULL, NULL, DATE '2026-01-01', DATE '2026-12-31');
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Visible Phase', NULL, DATE '2026-01-01', DATE '2026-06-30', true);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Hidden Phase', NULL, DATE '2026-07-01', DATE '2026-12-31', false);
SELECT * FROM public.server_create_project_phase('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Other Project'), 'Other Phase', NULL, DATE '2026-01-01', DATE '2026-12-31', true);

SELECT results_eq($$ SELECT app.calculate_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (0.00::numeric(5,2)) $$, 'no qualifying tasks returns 0.00');

SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Todo Weighted', (SELECT id FROM app.project_phases WHERE name = 'Visible Phase'), NULL, NULL, NULL, 20, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Progress Weighted', (SELECT id FROM app.project_phases WHERE name = 'Visible Phase'), NULL, NULL, NULL, 30, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Complete Weighted', (SELECT id FROM app.project_phases WHERE name = 'Hidden Phase'), NULL, NULL, NULL, 50, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'No Phase Weighted', NULL, NULL, NULL, NULL, 10, true);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Noncounting Task', NULL, NULL, NULL, NULL, NULL, false);
SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Cancelled Task', NULL, NULL, NULL, NULL, 40, true);

SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 1, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 2, 'ACTIVE');
SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Progress Weighted'), 1, 'IN_PROGRESS');
SELECT * FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Progress Weighted'), 2, 50);
SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Complete Weighted'), 1, 'IN_PROGRESS');
SELECT * FROM public.server_complete_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Complete Weighted'), 2);
SELECT * FROM public.server_change_project_task_status('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'No Phase Weighted'), 1, 'BLOCKED');
SELECT * FROM public.server_update_project_task_progress('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'No Phase Weighted'), 2, 25);
SELECT * FROM public.server_cancel_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Cancelled Task'), 1, 'No longer needed');

SELECT results_eq($$ SELECT app.calculate_project_phase_completion((SELECT id FROM app.project_phases WHERE name = 'Visible Phase')) $$, $$ VALUES (30.00::numeric(5,2)) $$, 'phase includes only tasks in requested phase');
SELECT results_eq($$ SELECT app.calculate_project_phase_completion((SELECT id FROM app.project_phases WHERE name = 'Hidden Phase')) $$, $$ VALUES (100.00::numeric(5,2)) $$, 'hidden phase calculates independently for trusted callers');
SELECT results_eq($$ SELECT app.calculate_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (61.36::numeric(5,2)) $$, 'Project includes all qualifying tasks including no-phase and hidden tasks');
SELECT results_eq($$ SELECT calculated_completion_percent, counted_task_count, total_weight FROM public.server_owner_project_completion('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (61.36::numeric(5,2), 4::integer, 110::numeric) $$, 'Owner receives Project completion, count and total weight');
SELECT results_eq($$ SELECT calculated_completion_percent, counted_task_count, total_weight FROM public.server_owner_project_phase_completion('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.project_phases WHERE name = 'Visible Phase')) $$, $$ VALUES (30.00::numeric(5,2), 2::integer, 50::numeric) $$, 'Owner receives phase completion, count and total weight');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003802', true);
SELECT results_eq($$ SELECT calculated_completion_percent FROM public.current_client_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (61.36::numeric(5,2)) $$, 'Client own Project completion succeeds');
SELECT results_eq($$ SELECT calculated_completion_percent FROM public.current_client_project_phase_completion((SELECT id FROM app.project_phases WHERE name = 'Visible Phase')) $$, $$ VALUES (30.00::numeric(5,2)) $$, 'Client own active visible phase completion succeeds');
SELECT is_empty($$ SELECT * FROM public.current_client_project_phase_completion((SELECT id FROM app.project_phases WHERE name = 'Hidden Phase')) $$, 'hidden phase denied to Client');
SELECT is_empty($$ SELECT * FROM public.current_client_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Other Project')) $$, 'cross-Client Project denied safely');
SELECT is_empty($$ SELECT * FROM public.current_client_project_phase_completion((SELECT id FROM app.project_phases WHERE name = 'Other Phase')) $$, 'cross-Client phase denied safely');

SELECT * FROM public.server_archive_project_phase('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.project_phases WHERE name = 'Other Phase'), 1);
SELECT results_eq($$ SELECT calculated_completion_percent FROM public.server_owner_project_phase_completion('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.project_phases WHERE name = 'Other Phase')) $$, $$ VALUES (0.00::numeric(5,2)) $$, 'Owner can read inactive phase current derived value');

SELECT throws_ok($$ SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Missing Weight') $$, '23514', 'Project task weight is required when completion counting is enabled.', 'omitted counted weight fails deterministically');
SELECT throws_ok($$ SELECT * FROM public.server_create_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.projects WHERE name = 'Completion Project'), 'Noncounting Weighted', NULL, NULL, NULL, NULL, 10, false) $$, '23514', 'Project task weight is not allowed when completion counting is disabled.', 'non-counting task with weight rejected');

SELECT * FROM public.server_reopen_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Complete Weighted'), 3, 75, 'Correction');
SELECT results_eq($$ SELECT app.calculate_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (50.00::numeric(5,2)) $$, 'reopened task contributes current percentage');
SELECT * FROM public.server_cancel_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'No Phase Weighted'), 3, 'Cancelled no phase');
SELECT results_eq($$ SELECT app.calculate_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (52.50::numeric(5,2)) $$, 'cancellation removes task from denominator immediately');
SELECT * FROM public.server_complete_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Progress Weighted'), 3);
SELECT * FROM public.server_archive_project_task('00000000-0000-0000-0000-000000003801', (SELECT id FROM app.tasks WHERE title = 'Progress Weighted'), 4);
SELECT results_eq($$ SELECT app.calculate_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (53.57::numeric(5,2)) $$, 'archival removes task from denominator immediately');

SELECT results_eq($$ SELECT app.calculate_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, $$ VALUES (53.57::numeric(5,2)) $$, 'deterministic two-decimal numeric result');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action IN ('view_project_completion','view_project_phase_completion') AND outcome = 'success'), 'successful calculation creates no activity event');
SELECT results_eq($$ SELECT version_number FROM app.projects WHERE name = 'Completion Project' $$, $$ VALUES (3) $$, 'calculation does not increment Project version');
SELECT hasnt_table('app', 'notifications', 'calculation creates no notifications');
SELECT hasnt_table('app', 'progress_updates', 'progress updates remain absent');
SELECT hasnt_table('app', 'financial_transactions', 'financial objects remain absent');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003804', true);
SELECT is_empty($$ SELECT * FROM public.current_client_project_completion((SELECT id FROM app.projects WHERE name = 'Completion Project')) $$, 'Project Manager denied');
SELECT ok(pg_get_functiondef('public.current_account()'::regprocedure) NOT ILIKE '%project_manager%access_allowed%true%', 'reserved-role activation unchanged');

SELECT * FROM finish();
ROLLBACK;
