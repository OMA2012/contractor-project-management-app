BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(29);

SELECT has_function('app', 'first_owner_delivery_context_for_service', ARRAY['uuid','citext']::name[], 'private first-owner delivery context exists');
SELECT has_function('public', 'server_first_owner_delivery_context', ARRAY['uuid','citext']::name[], 'public first-owner delivery context gateway exists');
SELECT volatility_is('app', 'first_owner_delivery_context_for_service', ARRAY['uuid','citext']::name[], 'stable', 'private context is stable');
SELECT volatility_is('public', 'server_first_owner_delivery_context', ARRAY['uuid','citext']::name[], 'stable', 'public context gateway is stable');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'app.first_owner_delivery_context_for_service(uuid, citext)'::regprocedure), 'private context is security definer');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.server_first_owner_delivery_context(uuid, citext)'::regprocedure), 'public context gateway is security definer');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'app.first_owner_delivery_context_for_service(uuid, citext)'::regprocedure), ARRAY['search_path=""'], 'private context has empty search path');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'public.server_first_owner_delivery_context(uuid, citext)'::regprocedure), ARRAY['search_path=""'], 'public gateway has empty search path');
SELECT isnt((SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.server_first_owner_delivery_context(uuid, citext)'::regprocedure), 'service_role', 'gateway owner is privileged migration owner');
SELECT is(
  (SELECT array_agg(parameter_name::text ORDER BY ordinal_position) FROM information_schema.routines r JOIN information_schema.parameters p ON p.specific_schema = r.specific_schema AND p.specific_name = r.specific_name WHERE r.specific_schema = 'public' AND r.routine_name = 'server_first_owner_delivery_context' AND p.parameter_mode = 'OUT'),
  ARRAY['owner_user_id', 'auth_subject', 'normalized_email', 'account_status', 'is_active', 'invitation_id', 'invitation_status', 'expires_at'],
  'gateway returns exact safe fields'
);
SELECT ok(NOT has_function_privilege('anon', 'app.first_owner_delivery_context_for_service(uuid, citext)', 'EXECUTE'), 'anon cannot execute private context');
SELECT ok(NOT has_function_privilege('authenticated', 'app.first_owner_delivery_context_for_service(uuid, citext)', 'EXECUTE'), 'authenticated cannot execute private context');
SELECT ok(NOT has_function_privilege('service_role', 'app.first_owner_delivery_context_for_service(uuid, citext)', 'EXECUTE'), 'service_role cannot execute private context');
SELECT ok(NOT has_function_privilege('anon', 'public.server_first_owner_delivery_context(uuid, citext)', 'EXECUTE'), 'anon cannot execute public gateway');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_first_owner_delivery_context(uuid, citext)', 'EXECUTE'), 'authenticated cannot execute public gateway');
SELECT ok(has_function_privilege('service_role', 'public.server_first_owner_delivery_context(uuid, citext)', 'EXECUTE'), 'service_role can execute public gateway');

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000001101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.11@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001191', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'active.11@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001192', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'suspended.11@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001193', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'disabled.11@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001194', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'missing.role.11@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'conflict.11@example.test', '', now(), '{}', '{}', now(), now());

SET ROLE service_role;
SELECT * FROM public.server_bootstrap_first_owner('00000000-0000-0000-0000-000000001101', 'owner.11@example.test', 'Owner Eleven', decode('1111111111111111111111111111111111111111111111111111111111111111','hex'), 'req-11', 'corr-11');
RESET ROLE;

SELECT results_eq(
  $$ SELECT owner_user_id, auth_subject, normalized_email, account_status, is_active, invitation_status FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001101', 'owner.11@example.test') $$,
  $$ SELECT id, auth_subject, email::text, status::text, is_active, 'PENDING'::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001101' $$,
  'same identity context is returned'
);
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001102', 'owner.11@example.test')), 0, 'different auth subject rejected');
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001101', 'other.11@example.test')), 0, 'different email rejected');

SAVEPOINT active_owner_case;
SELECT set_config('app.allow_owner_bootstrap', 'on', true);
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active) VALUES ('10000000-0000-0000-0000-000000001191', '00000000-0000-0000-0000-000000001191', 'active.11@example.test', 'STAFF', 'ACTIVE', true);
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by) VALUES ('10000000-0000-0000-0000-000000001191', 'Active Owner', '10000000-0000-0000-0000-000000001191', '10000000-0000-0000-0000-000000001191');
INSERT INTO app.user_roles (user_id, role_code, assigned_by) VALUES ('10000000-0000-0000-0000-000000001191', 'owner_admin', '10000000-0000-0000-0000-000000001191');
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001191', 'active.11@example.test')), 0, 'active Owner rejected');
ROLLBACK TO SAVEPOINT active_owner_case;

