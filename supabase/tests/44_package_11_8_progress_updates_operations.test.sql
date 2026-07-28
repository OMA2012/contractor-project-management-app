BEGIN;
SELECT plan(38);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000004401', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.44a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004402', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.44b@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004403', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.44a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004404', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.44b@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000004401', 'owner.44a@example.test', 'Owner Forty Four A', decode('4444444444444444444444444444444444444444444444444444444444444444', 'hex'), 'req-44', 'corr-44');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004401', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Progress Operations Contractor', 'Progress Operations Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004402', '00000000-0000-0000-0000-000000004402', 'owner.44b@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401')),
  ('10000000-0000-0000-0000-000000004403', '00000000-0000-0000-0000-000000004403', 'client.44a@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401')),
  ('10000000-0000-0000-0000-000000004404', '00000000-0000-0000-0000-000000004404', 'client.44b@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004402', 'Owner Forty Four B', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401')),
  ('10000000-0000-0000-0000-000000004403', 'Client Forty Four A', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401')),
  ('10000000-0000-0000-0000-000000004404', 'Client Forty Four B', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000004402', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), true),
  ('10000000-0000-0000-0000-000000004403', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), true),
  ('10000000-0000-0000-0000-000000004404', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004401'), true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000004401', 'Progress Client A', NULL, 'progress.client.a@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000004401', 'Progress Client B', NULL, 'progress.client.b@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.clients WHERE display_name = 'Progress Client A'), '10000000-0000-0000-0000-000000004403', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.clients WHERE display_name = 'Progress Client B'), '10000000-0000-0000-0000-000000004404', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.clients WHERE display_name = 'Progress Client A'), 'Progress Project A', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.clients WHERE display_name = 'Progress Client B'), 'Progress Project B', 'USD');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), 1, 'QUOTATION');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), 2, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project B'), 1, 'QUOTATION');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project B'), 2, 'APPROVED');

SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), 'Visible milestone', NULL, NULL, NULL, true);
SELECT * FROM public.server_create_project_milestone('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), 'Private milestone', NULL, NULL, NULL, false);

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), (SELECT id FROM app.project_milestones WHERE name = 'Visible milestone'), '  Week one  ', '  Public-safe summary  ', 12.5, false) $$, 'Owner creates draft');
SELECT results_eq($$ SELECT title::text, summary, status::text, client_visible, version_number FROM app.progress_updates WHERE title = 'Week one' $$, $$ VALUES ('Week one'::text, 'Public-safe summary'::text, 'DRAFT'::text, false, 1) $$, 'draft is normalized and private');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_progress_update_draft('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one'), 1, (SELECT id FROM app.project_milestones WHERE name = 'Visible milestone'), 'Week one revised', 'Revised public summary', 25, false) $$, 'Owner updates draft');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_progress_update_draft('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 1, NULL, 'Stale', 'Stale summary', 25, false) $$, '40001', 'Progress update version conflict.', 'stale draft update rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 2) $$, 'Owner submits draft');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_progress_update_draft('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 3, NULL, 'Locked', 'Locked summary', 25, false) $$, '23514', 'Progress update cannot be edited.', 'submitted content immutable through draft update');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 3) $$, '42501', 'Progress update requires different Owner approval.', 'creator self-approval denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000004402', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 3) $$, 'different Owner approves');
SELECT is_empty($$ SELECT * FROM public.current_client_progress_update_list((SELECT id FROM app.projects WHERE name = 'Progress Project A')) $$, 'approval alone is invisible to Client');
SELECT lives_ok($$ SELECT * FROM public.server_owner_set_progress_update_client_visibility('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 4, true) $$, 'controlled visibility change succeeds');
SELECT throws_ok($$ SELECT * FROM public.server_owner_set_progress_update_client_visibility('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 4, false) $$, '40001', 'Progress update version conflict.', 'stale visibility change rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_publish_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 5) $$, 'approved visible update publishes');
SELECT throws_ok($$ SELECT * FROM public.server_owner_set_progress_update_client_visibility('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 6, false) $$, '23514', 'Progress update visibility cannot be changed.', 'visibility cannot change after publication');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004403', true);
SELECT results_eq($$ SELECT title, milestone_id IS NOT NULL FROM public.current_client_progress_update_list((SELECT id FROM app.projects WHERE name = 'Progress Project A')) $$, $$ VALUES ('Week one revised'::text, true) $$, 'own Client sees published visible update and visible milestone id');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004404', true);
SELECT is_empty($$ SELECT * FROM public.current_client_progress_update_detail((SELECT id FROM app.progress_updates WHERE title = 'Week one revised')) $$, 'other Client copied identifier reveals no row');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004401', true);

SELECT lives_ok($$ SELECT * FROM public.server_owner_archive_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Week one revised'), 6) $$, 'published approved record archives');
SELECT ok((SELECT published_at IS NOT NULL AND archived_at IS NOT NULL FROM app.progress_updates WHERE title = 'Week one revised'), 'published timestamp survives archive');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004403', true);
SELECT is_empty($$ SELECT * FROM public.current_client_progress_update_list((SELECT id FROM app.projects WHERE name = 'Progress Project A')) $$, 'archived published update disappears from Client feed');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004401', true);

SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), (SELECT id FROM app.project_milestones WHERE name = 'Private milestone'), 'Private milestone update', 'Summary safe for publication', 33, true);
SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Private milestone update'), 1);
SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000004402', (SELECT id FROM app.progress_updates WHERE title = 'Private milestone update'), 2);
SELECT * FROM public.server_owner_publish_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Private milestone update'), 3);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004403', true);
SELECT results_eq($$ SELECT title, milestone_id FROM public.current_client_progress_update_list((SELECT id FROM app.projects WHERE name = 'Progress Project A')) WHERE title = 'Private milestone update' $$, $$ VALUES ('Private milestone update'::text, NULL::uuid) $$, 'private milestone id is projected as NULL to Client');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004401', true);

SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), NULL, 'Draft archive denied', 'Draft summary', 10, false);
SELECT throws_ok($$ SELECT * FROM public.server_owner_archive_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Draft archive denied'), 1) $$, '23514', 'Progress update cannot be archived.', 'draft archive rejected');
SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Draft archive denied'), 1);
SELECT throws_ok($$ SELECT * FROM public.server_owner_archive_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Draft archive denied'), 2) $$, '23514', 'Progress update cannot be archived.', 'submitted archive rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reject_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Draft archive denied'), 2, 'Need a replacement draft') $$, 'rejection succeeds with reason');
SELECT lives_ok($$ SELECT * FROM public.server_owner_archive_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Draft archive denied'), 3) $$, 'rejected update archives');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reject_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.progress_updates WHERE title = 'Private milestone update'), 4, 'Nope') $$, '23514', 'Progress update cannot be rejected.', 'rejected workflow cannot target approved rows');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), (SELECT id FROM app.project_milestones WHERE name = 'Visible milestone' AND project_id = (SELECT id FROM app.projects WHERE name = 'Progress Project A')), 'Bad completion', 'Bad completion summary', 101, false) $$, '23514', 'Invalid progress update.', 'invalid completion percentage rejected');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000004403', (SELECT id FROM app.projects WHERE name = 'Progress Project A'), NULL, 'Client denied', 'Client summary', 10, false) $$, '42501', 'Privileged operation denied.', 'Client cannot create progress updates');

SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_created'), 'create activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_updated'), 'draft update activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_submitted'), 'submit activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_approved'), 'approval activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_client_visibility_changed'), 'visibility activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_published'), 'publication activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_rejected'), 'rejection activity logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_archived'), 'archive activity logged');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.task_updates WHERE update_note = 'Summary safe for publication'), 'progress snapshots do not create task updates');
SELECT results_eq($$ SELECT calculated_completion_percent, official_completion_percent FROM public.server_owner_official_project_completion('00000000-0000-0000-0000-000000004401', (SELECT id FROM app.projects WHERE name = 'Progress Project A')) $$, $$ VALUES (0.00::numeric(5,2), 0.00::numeric(5,2)) $$, 'progress updates do not change calculated or official completion');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('financial_transactions','ledger_entries')), 'no finance created');
SELECT is((SELECT count(*)::integer FROM app.projects WHERE name IN ('Progress Project A','Progress Project B') AND status = 'APPROVED'), 2, 'Project statuses unchanged by progress workflow');

SELECT * FROM finish();
ROLLBACK;
