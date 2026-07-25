BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(38);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000001401', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.14@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001402', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.14@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001403', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.client.14@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001404', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff.14@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001405', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reserved.14@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001406', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'suspended.14@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001407', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'disabled.14@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000001401', 'owner.14@example.test', 'Owner Fourteen', decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'), 'req-14', 'corr-14');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001401', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, deactivated_at, deactivated_by, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000001402', '00000000-0000-0000-0000-000000001402', 'client.14@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001403', '00000000-0000-0000-0000-000000001403', 'other.client.14@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001404', '00000000-0000-0000-0000-000000001404', 'staff.14@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001405', '00000000-0000-0000-0000-000000001405', 'reserved.14@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001406', '00000000-0000-0000-0000-000000001406', 'suspended.14@example.test', 'CLIENT', 'SUSPENDED', false, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001407', '00000000-0000-0000-0000-000000001407', 'disabled.14@example.test', 'CLIENT', 'DISABLED', false, now(), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000001402', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001403', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001404', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001405', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001406', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401')),
  ('10000000-0000-0000-0000-000000001407', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'));

ALTER SEQUENCE app.client_number_seq RESTART WITH 1;

SELECT results_eq(
  $$ SELECT client_number, version_number FROM public.server_create_client_record('00000000-0000-0000-0000-000000001401', ' Acme Client ', ' Acme Legal ', 'ACME@example.test', '+1234567890', ' 123 Main ', 'private notes', 'req', 'corr') $$,
  $$ VALUES ('CL-000001'::text, 1) $$,
  'Owner creates first Client record with generated number'
);
SELECT results_eq(
  $$ SELECT client_number, version_number FROM public.server_create_client_record('00000000-0000-0000-0000-000000001401', 'Beta Client', NULL, NULL, NULL, NULL, NULL, 'req', 'corr') $$,
  $$ VALUES ('CL-000002'::text, 1) $$,
  'Owner creates second Client record with sequence number'
);
SELECT is((SELECT email::text FROM app.clients WHERE client_number = 'CL-000001'), 'acme@example.test', 'email normalized to lowercase');
SELECT is((SELECT created_by FROM app.clients WHERE client_number = 'CL-000001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001401'), 'created_by resolved from Owner subject');
SELECT is((SELECT count(*)::integer FROM public.server_owner_client_record_list('00000000-0000-0000-0000-000000001401', 500, -1)), 2, 'Owner list is bounded and readable');
SELECT results_eq(
  $$ SELECT client_number, internal_notes FROM public.server_owner_client_record_detail('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001')) $$,
  $$ VALUES ('CL-000001'::text, 'private notes'::text) $$,
  'Owner detail exposes internal notes for administration'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_update_client_record('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), 1, 'Acme Updated', 'Acme Legal Updated', 'updated@example.test', '+1234567899', '456 Main', 'new private notes', 'req', 'corr') $$,
  $$ VALUES (2) $$,
  'Owner update increments version once'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_update_client_record('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), 1, 'Stale', NULL, NULL, NULL, NULL, NULL) $$,
  '40001',
  'Client record version conflict.',
  'stale update is rejected deterministically'
);
SELECT throws_ok(
  $$ UPDATE app.clients SET client_number = 'CL-999999' WHERE client_number = 'CL-000001' $$,
  '23514',
  'Client number is immutable.',
  'client number cannot be changed'
);
SELECT results_eq(
  $$ SELECT portal_user_id, version_number FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), '10000000-0000-0000-0000-000000001402', 2, 'req', 'corr') $$,
  $$ VALUES ('10000000-0000-0000-0000-000000001402'::uuid, 3) $$,
  'valid portal user is linked and version increments'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), '10000000-0000-0000-0000-000000001402', 3) $$,
  $$ VALUES (3) $$,
  'same portal user relink is idempotent'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001402', true);
