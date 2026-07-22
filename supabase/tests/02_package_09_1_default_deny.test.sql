BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(25);

SELECT ok(relrowsecurity, 'currencies has RLS enabled')
FROM pg_class WHERE oid = 'app.currencies'::regclass;
SELECT ok(relforcerowsecurity, 'currencies forces RLS')
FROM pg_class WHERE oid = 'app.currencies'::regclass;
SELECT ok(relrowsecurity, 'contractor_profiles has RLS enabled')
FROM pg_class WHERE oid = 'app.contractor_profiles'::regclass;
SELECT ok(relforcerowsecurity, 'contractor_profiles forces RLS')
FROM pg_class WHERE oid = 'app.contractor_profiles'::regclass;
SELECT ok(relrowsecurity, 'users has RLS enabled')
FROM pg_class WHERE oid = 'app.users'::regclass;
SELECT ok(relforcerowsecurity, 'users forces RLS')
FROM pg_class WHERE oid = 'app.users'::regclass;
SELECT ok(relrowsecurity, 'user_profiles has RLS enabled')
FROM pg_class WHERE oid = 'app.user_profiles'::regclass;
SELECT ok(relforcerowsecurity, 'user_profiles forces RLS')
FROM pg_class WHERE oid = 'app.user_profiles'::regclass;
SELECT ok(relrowsecurity, 'roles has RLS enabled')
FROM pg_class WHERE oid = 'app.roles'::regclass;
SELECT ok(relforcerowsecurity, 'roles forces RLS')
FROM pg_class WHERE oid = 'app.roles'::regclass;
SELECT ok(relrowsecurity, 'user_roles has RLS enabled')
FROM pg_class WHERE oid = 'app.user_roles'::regclass;
SELECT ok(relforcerowsecurity, 'user_roles forces RLS')
FROM pg_class WHERE oid = 'app.user_roles'::regclass;

SELECT is((SELECT count(*)::integer FROM pg_policies WHERE schemaname = 'app'), 0,
  'Package 09.1 creates no application-facing RLS policies');

SELECT ok(NOT has_table_privilege('anon', 'app.currencies', 'SELECT'), 'anon cannot select currencies');
SELECT ok(NOT has_table_privilege('authenticated', 'app.currencies', 'SELECT'), 'authenticated cannot select currencies');
SELECT ok(NOT has_table_privilege('anon', 'app.contractor_profiles', 'SELECT'), 'anon cannot select contractor profile');
SELECT ok(NOT has_table_privilege('authenticated', 'app.contractor_profiles', 'SELECT'), 'authenticated cannot select contractor profile');
SELECT ok(NOT has_table_privilege('anon', 'app.users', 'SELECT'), 'anon cannot select users');
SELECT ok(NOT has_table_privilege('authenticated', 'app.users', 'SELECT'), 'authenticated cannot select users');
SELECT ok(NOT has_table_privilege('anon', 'app.user_profiles', 'SELECT'), 'anon cannot select user profiles');
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_profiles', 'SELECT'), 'authenticated cannot select user profiles');
SELECT ok(NOT has_table_privilege('anon', 'app.roles', 'SELECT'), 'anon cannot select roles');
SELECT ok(NOT has_table_privilege('authenticated', 'app.roles', 'SELECT'), 'authenticated cannot select roles');
SELECT ok(NOT has_table_privilege('anon', 'app.user_roles', 'SELECT'), 'anon cannot select user roles');
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_roles', 'SELECT'), 'authenticated cannot select user roles');

SELECT * FROM finish();
ROLLBACK;
