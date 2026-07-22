BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(30);

-- Supabase Auth fixtures. Fictional values only.
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
VALUES
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.one@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.two@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client@example.test', '', now(), '{}', '{}', now(), now());

INSERT INTO app.users (
  id, auth_subject, email, user_type, status, is_active
)
VALUES
  ('10000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000101', 'owner.one@example.test', 'STAFF', 'ACTIVE', true),
  ('10000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000102', 'owner.two@example.test', 'STAFF', 'ACTIVE', true),
  ('10000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000103', 'pm@example.test', 'STAFF', 'ACTIVE', true),
  ('10000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000104', 'client@example.test', 'CLIENT', 'ACTIVE', true);

SELECT set_config('app.allow_owner_bootstrap', 'on', true);
INSERT INTO app.user_roles (user_id, role_code, assigned_by)
VALUES (
  '10000000-0000-0000-0000-000000000101',
  'owner_admin',
  '10000000-0000-0000-0000-000000000101'
);
SELECT set_config('app.allow_owner_bootstrap', 'off', true);

SELECT is((SELECT count(*)::integer FROM app.roles), 5, 'exactly five roles are seeded');
SELECT results_eq(
  $$ SELECT code FROM app.roles ORDER BY code $$,
  $$ VALUES ('accountant'::varchar), ('client'::varchar), ('owner_admin'::varchar), ('project_manager'::varchar), ('site_supervisor'::varchar) $$,
  'role codes match the approved allowlist'
);

SELECT lives_ok(
  $$ INSERT INTO app.contractor_profiles (
       legal_name, display_name, default_reporting_currency_code, created_by, updated_by
     ) VALUES (
       'Fictional Contractor Sdn. Bhd.', 'Fictional Contractor', 'USD',
       '10000000-0000-0000-0000-000000000101',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  'the single contractor profile can be created'
);
SELECT throws_ok(
  $$ INSERT INTO app.contractor_profiles (
       legal_name, display_name, default_reporting_currency_code, created_by, updated_by
     ) VALUES (
       'Second Contractor', 'Second Contractor', 'USD',
       '10000000-0000-0000-0000-000000000101',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  '23505',
  NULL,
  'a second contractor row is rejected'
);

SELECT throws_ok(
  $$ INSERT INTO app.users (
       auth_subject, email, user_type, status, is_active
     ) VALUES (
       '00000000-0000-0000-0000-000000000101', 'duplicate-auth@example.test',
       'STAFF', 'ACTIVE', true
     ) $$,
  '23505', NULL, 'authentication subject is unique'
);
SELECT throws_ok(
  $$ INSERT INTO app.users (
       auth_subject, email, user_type, status, is_active
     ) VALUES (
       gen_random_uuid(), 'owner.one@example.test', 'STAFF', 'ACTIVE', true
     ) $$,
  '23505', NULL, 'email is unique case-insensitively'
);
SELECT throws_ok(
  $$ UPDATE app.users
     SET auth_subject = '00000000-0000-0000-0000-000000000999'
     WHERE id = '10000000-0000-0000-0000-000000000103' $$,
  '23514', 'Authentication identity cannot be changed.',
  'authentication identity is immutable'
);

SELECT throws_ok(
  $$ UPDATE app.users
     SET status = 'ACTIVE', is_active = false
     WHERE id = '10000000-0000-0000-0000-000000000103' $$,
  '23514', NULL,
  'user lifecycle status and active flag must remain consistent'
);

SELECT lives_ok(
  $$ INSERT INTO app.user_profiles (
       user_id, full_name, created_by, updated_by
     ) VALUES (
       '10000000-0000-0000-0000-000000000103', 'Fictional Project Manager',
       '10000000-0000-0000-0000-000000000101',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  'a one-to-one user profile can be created'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_profiles (
       user_id, full_name, created_by, updated_by
     ) VALUES (
       '10000000-0000-0000-0000-000000000103', 'Duplicate Profile',
       '10000000-0000-0000-0000-000000000101',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  '23505', NULL, 'a second profile for one user is rejected'
);

SELECT lives_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000103', 'project_manager',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  'an active owner can assign a staff role'
);
SELECT lives_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000103', 'accountant',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  'multiple predefined staff roles are permitted'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000103', 'project_manager',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  '23505', NULL, 'duplicate active role assignment is rejected'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000104', 'project_manager',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  '23514', 'Client identities may receive only the client role.',
  'a client cannot receive a staff role'
);
SELECT lives_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000104', 'client',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  'a client can receive the client role'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000103', 'client',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  '23514', 'Staff identities cannot receive the client role.',
  'a staff user cannot receive the client role'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000102', 'owner_admin',
       '10000000-0000-0000-0000-000000000103'
     ) $$,
  '42501', 'Only an active Owner/Administrator may assign roles.',
  'a non-owner cannot assign roles'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000101', 'accountant',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  '42501', 'Users may not assign roles to themselves.',
  'self-role assignment is rejected after bootstrap'
);

