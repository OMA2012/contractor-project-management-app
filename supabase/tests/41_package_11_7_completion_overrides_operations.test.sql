BEGIN;
SELECT plan(30);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.41a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.41b@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.41@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000004101', 'owner.41a@example.test', 'Owner Forty One A', decode('4141414141414141414141414141414141414141414141414141414141414141', 'hex'), 'req-41', 'corr-41');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004101', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Override Operations Contractor', 'Override Operations Contractor', 'USD', 'Asia/Kuching', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004102', '00000000-0000-0000-0000-000000004102', 'owner.41b@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101')),
  ('10000000-0000-0000-0000-000000004103', '00000000-0000-0000-0000-000000004103', 'client.41@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004102', 'Owner Forty One B', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101')),
  ('10000000-0000-0000-0000-000000004103', 'Client Forty One', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000004102', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'), true),
  ('10000000-0000-0000-0000-000000004103', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004101'), true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000004101', 'Override Operations Client', NULL, 'client.41a@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.clients WHERE display_name = 'Override Operations Client'), '10000000-0000-0000-0000-000000004103', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.clients WHERE display_name = 'Override Operations Client'), 'Override Operations Project', 'USD');

SELECT results_eq($$ SELECT calculated_completion_percent, official_completion_percent, is_overridden FROM public.server_owner_official_project_completion('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project')) $$, $$ VALUES (0.00::numeric(5,2), 0.00::numeric(5,2), false) $$, 'official completion initially falls back to calculated');
SELECT throws_ok($$ SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project'), 10, 'Missing time', NULL) $$, '23514', 'Project completion override effective timestamp is required.', 'null effective time rejected');
SELECT throws_ok($$ SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project'), 10, 'Future time', transaction_timestamp() + interval '1 day') $$, '23514', 'Future Project completion overrides are not supported.', 'future effective time rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project'), 25, 'Past request reason', transaction_timestamp() - interval '1 hour') $$, 'past effective timestamp accepted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project'), 35, 'Current request reason', transaction_timestamp()) $$, 'current effective timestamp accepted');
SELECT results_eq($$ SELECT count(*)::integer FROM app.project_completion_overrides WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Override Operations Project') AND approved_at IS NULL $$, $$ VALUES (2) $$, 'multiple pending requests coexist');
SELECT results_eq($$ SELECT calculated_completion_percent, official_completion_percent, is_overridden FROM public.server_owner_official_project_completion('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project')) $$, $$ VALUES (0.00::numeric(5,2), 0.00::numeric(5,2), false) $$, 'pending requests do not change official completion');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Past request reason')) $$, '42501', 'Project completion override requires different Owner approval.', 'self-approval denied');
SELECT * FROM public.server_owner_approve_project_completion_override('00000000-0000-0000-0000-000000004102', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Past request reason'));
SELECT results_eq($$ SELECT calculated_completion_percent, official_completion_percent, is_overridden FROM public.server_owner_official_project_completion('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project')) $$, $$ VALUES (0.00::numeric(5,2), 25.00::numeric(5,2), true) $$, 'different Owner approval changes official completion');
SELECT results_eq($$ SELECT count(*)::integer FROM app.project_completion_overrides WHERE reason = 'Current request reason' AND approved_at IS NULL $$, $$ VALUES (1) $$, 'unrelated pending request remains pending');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_project_completion_override('00000000-0000-0000-0000-000000004102', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Past request reason')) $$, '23514', 'Project completion override cannot be approved.', 'repeated approval rejected');
SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project'), 80, 'Superseding request reason', transaction_timestamp());
SELECT * FROM public.server_owner_approve_project_completion_override('00000000-0000-0000-0000-000000004102', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Superseding request reason'));
SELECT results_eq($$ SELECT count(*)::integer FROM app.project_completion_overrides WHERE project_id = (SELECT id FROM app.projects WHERE name = 'Override Operations Project') AND approved_at IS NOT NULL AND revoked_at IS NULL $$, $$ VALUES (1) $$, 'only one active override remains after supersession');
SELECT results_eq($$ SELECT app.derive_project_completion_override_state(approved_at, approved_by, revoked_at, revoked_by) FROM app.project_completion_overrides WHERE reason = 'Past request reason' $$, $$ VALUES ('SUPERSEDED_OR_REVOKED'::text) $$, 'previous active override is retained as superseded history');
SELECT results_eq($$ SELECT official_completion_percent FROM public.server_owner_official_project_completion('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project')) $$, $$ VALUES (80.00::numeric(5,2)) $$, 'superseding override becomes official');
SELECT throws_ok($$ SELECT * FROM public.server_owner_revoke_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Superseding request reason'), '   ') $$, '23514', 'Project completion override revocation reason is required.', 'revocation requires reason');
SELECT * FROM public.server_owner_revoke_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Superseding request reason'), 'Revocation reason kept');
SELECT results_eq($$ SELECT official_completion_percent, is_overridden FROM public.server_owner_official_project_completion('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project')) $$, $$ VALUES (0.00::numeric(5,2), false) $$, 'revocation restores calculated completion as official');
SELECT throws_ok($$ SELECT * FROM public.server_owner_revoke_project_completion_override('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Superseding request reason'), 'Again') $$, '23514', 'Project completion override cannot be revoked.', 'repeated revocation rejected');
SELECT results_eq($$ SELECT reason FROM app.project_completion_overrides WHERE reason = 'Superseding request reason' $$, $$ VALUES ('Superseding request reason'::text) $$, 'original override reason remains unchanged after revocation');
SELECT results_eq($$ SELECT derived_state FROM public.server_owner_project_completion_override_list('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.projects WHERE name = 'Override Operations Project'), 10, 0) WHERE reason = 'Superseding request reason' $$, $$ VALUES ('SUPERSEDED_OR_REVOKED'::text) $$, 'Owner history derives state');
SELECT results_eq($$ SELECT override_percent, reason FROM public.server_owner_project_completion_override_detail('00000000-0000-0000-0000-000000004101', (SELECT id FROM app.project_completion_overrides WHERE reason = 'Superseding request reason')) $$, $$ VALUES (80.00::numeric(5,2), 'Superseding request reason'::text) $$, 'Owner detail returns retained history');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004103', true);
SELECT results_eq($$ SELECT calculated_completion_percent, official_completion_percent, is_overridden FROM public.current_client_project_completion((SELECT id FROM app.projects WHERE name = 'Override Operations Project')) $$, $$ VALUES (0.00::numeric(5,2), 0.00::numeric(5,2), false) $$, 'Client sees fallback official completion after revocation');
SELECT ok(
  pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%reason%'
  AND pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%active_override_id%'
  AND pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%approved_by%'
  AND pg_get_function_result('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%created_by%',
  'Client output exposes no reason, identifiers or actors'
);
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_completion_override_requested' AND reason = 'Past request reason'), 'request activity retains validated reason');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_completion_override_approved' AND reason = 'Past request reason'), 'approval activity retains selected reason');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_completion_override_superseded' AND metadata ? 'superseded_by_override_id'), 'supersession activity is logged');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'project_completion_override_revoked' AND reason = 'Revocation reason kept'), 'revocation activity retains reason');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'denied_privileged_operation' AND reason IN ('Future time', 'Missing time', '   ')), 'denied logs do not echo submitted reasons');
SELECT results_eq($$ SELECT version_number FROM app.projects WHERE name = 'Override Operations Project' $$, $$ VALUES (1) $$, 'override workflows do not increment Project version');
SELECT hasnt_table('app', 'notifications', 'notification table remains absent');
SELECT hasnt_table('app', 'financial_transactions', 'financial objects remain absent');

SELECT * FROM finish();
ROLLBACK;
