BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(35);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000001701', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.17@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001702', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.17@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001703', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.client.17@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001704', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reserved.17@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000001701', 'owner.17@example.test', 'Owner Seventeen', decode('1717171717171717171717171717171717171717171717171717171717171717', 'hex'), 'req-17', 'corr-17');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001701', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, created_by, updated_by)
VALUES (
  'Contractor Test Company',
  'Contractor Test',
  'USD',
  (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701'),
  (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701')
);

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000001702', '00000000-0000-0000-0000-000000001702', 'client.17@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701')),
  ('10000000-0000-0000-0000-000000001703', '00000000-0000-0000-0000-000000001703', 'other.client.17@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701')),
  ('10000000-0000-0000-0000-000000001704', '00000000-0000-0000-0000-000000001704', 'reserved.17@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000001702', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701')),
  ('10000000-0000-0000-0000-000000001703', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701')),
  ('10000000-0000-0000-0000-000000001704', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001701'));

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000001701', 'Client A', NULL, 'client.a.17@example.test', NULL, NULL, NULL);
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000001701', 'Client B', NULL, 'client.b.17@example.test', NULL, NULL, NULL);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.clients WHERE display_name = 'Client A'), '10000000-0000-0000-0000-000000001702', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.clients WHERE display_name = 'Client B'), '10000000-0000-0000-0000-000000001703', 1);

ALTER TABLE app.project_number_counters DISABLE TRIGGER project_number_counters_no_delete;
DELETE FROM app.project_number_counters;
ALTER TABLE app.project_number_counters ENABLE TRIGGER project_number_counters_no_delete;

SELECT results_eq(
  $$ SELECT project_number, status, version_number FROM public.server_create_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.clients WHERE display_name = 'Client A'), ' Project One ', 'USD', 'Renovation', 'Secret Location', DATE '2026-01-01', DATE '2026-02-01', 0, 'USD', 0, 'USD', 'summary for client', 'private project notes', 'req', 'corr') $$,
  $$ VALUES ('PRJ-2026-0001'::text, 'DRAFT'::text, 1) $$,
  'Owner creates Project with contractor-time-zone Project number'
);
SELECT results_eq(
  $$ SELECT project_number FROM public.server_create_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.clients WHERE display_name = 'Client A'), 'Project Two', 'USD') $$,
  $$ VALUES ('PRJ-2026-0002'::text) $$,
  'second Project number increments'
);
SELECT is((SELECT count(*)::integer FROM public.server_owner_project_record_list('00000000-0000-0000-0000-000000001701', 500, -10)), 2, 'Owner list is bounded and readable');
SELECT results_eq(
  $$ SELECT project_number, internal_notes, contract_amount, budget_amount FROM public.server_owner_project_record_detail('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001')) $$,
  $$ VALUES ('PRJ-2026-0001'::citext, 'private project notes'::text, 0::numeric(20,6), 0::numeric(20,6)) $$,
  'Owner detail can read internal notes and monetary metadata'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 1, 'Project One Updated', 'USD', 'Repair', 'Masked Location', DATE '2026-01-02', DATE '2026-02-02', 10, 'USD', 20, 'USD', 'updated client summary', 'updated private notes') $$,
  $$ VALUES (2) $$,
  'Owner update increments version once'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_update_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 1, 'Stale', 'USD') $$,
  '40001',
  'Project record version conflict.',
  'stale update rejected'
);
SELECT results_eq(
  $$ SELECT new_client_id, version_number FROM public.server_change_project_client('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), (SELECT id FROM app.clients WHERE display_name = 'Client B'), 2) $$,
  $$ VALUES ((SELECT id FROM app.clients WHERE display_name = 'Client B'), 3) $$,
  'pre-active Project Client reassignment succeeds'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_change_project_client('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), (SELECT id FROM app.clients WHERE display_name = 'Client B'), 3) $$,
  $$ VALUES (3) $$,
  'same Client reassignment is deterministic no-change'
);
SELECT results_eq(
  $$ SELECT status, version_number FROM public.server_change_project_status('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 3, 'APPROVED') $$,
  $$ VALUES ('APPROVED'::text, 4) $$,
  'DRAFT to APPROVED transition succeeds'
);
SELECT results_eq(
  $$ SELECT status, version_number FROM public.server_change_project_status('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 4, 'ACTIVE') $$,
  $$ VALUES ('ACTIVE'::text, 5) $$,
  'APPROVED to ACTIVE transition succeeds'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_change_project_client('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), (SELECT id FROM app.clients WHERE display_name = 'Client A'), 5) $$,
  '23514',
  'Project Client cannot be changed in this status.',
  'Client reassignment is denied from ACTIVE onward'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 5, 'ARCHIVED') $$,
  '23514',
  'Project terminal transitions require dedicated functions.',
  'general status change cannot archive'
);
SELECT results_eq(
  $$ SELECT status, version_number FROM public.server_change_project_status('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 5, 'ON_HOLD') $$,
  $$ VALUES ('ON_HOLD'::text, 6) $$,
  'ACTIVE to ON_HOLD transition succeeds'
);
SELECT results_eq(
  $$ SELECT status, version_number FROM public.server_change_project_status('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 6, 'ACTIVE') $$,
  $$ VALUES ('ACTIVE'::text, 7) $$,
  'ON_HOLD to ACTIVE transition succeeds'
);
SELECT results_eq(
  $$ SELECT status, version_number FROM public.server_complete_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 7) $$,
  $$ VALUES ('COMPLETED'::text, 8) $$,
  'ACTIVE to COMPLETED succeeds'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_complete_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 8) $$,
  '23514',
  'Project status transition is not allowed.',
  'repeated completion rejected'
);
SELECT results_eq(
  $$ SELECT status, version_number FROM public.server_archive_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 8) $$,
  $$ VALUES ('ARCHIVED'::text, 9) $$,
  'COMPLETED to ARCHIVED succeeds'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_archive_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 9) $$,
  '23514',
  'Project status transition is not allowed.',
  'repeated archive rejected'
);
SELECT results_eq(
  $$ SELECT status, version_number FROM public.server_cancel_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0002'), 1, ' Client cancelled ') $$,
  $$ VALUES ('CANCELLED'::text, 2) $$,
  'DRAFT to CANCELLED succeeds with reason'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_cancel_project_record('00000000-0000-0000-0000-000000001701', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0002'), 2, ' ') $$,
  '23514',
  'Project cancellation requires a reason.',
  'blank cancellation reason rejected'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001703', true);
SELECT results_eq(
  $$ SELECT project_number, name, status, reporting_currency_code, client_visible_summary FROM public.current_client_project_records() ORDER BY project_number $$,
  $$ VALUES ('PRJ-2026-0001'::text, 'Project One Updated'::text, 'ARCHIVED'::text, 'USD'::char(3), 'updated client summary'::text) $$,
  'Client B reads only its linked Project safe fields'
);
SELECT ok(NOT EXISTS (SELECT 1 FROM public.current_client_project_records() WHERE project_number = 'PRJ-2026-0002'), 'Client B cannot read Client A Project');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM information_schema.parameters
  WHERE specific_schema = 'public'
    AND specific_name = (SELECT specific_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'current_client_project_records')
    AND parameter_name IN ('contract_amount','contract_currency_code','budget_amount','budget_currency_code','internal_notes','cancellation_reason','created_by','updated_by','archived_by')
), 'Client-safe Project reads omit private and monetary fields');
SELECT is((SELECT count(*)::integer FROM public.current_client_project_record((SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0002'))), 0, 'Client detail prevents cross-Client Project-ID manipulation');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001704', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'reserved role remains unusable'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001701', true);
SELECT throws_ok($$ DELETE FROM app.projects WHERE project_number = 'PRJ-2026-0001' $$, '23514', 'Project records cannot be deleted.', 'hard delete rejected');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_record_created'), 2, 'Project create activity logs written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_record_updated'), 1, 'Project update activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_client_changed'), 1, 'Project Client change activity log written once');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_status_changed'), 4, 'Project status change activity logs written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_completed'), 1, 'Project completion activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_cancelled'), 1, 'Project cancellation activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'project_archived'), 1, 'Project archive activity log written');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM app.activity_logs
  WHERE action LIKE 'project_%'
    AND (
      previous_values::text LIKE '%private project notes%'
      OR new_values::text LIKE '%private project notes%'
      OR new_values::text LIKE '%Client cancelled%'
      OR previous_values::text LIKE '%10000000-0000-0000-0000-000000001702%'
      OR new_values::text LIKE '%10000000-0000-0000-0000-000000001702%'
      OR new_values::text LIKE '%10.000000%'
    )
), 'Project activity metadata masks sensitive details and raw monetary values');
SELECT lives_ok(
  $$ SELECT public.server_record_denied_privileged_operation('00000000-0000-0000-0000-000000001701', 'change_project_client', 'project_record', (SELECT id FROM app.projects WHERE project_number = 'PRJ-2026-0001'), 'authorization_denied') $$,
  'Project denied action code is accepted'
);

SELECT * FROM finish();
ROLLBACK;