SELECT results_eq(
  $$ SELECT client_number, display_name, legal_name, email, phone, address, status FROM public.current_client_record() $$,
  $$ VALUES ('CL-000001'::text, 'Acme Updated'::text, 'Acme Legal Updated'::text, 'updated@example.test'::text, '+1234567899'::text, '456 Main'::text, 'ACTIVE'::text) $$,
  'Client reads only own safe linked record'
);
SELECT ok(NOT EXISTS (SELECT 1 FROM public.current_client_record() WHERE client_number = 'CL-000002'), 'Client cannot read unrelated record');
SELECT ok(NOT EXISTS (
  SELECT 1
  FROM information_schema.parameters
  WHERE specific_schema = 'public'
    AND specific_name = (SELECT specific_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'current_client_record')
    AND parameter_name IN ('internal_notes', 'portal_user_id', 'created_by', 'updated_by', 'archived_by')
), 'Client self-read omits private fields');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001401', true);
SELECT results_eq(
  $$ SELECT portal_user_id, version_number FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), '10000000-0000-0000-0000-000000001403', 3) $$,
  $$ VALUES ('10000000-0000-0000-0000-000000001403'::uuid, 4) $$,
  'portal replacement succeeds and increments version'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000002'), '10000000-0000-0000-0000-000000001403', 1) $$,
  '23505',
  'Client portal user already linked.',
  'duplicate portal link is prevented'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000002'), '10000000-0000-0000-0000-000000001404', 1) $$,
  '42501',
  'Privileged operation denied.',
  'staff portal user link is denied'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000002'), '10000000-0000-0000-0000-000000001405', 1) $$,
  '42501',
  'Privileged operation denied.',
  'reserved-role portal user link is denied'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000002'), '10000000-0000-0000-0000-000000001406', 1) $$,
  '42501',
  'Privileged operation denied.',
  'suspended Client user link is denied'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000002'), '10000000-0000-0000-0000-000000001407', 1) $$,
  '42501',
  'Privileged operation denied.',
  'disabled Client user link is denied'
);
SELECT results_eq(
  $$ SELECT portal_user_id, version_number FROM public.server_unlink_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), 4) $$,
  $$ VALUES (NULL::uuid, 5) $$,
  'unlink clears portal user and increments version'
);
SELECT results_eq(
  $$ SELECT version_number FROM public.server_unlink_client_portal_user('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), 5) $$,
  $$ VALUES (5) $$,
  'already unlinked is deterministic no-change'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001403', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_record()), 0, 'unlinked Client loses portal access');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001401', true);
SELECT results_eq(
  $$ SELECT status, is_active, version_number FROM public.server_archive_client_record('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), 5) $$,
  $$ VALUES ('INACTIVE'::text, false, 6) $$,
  'archive sets inactive state and increments version'
);
SELECT throws_ok(
  $$ SELECT * FROM public.server_archive_client_record('00000000-0000-0000-0000-000000001401', (SELECT id FROM app.clients WHERE client_number = 'CL-000001'), 6) $$,
  '23514',
  'Client record cannot be archived.',
  'repeated archive rejected safely'
);
SELECT throws_ok($$ DELETE FROM app.clients WHERE client_number = 'CL-000001' $$, '23514', 'Client records cannot be deleted.', 'hard delete is rejected');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'client_record_created'), 2, 'create activity logs written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'client_record_updated'), 1, 'update activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'client_portal_user_linked'), 1, 'link activity log written once');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'client_portal_user_replaced'), 1, 'replace activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'client_portal_user_unlinked'), 1, 'unlink activity log written');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'client_record_archived'), 1, 'archive activity log written');
SELECT ok(NOT EXISTS (
  SELECT 1
  FROM app.activity_logs
  WHERE action LIKE 'client_%'
    AND (
      previous_values::text LIKE '%updated@example.test%'
      OR new_values::text LIKE '%updated@example.test%'
      OR previous_values::text LIKE '%new private notes%'
      OR new_values::text LIKE '%new private notes%'
      OR previous_values::text LIKE '%10000000-0000-0000-0000-000000001402%'
      OR new_values::text LIKE '%10000000-0000-0000-0000-000000001402%'
    )
), 'activity metadata masks sensitive Client values');
SELECT lives_ok(
  $$ SELECT public.server_record_denied_privileged_operation('00000000-0000-0000-0000-000000001401', 'create_client_record', 'client_record', NULL, 'authorization_denied') $$,
  'denied Client action code is accepted by durable denial gateway'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001405', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'reserved role remains unusable in first release'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001402', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_record()), 0, 'replaced Client no longer has access to archived/unlinked record');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001401', true);
SELECT results_eq(
  $$ SELECT client_number FROM public.server_create_client_record('00000000-0000-0000-0000-000000001401', 'Gamma Client', NULL, NULL, NULL, NULL, NULL) $$,
  $$ VALUES ('CL-000003'::text) $$,
  'sequence continues across multiple trusted inserts'
);
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.clients'::regclass), 'forced RLS remains enabled during operations');

SELECT * FROM finish();
ROLLBACK;
