BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(37);

SELECT has_function('public', 'current_account', ARRAY[]::name[], 'current_account rpc exists with zero arguments');
SELECT function_lang_is('public', 'current_account', ARRAY[]::name[], 'sql', 'current_account is a sql function');
SELECT volatility_is('public', 'current_account', ARRAY[]::name[], 'stable', 'current_account is stable');
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE oid = 'public.current_account()'::regprocedure),
  true,
  'current_account is security definer'
);
SELECT is(
  (SELECT proconfig FROM pg_proc WHERE oid = 'public.current_account()'::regprocedure),
  ARRAY['search_path=""'],
  'current_account sets an empty search path'
);
SELECT isnt(
  (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.current_account()'::regprocedure),
  'anon',
  'current_account owner is not anon'
);
SELECT isnt(
  (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.current_account()'::regprocedure),
  'authenticated',
  'current_account owner is not authenticated'
);

SELECT ok(
  coalesce(
    array_to_string((SELECT proacl FROM pg_proc WHERE oid = 'public.current_account()'::regprocedure), ','),
    ''
  ) !~ '(^|,)=X',
  'PUBLIC cannot execute current_account'
);
SELECT ok(NOT has_function_privilege('anon', 'public.current_account()', 'EXECUTE'), 'anon cannot execute current_account');
SELECT ok(has_function_privilege('authenticated', 'public.current_account()', 'EXECUTE'), 'authenticated can execute current_account');
SELECT ok(NOT has_schema_privilege('authenticated', 'app', 'USAGE'), 'authenticated has no app schema usage');
SELECT ok(NOT has_schema_privilege('anon', 'app', 'USAGE'), 'anon has no app schema usage');

SELECT ok(NOT has_table_privilege('authenticated', 'app.users', 'SELECT'), 'authenticated cannot select users');
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_profiles', 'SELECT'), 'authenticated cannot select user_profiles');
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_roles', 'SELECT'), 'authenticated cannot select user_roles');
SELECT ok(NOT has_table_privilege('authenticated', 'app.roles', 'SELECT'), 'authenticated cannot select roles');
SELECT ok(NOT has_table_privilege('authenticated', 'app.users', 'INSERT,UPDATE,DELETE'), 'authenticated cannot write users');
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_roles', 'INSERT,UPDATE,DELETE'), 'authenticated cannot write user_roles');

SELECT ok(relforcerowsecurity, 'users still forces RLS') FROM pg_class WHERE oid = 'app.users'::regclass;
SELECT ok(relforcerowsecurity, 'user_profiles still forces RLS') FROM pg_class WHERE oid = 'app.user_profiles'::regclass;
SELECT ok(relforcerowsecurity, 'user_roles still forces RLS') FROM pg_class WHERE oid = 'app.user_roles'::regclass;
SELECT ok(relforcerowsecurity, 'roles still forces RLS') FROM pg_class WHERE oid = 'app.roles'::regclass;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invited@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000204', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'suspended@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000205', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'disabled@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000206', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'norole@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000207', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'badcombo@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000208', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'revoked@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000209', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff.clientonly@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000210', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.staffrole@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000299', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'missing@example.test', '', now(), '{}', '{}', now(), now());

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, deactivated_at, deactivated_by)
VALUES
  ('10000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000201', 'staff@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000202', 'client@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000203', 'invited@example.test', 'STAFF', 'INVITED', false, NULL, NULL),
  ('10000000-0000-0000-0000-000000000204', '00000000-0000-0000-0000-000000000204', 'suspended@example.test', 'STAFF', 'SUSPENDED', false, NULL, NULL),
  ('10000000-0000-0000-0000-000000000205', '00000000-0000-0000-0000-000000000205', 'disabled@example.test', 'STAFF', 'DISABLED', false, now(), '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000206', '00000000-0000-0000-0000-000000000206', 'norole@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000207', '00000000-0000-0000-0000-000000000207', 'badcombo@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000208', '00000000-0000-0000-0000-000000000208', 'revoked@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000209', '00000000-0000-0000-0000-000000000209', 'staff.clientonly@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL),
  ('10000000-0000-0000-0000-000000000210', '00000000-0000-0000-0000-000000000210', 'client.staffrole@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL);

INSERT INTO app.user_profiles (user_id, full_name, job_title, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000000201', 'Staff Person', 'Project Manager', '10000000-0000-0000-0000-000000000201', '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000202', 'Client Person', 'Owner', '10000000-0000-0000-0000-000000000201', '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000203', 'Pending Person', 'Pending', '10000000-0000-0000-0000-000000000201', '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000206', 'No Role Person', 'Staff', '10000000-0000-0000-0000-000000000201', '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000208', 'Revoked Person', 'Staff', '10000000-0000-0000-0000-000000000201', '10000000-0000-0000-0000-000000000201');

SELECT set_config('app.allow_owner_bootstrap', 'on', true);
INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES ('10000000-0000-0000-0000-000000000201', 'owner_admin', '10000000-0000-0000-0000-000000000201');
SELECT set_config('app.allow_owner_bootstrap', 'off', true);

INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000000202', 'client', '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000207', 'client', '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000208', 'accountant', '10000000-0000-0000-0000-000000000201');

ALTER TABLE app.user_roles DISABLE TRIGGER user_roles_validate_change;
INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES
  ('10000000-0000-0000-0000-000000000209', 'client', '10000000-0000-0000-0000-000000000201'),
  ('10000000-0000-0000-0000-000000000210', 'accountant', '10000000-0000-0000-0000-000000000201');
ALTER TABLE app.user_roles ENABLE TRIGGER user_roles_validate_change;

UPDATE app.user_roles
SET is_active = false,
    revoked_at = now(),
    revoked_by = '10000000-0000-0000-0000-000000000201',
    revoke_reason = 'revoked for test'
WHERE user_id = '10000000-0000-0000-0000-000000000208'
  AND role_code = 'accountant';

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000299', true);
SELECT is((SELECT count(*)::integer FROM public.current_account()), 0, 'missing app user returns zero rows');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000203', true);
SELECT results_eq(
  $$ SELECT account_status, access_allowed, full_name, active_role_codes FROM public.current_account() $$,
  $$ VALUES ('INVITED'::text, false, NULL::varchar(160), ARRAY[]::varchar(40)[]) $$,
  'invited account returns minimal denied row'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000204', true);
SELECT results_eq(
  $$ SELECT account_status, access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES ('SUSPENDED'::text, false, ARRAY[]::varchar(40)[]) $$,
  'suspended account returns minimal denied row'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000205', true);
SELECT results_eq(
  $$ SELECT account_status, access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES ('DISABLED'::text, false, ARRAY[]::varchar(40)[]) $$,
  'disabled account returns minimal denied row'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
SELECT results_eq(
  $$ SELECT account_status, is_active, access_allowed, user_type, full_name, job_title, active_role_codes FROM public.current_account() $$,
  $$ VALUES ('ACTIVE'::text, true, true, 'STAFF'::text, 'Staff Person'::varchar(160), 'Project Manager'::varchar(120), ARRAY['owner_admin']::varchar(40)[]) $$,
  'valid staff account returns trusted staff data and excludes revoked role'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000202', true);
SELECT results_eq(
  $$ SELECT account_status, is_active, access_allowed, user_type, full_name, active_role_codes FROM public.current_account() $$,
  $$ VALUES ('ACTIVE'::text, true, true, 'CLIENT'::text, 'Client Person'::varchar(160), ARRAY['client']::varchar(40)[]) $$,
  'valid client account returns trusted client data'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000206', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'active user with no role is denied with empty role array'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000207', true);
SELECT results_eq(
  $$ SELECT access_allowed, user_type, active_role_codes FROM public.current_account() $$,
  $$ VALUES (true, 'CLIENT'::text, ARRAY['client']::varchar(40)[]) $$,
  'valid client with only client role is allowed'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000209', true);
SELECT results_eq(
  $$ SELECT access_allowed, user_type, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, 'STAFF'::text, ARRAY[]::varchar(40)[]) $$,
  'staff user with only client role is denied and returns no authorized role set'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000210', true);
SELECT results_eq(
  $$ SELECT access_allowed, user_type, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, 'CLIENT'::text, ARRAY[]::varchar(40)[]) $$,
  'client user with a staff role is denied and returns no authorized role set'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000208', true);
SELECT results_eq(
  $$ SELECT access_allowed, active_role_codes FROM public.current_account() $$,
  $$ VALUES (false, ARRAY[]::varchar(40)[]) $$,
  'revoked roles are excluded'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
SELECT ok(NOT EXISTS (
  SELECT 1 FROM public.current_account()
  WHERE application_user_id = '10000000-0000-0000-0000-000000000202'
), 'caller cannot retrieve another user');
SELECT ok((SELECT active_role_codes IS NOT NULL FROM public.current_account()), 'role codes are never null');
SELECT is((SELECT count(*)::integer FROM app.roles), 5, 'exactly five predefined role codes remain');
SELECT results_eq(
  $$ SELECT code FROM app.roles ORDER BY code $$,
  $$ VALUES ('accountant'::varchar), ('client'::varchar), ('owner_admin'::varchar), ('project_manager'::varchar), ('site_supervisor'::varchar) $$,
  'predefined role codes remain exact'
);

SELECT * FROM finish();
ROLLBACK;
