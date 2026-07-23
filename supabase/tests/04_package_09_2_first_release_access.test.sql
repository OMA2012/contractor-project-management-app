BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(21);

SELECT has_function('public', 'current_account', ARRAY[]::name[], 'current_account still exists');
SELECT volatility_is('public', 'current_account', ARRAY[]::name[], 'stable', 'current_account remains stable');
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE oid = 'public.current_account()'::regprocedure),
  true,
  'current_account remains security definer'
);
SELECT is(
  (SELECT proconfig FROM pg_proc WHERE oid = 'public.current_account()'::regprocedure),
  ARRAY['search_path=""'],
  'current_account keeps empty search path'
);
SELECT ok(has_function_privilege('authenticated', 'public.current_account()', 'EXECUTE'), 'authenticated can execute current_account');

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.only.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.only.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000403', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.pm.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000404', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.accountant.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000405', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.site.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000406', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.client.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000407', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.owner.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000408', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.pm.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000409', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.accountant.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000410', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.site.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000411', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.staffonly.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000412', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.only.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000413', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.only.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000414', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'site.only.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000415', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invited.0910@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000416', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'missing.0910@example.test', '', now(), '{}', '{}', now(), now());

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, deactivated_at, deactivated_by)
VALUES
  ('10000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000401', 'owner.only.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000402', 'client.only.0910@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000403', '00000000-0000-0000-0000-000000000403', 'owner.pm.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000404', '00000000-0000-0000-0000-000000000404', 'owner.accountant.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000405', '00000000-0000-0000-0000-000000000405', 'owner.site.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000406', '00000000-0000-0000-0000-000000000406', 'owner.client.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000407', '00000000-0000-0000-0000-000000000407', 'client.owner.0910@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000408', '00000000-0000-0000-0000-000000000408', 'client.pm.0910@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000409', '00000000-0000-0000-0000-000000000409', 'client.accountant.0910@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000410', '00000000-0000-0000-0000-000000000410', 'client.site.0910@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000411', '00000000-0000-0000-0000-000000000411', 'client.staffonly.0910@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000412', '00000000-0000-0000-0000-000000000412', 'pm.only.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000413', '00000000-0000-0000-0000-000000000413', 'accountant.only.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000414', '00000000-0000-0000-0000-000000000414', 'site.only.0910@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000415', '00000000-0000-0000-0000-000000000415', 'invited.0910@example.test', 'CLIENT', 'INVITED', false, NULL, NULL);

INSERT INTO app.user_profiles (user_id, full_name, job_title, created_by, updated_by)
SELECT u.id, 'Test Person', 'Test Role', '10000000-0000-0000-0000-000000000401', '10000000-0000-0000-0000-000000000401'
FROM app.users AS u
WHERE u.id BETWEEN '10000000-0000-0000-0000-000000000401'::uuid AND '10000000-0000-0000-0000-000000000415'::uuid;

SELECT set_config('app.allow_owner_bootstrap', 'on', true);
INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES ('10000000-0000-0000-0000-000000000401', 'owner_admin', '10000000-0000-0000-0000-000000000401');
SELECT set_config('app.allow_owner_bootstrap', 'off', true);

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000000402', 'client', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000412', 'project_manager', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000413', 'accountant', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000414', 'site_supervisor', '10000000-0000-0000-0000-000000000401');

ALTER TABLE app.user_roles DISABLE TRIGGER user_roles_validate_change;
INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000000403', 'owner_admin', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000403', 'project_manager', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000404', 'owner_admin', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000404', 'accountant', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000405', 'owner_admin', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000405', 'site_supervisor', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000406', 'owner_admin', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000406', 'client', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000407', 'client', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000407', 'owner_admin', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000408', 'client', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000408', 'project_manager', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000409', 'client', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000409', 'accountant', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000410', 'client', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000410', 'site_supervisor', '10000000-0000-0000-0000-000000000401'),
  ('10000000-0000-0000-0000-000000000411', 'project_manager', '10000000-0000-0000-0000-000000000401');
ALTER TABLE app.user_roles ENABLE TRIGGER user_roles_validate_change;

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000401', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (true, ARRAY['owner_admin']::varchar(40)[]) $$,
  'staff with owner_admin only is allowed and returns only owner_admin'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000403', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (true, ARRAY['owner_admin']::varchar(40)[]) $$,
  'staff with owner_admin plus project_manager returns only owner_admin'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000404', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (true, ARRAY['owner_admin']::varchar(40)[]) $$,
  'staff with owner_admin plus accountant returns only owner_admin'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000405', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (true, ARRAY['owner_admin']::varchar(40)[]) $$,
  'staff with owner_admin plus site_supervisor returns only owner_admin'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000406', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'staff with owner_admin plus client is denied'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000402', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (true, ARRAY['client']::varchar(40)[]) $$,
  'client with client only is allowed and returns only client'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000407', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'client with client plus owner_admin is denied'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000408', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'client with client plus project_manager is denied'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000409', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'client with client plus accountant is denied'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000410', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'client with client plus site_supervisor is denied'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000411', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'client with only a staff role is denied'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000412', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'project_manager alone is denied first-release access'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000413', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'accountant alone is denied first-release access'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000414', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'site_supervisor alone is denied first-release access'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000415', true);
SELECT results_eq(
  $$ SELECT account_status, access_allowed, full_name, active_role_codes FROM public.current_account() $$,
  $$ VALUES ('INVITED'::text, false, NULL::varchar(160), ARRAY[]::varchar(40)[]) $$,
  'invited account remains minimal and denied'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000416', true);
SELECT is((SELECT count(*)::integer FROM public.current_account()), 0, 'missing app user still returns zero rows');

SELECT * FROM finish();
ROLLBACK;