SELECT throws_ok(
  $$ UPDATE app.user_roles
     SET is_active = false,
         revoked_at = now(),
         revoked_by = '10000000-0000-0000-0000-000000000103',
         revoke_reason = 'Unauthorised revocation attempt'
     WHERE user_id = '10000000-0000-0000-0000-000000000103'
       AND role_code = 'accountant'
       AND is_active $$,
  '42501', 'Only an active Owner/Administrator may revoke roles.',
  'a non-owner cannot revoke roles'
);
SELECT lives_ok(
  $$ UPDATE app.user_roles
     SET is_active = false,
         revoked_at = now(),
         revoked_by = '10000000-0000-0000-0000-000000000101',
         revoke_reason = 'Role no longer required'
     WHERE user_id = '10000000-0000-0000-0000-000000000103'
       AND role_code = 'accountant'
       AND is_active $$,
  'an active owner can revoke a role while retaining history'
);
SELECT throws_ok(
  $$ UPDATE app.user_roles
     SET is_active = true, revoked_at = NULL, revoked_by = NULL, revoke_reason = NULL
     WHERE user_id = '10000000-0000-0000-0000-000000000103'
       AND role_code = 'accountant'
       AND NOT is_active $$,
  '23514', 'Revoked role history cannot be edited or reactivated.',
  'revoked role history cannot be reactivated in place'
);
SELECT throws_ok(
  $$ UPDATE app.user_roles
     SET role_code = 'site_supervisor'
     WHERE user_id = '10000000-0000-0000-0000-000000000103'
       AND role_code = 'project_manager'
       AND is_active $$,
  '23514', 'Role assignment identity and assignment history are immutable.',
  'an existing role assignment cannot be rewritten as another role'
);
SELECT throws_ok(
  $$ DELETE FROM app.user_roles
     WHERE user_id = '10000000-0000-0000-0000-000000000103'
       AND role_code = 'project_manager'
       AND is_active $$,
  '23514', 'user_roles rows cannot be permanently deleted.',
  'role-assignment history cannot be hard deleted'
);

SELECT throws_ok(
  $$ UPDATE app.user_roles
     SET is_active = false,
         revoked_at = now(),
         revoked_by = '10000000-0000-0000-0000-000000000101',
         revoke_reason = 'Test last-owner protection'
     WHERE user_id = '10000000-0000-0000-0000-000000000101'
       AND role_code = 'owner_admin'
       AND is_active $$,
  '23514', 'At least one active Owner/Administrator must remain.',
  'the last active owner role cannot be revoked'
);
SELECT throws_ok(
  $$ UPDATE app.users
     SET status = 'DISABLED', is_active = false,
         deactivated_at = now(),
         deactivated_by = '10000000-0000-0000-0000-000000000101'
     WHERE id = '10000000-0000-0000-0000-000000000101' $$,
  '23514', 'The last active Owner/Administrator cannot be deactivated.',
  'the last active owner user cannot be disabled'
);

SELECT lives_ok(
  $$ INSERT INTO app.user_roles (user_id, role_code, assigned_by)
     VALUES (
       '10000000-0000-0000-0000-000000000102', 'owner_admin',
       '10000000-0000-0000-0000-000000000101'
     ) $$,
  'a second owner can be assigned by the current owner'
);
SELECT lives_ok(
  $$ UPDATE app.users
     SET status = 'DISABLED', is_active = false,
         deactivated_at = now(),
         deactivated_by = '10000000-0000-0000-0000-000000000102'
     WHERE id = '10000000-0000-0000-0000-000000000101' $$,
  'one owner can be disabled when another active owner remains'
);
SELECT throws_ok(
  $$ DELETE FROM app.roles WHERE code = 'accountant' $$,
  '23514', 'System role definitions cannot be deleted.',
  'system roles cannot be deleted'
);
SELECT throws_ok(
  $$ UPDATE app.roles SET name = 'Changed' WHERE code = 'accountant' $$,
  '23514', 'System role definition fields are immutable.',
  'system role definition fields cannot be changed'
);
SELECT throws_ok(
  $$ DELETE FROM app.users WHERE id = '10000000-0000-0000-0000-000000000103' $$,
  '23514', 'users rows cannot be permanently deleted.',
  'application identities cannot be hard deleted'
);

SELECT * FROM finish();
ROLLBACK;
