BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(30);

CREATE TEMP TABLE private_function_specs (
  regsig text PRIMARY KEY,
  expected_volatility "char" NOT NULL
) ON COMMIT DROP;

INSERT INTO private_function_specs (regsig, expected_volatility)
VALUES
  ('app.require_active_owner_admin(uuid)', 's'),
  ('app.record_denied_privileged_operation(uuid, character varying, character varying, uuid, character varying, text, text, text, inet, jsonb)', 'v'),
  ('app.expire_elapsed_client_invitations(uuid)', 'v'),
  ('app.create_client_invitation(uuid, uuid, citext, bytea, text, text, text, inet)', 'v'),
  ('app.resend_client_invitation(uuid, uuid, bytea, text, text, text, inet)', 'v'),
  ('app.revoke_client_invitation(uuid, uuid, text, text, text, text, inet)', 'v'),
  ('app.accept_client_invitation(uuid, bytea, text, text, text, text, inet)', 'v'),
  ('app.suspend_client_account(uuid, uuid, text, text, text, text, inet)', 'v'),
  ('app.reactivate_client_account(uuid, uuid, text, text, text, text, inet)', 'v'),
  ('app.disable_client_account(uuid, uuid, text, text, text, text, inet)', 'v'),
  ('app.bootstrap_first_owner(uuid, citext, text, bytea, text, text)', 'v'),
  ('app.activate_current_invited_owner(uuid, text, text, text, inet)', 'v');

SELECT is((SELECT count(*)::integer FROM private_function_specs WHERE to_regprocedure(regsig) IS NULL), 0, 'every private function exists with exact signature');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE p.provolatile <> s.expected_volatility), 0, 'every private function has expected volatility');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE NOT p.prosecdef), 0, 'every private function is security definer');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE p.proconfig IS DISTINCT FROM ARRAY['search_path=""']), 0, 'every private function has empty search path');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE pg_get_userbyid(p.proowner) IN ('anon', 'authenticated', 'service_role')), 0, 'every private function has privileged owner');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig), aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS acl WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'), 0, 'PUBLIC cannot execute private functions');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s WHERE has_function_privilege('anon', s.regsig, 'EXECUTE')), 0, 'anon cannot execute private functions');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s WHERE has_function_privilege('authenticated', s.regsig, 'EXECUTE')), 0, 'authenticated cannot execute private functions');
SELECT is((SELECT count(*)::integer FROM private_function_specs AS s WHERE has_function_privilege('service_role', s.regsig, 'EXECUTE')), 0, 'service_role cannot execute private functions directly');

SELECT ok(relforcerowsecurity, 'users still force RLS') FROM pg_class WHERE oid = 'app.users'::regclass;
SELECT ok(relforcerowsecurity, 'user_invitations force RLS') FROM pg_class WHERE oid = 'app.user_invitations'::regclass;
SELECT ok(relforcerowsecurity, 'activity_logs force RLS') FROM pg_class WHERE oid = 'app.activity_logs'::regclass;
SELECT ok(NOT has_table_privilege('authenticated', 'app.users', 'INSERT,UPDATE,DELETE'), 'authenticated still cannot write users');
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_invitations', 'INSERT,UPDATE,DELETE'), 'authenticated still cannot write invitations');
SELECT ok(NOT has_table_privilege('authenticated', 'app.activity_logs', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated still cannot write activity logs');

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.07@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000702', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.07@example.test', '', now(), '{}', '{}', now(), now());

SELECT lives_ok(
  $$ SELECT * FROM app.bootstrap_first_owner(
       '00000000-0000-0000-0000-000000000701',
       'owner.07@example.test',
       'Owner Seven',
       decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'),
       'req-07',
       'corr-07'
     ) $$,
  'private bootstrap executes through forced RLS'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000701', true);
SELECT lives_ok($$ SELECT public.activate_current_invited_owner() $$, 'invited owner activates through public wrapper');
SELECT results_eq(
  $$ SELECT effective_role_code FROM app.require_active_owner_admin('00000000-0000-0000-0000-000000000701') $$,
  $$ VALUES ('owner_admin'::varchar(40)) $$,
  'active owner authorization succeeds'
);
SELECT is(
  (SELECT count(*)::integer FROM app.require_active_owner_admin('00000000-0000-0000-0000-000000000702')),
  0,
  'unknown app actor has no owner authorization row'
);

SELECT lives_ok(
  $$ SELECT app.record_denied_privileged_operation(
       '00000000-0000-0000-0000-000000000701',
       'test_denied',
       'user',
       NULL,
       'insufficient_role',
       'req-denied',
       'corr-denied',
       NULL,
       NULL,
       '{"token":"secret","safe":"ok"}'::jsonb
     ) $$,
  'denial logging helper accepts controlled codes'
);
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'denied_privileged_operation'), 1, 'denied operation log persists');
SELECT is((SELECT metadata FROM app.activity_logs WHERE action = 'denied_privileged_operation'), '{"safe":"ok","requested_action":"test_denied"}'::jsonb, 'denial metadata is masked');
SELECT is((SELECT reason FROM app.activity_logs WHERE action = 'denied_privileged_operation'), 'insufficient_role', 'denial reason code is stored');

SELECT throws_ok($$ SELECT app.record_denied_privileged_operation('00000000-0000-0000-0000-000000000701', 'TestDenied', 'user', NULL, 'authorization_denied') $$, '23514', 'Denied-operation action code is invalid.', 'uppercase action code is rejected');
SELECT throws_ok($$ SELECT app.record_denied_privileged_operation('00000000-0000-0000-0000-000000000701', 'test denied', 'user', NULL, 'authorization_denied') $$, '23514', 'Denied-operation action code is invalid.', 'whitespace action code is rejected');
SELECT throws_ok($$ SELECT app.record_denied_privileged_operation('00000000-0000-0000-0000-000000000701', 'https_token', 'user', NULL, 'authorization_denied') $$, '23514', 'Denied-operation action code is invalid.', 'URL-like action code is rejected');
SELECT throws_ok($$ SELECT app.record_denied_privileged_operation('00000000-0000-0000-0000-000000000701', 'test_denied', 'token_value', NULL, 'authorization_denied') $$, '23514', 'Denied-operation entity type code is invalid.', 'token-like entity type is rejected');
SELECT throws_ok($$ SELECT app.record_denied_privileged_operation('00000000-0000-0000-0000-000000000701', 'test_denied', 'user', NULL, 'raw stack trace') $$, '23514', 'Denied-operation reason code is invalid.', 'unsupported reason code is rejected');
SELECT throws_ok($$ SELECT app.record_denied_privileged_operation('00000000-0000-0000-0000-000000000702', 'test_denied', 'user', NULL, 'authorization_denied') $$, '42501', 'Privileged operation denied.', 'unknown identity writes no denial row');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'denied_privileged_operation'), 1, 'unknown identity creates no activity row');

SELECT * FROM finish();
ROLLBACK;
