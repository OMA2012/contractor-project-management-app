BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(23);

CREATE TEMP TABLE gateway_function_specs (
  regsig text PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO gateway_function_specs (regsig)
VALUES
  ('public.server_create_client_invitation(uuid, uuid, citext, bytea, text, text, text, inet)'),
  ('public.server_resend_client_invitation(uuid, uuid, bytea, text, text, text, inet)'),
  ('public.server_revoke_client_invitation(uuid, uuid, text, text, text, text, inet)'),
  ('public.server_accept_client_invitation(uuid, bytea, text, text, text, text, inet)'),
  ('public.server_suspend_client_account(uuid, uuid, text, text, text, text, inet)'),
  ('public.server_reactivate_client_account(uuid, uuid, text, text, text, text, inet)'),
  ('public.server_disable_client_account(uuid, uuid, text, text, text, text, inet)'),
  ('public.server_bootstrap_first_owner(uuid, citext, text, bytea, text, text)'),
  ('public.server_record_denied_privileged_operation(uuid, character varying, character varying, uuid, character varying, text, text, text, inet, jsonb)');

SELECT is((SELECT count(*)::integer FROM gateway_function_specs WHERE to_regprocedure(regsig) IS NULL), 0, 'every service gateway exists with exact signature');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE p.provolatile <> 'v'), 0, 'every service gateway is volatile');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE NOT p.prosecdef), 0, 'every service gateway is security definer');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE p.proconfig IS DISTINCT FROM ARRAY['search_path=""']), 0, 'every service gateway has empty search path');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig) WHERE pg_get_userbyid(p.proowner) IN ('anon', 'authenticated', 'service_role')), 0, 'every service gateway has privileged owner');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s WHERE NOT has_function_privilege('service_role', s.regsig, 'EXECUTE')), 0, 'service_role can execute every service gateway');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s JOIN pg_proc AS p ON p.oid = to_regprocedure(s.regsig), aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS acl WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'), 0, 'PUBLIC cannot execute service gateways');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s WHERE has_function_privilege('anon', s.regsig, 'EXECUTE')), 0, 'anon cannot execute service gateways');
SELECT is((SELECT count(*)::integer FROM gateway_function_specs AS s WHERE has_function_privilege('authenticated', s.regsig, 'EXECUTE')), 0, 'authenticated cannot execute service gateways');

SELECT is((SELECT pronargs::integer FROM pg_proc WHERE oid = 'public.activate_current_invited_owner()'::regprocedure), 0, 'owner activation gateway has zero arguments');
SELECT is((SELECT provolatile FROM pg_proc WHERE oid = 'public.activate_current_invited_owner()'::regprocedure), 'v'::"char", 'owner activation gateway is volatile');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.activate_current_invited_owner()'::regprocedure), 'owner activation gateway is security definer');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'public.activate_current_invited_owner()'::regprocedure), ARRAY['search_path=""'], 'owner activation gateway has empty search path');
SELECT isnt((SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.activate_current_invited_owner()'::regprocedure), 'service_role', 'owner activation gateway owner is not service_role');
SELECT ok(has_function_privilege('authenticated', 'public.activate_current_invited_owner()', 'EXECUTE'), 'authenticated can execute invited owner activation');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc AS p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS acl WHERE p.oid = 'public.activate_current_invited_owner()'::regprocedure AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'), 'PUBLIC cannot execute invited owner activation');
SELECT ok(NOT has_function_privilege('anon', 'public.activate_current_invited_owner()', 'EXECUTE'), 'anon cannot execute invited owner activation');
SELECT ok(NOT has_function_privilege('service_role', 'public.activate_current_invited_owner()', 'EXECUTE'), 'service_role cannot execute invited owner activation');

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000000801', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.08@example.test', '', now(), '{}', '{}', now(), now());
SELECT lives_ok(
  $$ SELECT * FROM public.server_bootstrap_first_owner(
       '00000000-0000-0000-0000-000000000801',
       'owner.08@example.test',
       'Owner Eight',
       decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'),
       'req-08',
       'corr-08'
     ) $$,
  'service gateway calls private bootstrap behavior'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
SELECT lives_ok($$ SELECT public.activate_current_invited_owner() $$, 'authenticated owner activation wrapper derives auth.uid');
SELECT throws_ok($$ SELECT public.activate_current_invited_owner() $$, '23514', NULL, 'repeated owner activation is rejected');
SELECT lives_ok(
  $$ SELECT public.server_record_denied_privileged_operation(
       '00000000-0000-0000-0000-000000000801',
       'client_invitation_create',
       'user_invitation',
       NULL,
       'authorization_denied',
       'req-denied-gateway',
       'corr-denied-gateway'
     ) $$,
  'denial logging works through separate service gateway transaction'
);
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'denied_privileged_operation'), 1, 'denial gateway writes one durable activity row');

SELECT * FROM finish();
ROLLBACK;