SAVEPOINT suspended_owner_case;
SELECT set_config('app.allow_owner_bootstrap', 'on', true);
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active) VALUES ('10000000-0000-0000-0000-000000001192', '00000000-0000-0000-0000-000000001192', 'suspended.11@example.test', 'STAFF', 'SUSPENDED', false);
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by) VALUES ('10000000-0000-0000-0000-000000001192', 'Suspended Owner', '10000000-0000-0000-0000-000000001192', '10000000-0000-0000-0000-000000001192');
INSERT INTO app.user_roles (user_id, role_code, assigned_by) VALUES ('10000000-0000-0000-0000-000000001192', 'owner_admin', '10000000-0000-0000-0000-000000001192');
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001192', 'suspended.11@example.test')), 0, 'suspended Owner rejected');
ROLLBACK TO SAVEPOINT suspended_owner_case;

SAVEPOINT disabled_owner_case;
SELECT set_config('app.allow_owner_bootstrap', 'on', true);
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, deactivated_at, deactivated_by) VALUES ('10000000-0000-0000-0000-000000001193', '00000000-0000-0000-0000-000000001193', 'disabled.11@example.test', 'STAFF', 'DISABLED', false, now(), '10000000-0000-0000-0000-000000001193');
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by) VALUES ('10000000-0000-0000-0000-000000001193', 'Disabled Owner', '10000000-0000-0000-0000-000000001193', '10000000-0000-0000-0000-000000001193');
INSERT INTO app.user_roles (user_id, role_code, assigned_by) VALUES ('10000000-0000-0000-0000-000000001193', 'owner_admin', '10000000-0000-0000-0000-000000001193');
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001193', 'disabled.11@example.test')), 0, 'disabled Owner rejected');
ROLLBACK TO SAVEPOINT disabled_owner_case;
UPDATE app.user_invitations SET created_at = now() - interval '7 days 1 second', expires_at = now() - interval '1 second' WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001101');
SELECT throws_ok($$ SELECT * FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001101', 'owner.11@example.test') $$, 'P0001', 'First Owner invitation expired.', 'expired invitation rejected with safe failure');
UPDATE app.user_invitations SET created_at = now(), expires_at = now() + interval '7 days' WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001101');

SAVEPOINT missing_owner_role_case;
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active) VALUES ('10000000-0000-0000-0000-000000001194', '00000000-0000-0000-0000-000000001194', 'missing.role.11@example.test', 'STAFF', 'INVITED', false);
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by) VALUES ('10000000-0000-0000-0000-000000001194', 'Missing Role Owner', '10000000-0000-0000-0000-000000001194', '10000000-0000-0000-0000-000000001194');
INSERT INTO app.user_invitations (invited_user_id, token_hash, status, expires_at, invited_by) VALUES ('10000000-0000-0000-0000-000000001194', decode('1414141414141414141414141414141414141414141414141414141414141414','hex'), 'PENDING', now() + interval '7 days', '10000000-0000-0000-0000-000000001194');
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001194', 'missing.role.11@example.test')), 0, 'missing owner_admin rejected');
ROLLBACK TO SAVEPOINT missing_owner_role_case;

SAVEPOINT conflicting_owner_case;
SELECT set_config('app.allow_owner_bootstrap', 'on', true);
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active) VALUES ('10000000-0000-0000-0000-000000001199', '00000000-0000-0000-0000-000000001199', 'conflict.11@example.test', 'STAFF', 'INVITED', false);
INSERT INTO app.user_roles (user_id, role_code, assigned_by) VALUES ('10000000-0000-0000-0000-000000001199', 'owner_admin', '10000000-0000-0000-0000-000000001199');
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001101', 'owner.11@example.test')), 0, 'conflicting Owner rejected');
ROLLBACK TO SAVEPOINT conflicting_owner_case;

UPDATE app.user_invitations SET status = 'EXPIRED' WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001101');
INSERT INTO app.user_invitations (id, invited_user_id, token_hash, status, created_at, expires_at, invited_by) VALUES ('20000000-0000-0000-0000-000000001199', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001101'), decode('1212121212121212121212121212121212121212121212121212121212121212','hex'), 'PENDING', now() + interval '1 second', now() + interval '7 days 1 second', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001101'));
SELECT is((SELECT invitation_id FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001101', 'owner.11@example.test')), '20000000-0000-0000-0000-000000001199'::uuid, 'latest invitation selected deterministically');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001101', 'owner.11@example.test') WHERE normalized_email <> 'owner.11@example.test'), 'no unrelated private data exposed');
ALTER TABLE app.users FORCE ROW LEVEL SECURITY;
SELECT is((SELECT count(*)::integer FROM public.server_first_owner_delivery_context('00000000-0000-0000-0000-000000001101', 'owner.11@example.test')), 1, 'forced-RLS execution remains correct');
SELECT ok(NOT has_table_privilege('service_role', 'app.users', 'SELECT') AND NOT has_table_privilege('authenticated', 'app.user_invitations', 'SELECT'), 'no direct table grants introduced');

SELECT * FROM finish();
ROLLBACK;
