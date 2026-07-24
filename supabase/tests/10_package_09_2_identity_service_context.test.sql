BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(31);

SELECT has_function('app', 'client_identity_context_for_service', ARRAY['uuid','uuid']::name[], 'private service context function exists');
SELECT has_function('public', 'server_client_identity_context', ARRAY['uuid','uuid']::name[], 'public service context gateway exists');
SELECT volatility_is('app', 'client_identity_context_for_service', ARRAY['uuid','uuid']::name[], 'stable', 'private service context is stable');
SELECT volatility_is('public', 'server_client_identity_context', ARRAY['uuid','uuid']::name[], 'stable', 'public service context gateway is stable');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'app.client_identity_context_for_service(uuid, uuid)'::regprocedure), 'private service context is security definer');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.server_client_identity_context(uuid, uuid)'::regprocedure), 'public service context gateway is security definer');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'app.client_identity_context_for_service(uuid, uuid)'::regprocedure), ARRAY['search_path=""'], 'private service context has empty search path');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'public.server_client_identity_context(uuid, uuid)'::regprocedure), ARRAY['search_path=""'], 'public service context gateway has empty search path');
SELECT isnt((SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'app.client_identity_context_for_service(uuid, uuid)'::regprocedure), 'service_role', 'private service context owner is privileged migration owner');
SELECT isnt((SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.server_client_identity_context(uuid, uuid)'::regprocedure), 'service_role', 'public service context gateway owner is privileged migration owner');

SELECT results_eq(
  $$ SELECT parameter_name, data_type
     FROM information_schema.parameters
     WHERE specific_schema = 'public'
       AND specific_name = (
         SELECT specific_name
         FROM information_schema.routines
         WHERE routine_schema = 'public'
           AND routine_name = 'server_client_identity_context'
       )
       AND parameter_mode = 'OUT'
     ORDER BY ordinal_position $$,
  $$ VALUES
     ('client_user_id'::information_schema.sql_identifier, 'uuid'::information_schema.character_data),
     ('auth_subject'::information_schema.sql_identifier, 'uuid'::information_schema.character_data),
     ('normalized_email'::information_schema.sql_identifier, 'text'::information_schema.character_data),
     ('account_status'::information_schema.sql_identifier, 'text'::information_schema.character_data),
     ('is_active'::information_schema.sql_identifier, 'boolean'::information_schema.character_data),
     ('latest_invitation_id'::information_schema.sql_identifier, 'uuid'::information_schema.character_data),
     ('latest_invitation_status'::information_schema.sql_identifier, 'text'::information_schema.character_data) $$,
  'public gateway exposes only the approved return fields'
);

SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc AS p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS acl WHERE p.oid = 'app.client_identity_context_for_service(uuid, uuid)'::regprocedure AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'), 'PUBLIC cannot execute private service context');
SELECT ok(NOT has_function_privilege('anon', 'app.client_identity_context_for_service(uuid, uuid)', 'EXECUTE'), 'anon cannot execute private service context');
SELECT ok(NOT has_function_privilege('authenticated', 'app.client_identity_context_for_service(uuid, uuid)', 'EXECUTE'), 'authenticated cannot execute private service context');
SELECT ok(NOT has_function_privilege('service_role', 'app.client_identity_context_for_service(uuid, uuid)', 'EXECUTE'), 'service_role cannot execute private service context directly');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc AS p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS acl WHERE p.oid = 'public.server_client_identity_context(uuid, uuid)'::regprocedure AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'), 'PUBLIC cannot execute service context gateway');
SELECT ok(NOT has_function_privilege('anon', 'public.server_client_identity_context(uuid, uuid)', 'EXECUTE'), 'anon cannot execute service context gateway');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_client_identity_context(uuid, uuid)', 'EXECUTE'), 'authenticated cannot execute service context gateway');
SELECT ok(has_function_privilege('service_role', 'public.server_client_identity_context(uuid, uuid)', 'EXECUTE'), 'service_role can execute service context gateway');

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000001001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.10@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.10@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.client.10@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.noinvite.10@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff.target.10@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reserved.actor.10@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000001007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inactive.owner.10@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner(
  '00000000-0000-0000-0000-000000001001',
  'owner.10@example.test',
  'Owner Ten',
  decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'),
  'req-10',
  'corr-10'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001001', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, deactivated_at, deactivated_by, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000001002', 'client.10@example.test', 'CLIENT', 'INVITED', false, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001')),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000001003', 'other.client.10@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001')),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000001004', 'client.noinvite.10@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001')),
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000001005', 'staff.target.10@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001')),
  ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000001006', 'reserved.actor.10@example.test', 'STAFF', 'ACTIVE', true, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001')),
  ('10000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000001007', 'inactive.owner.10@example.test', 'STAFF', 'SUSPENDED', false, NULL, NULL, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000000003', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), true),
  ('10000000-0000-0000-0000-000000000004', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), true),
  ('10000000-0000-0000-0000-000000000006', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), true),
  ('10000000-0000-0000-0000-000000000007', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), true);

INSERT INTO app.user_invitations (id, invited_user_id, token_hash, status, expires_at, invited_by, created_at, accepted_at, revoked_at, revoked_by, revoke_reason)
VALUES
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', decode('0101010101010101010101010101010101010101010101010101010101010101','hex'), 'REVOKED', '2026-01-08 00:00:00+00', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), '2026-01-01 00:00:00+00', NULL, '2026-01-02 00:00:00+00', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), 'test'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', decode('0202020202020202020202020202020202020202020202020202020202020202','hex'), 'EXPIRED', '2026-01-09 00:00:00+00', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), '2026-01-02 00:00:00+00', NULL, NULL, NULL, NULL),
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', decode('0404040404040404040404040404040404040404040404040404040404040404','hex'), 'EXPIRED', '2026-01-10 00:00:00+00', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), '2026-01-03 00:00:00+00', NULL, NULL, NULL, NULL),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', decode('0303030303030303030303030303030303030303030303030303030303030303','hex'), 'EXPIRED', '2026-01-10 00:00:00+00', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), '2026-01-03 00:00:00+00', NULL, NULL, NULL, NULL),
  ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000003', decode('0505050505050505050505050505050505050505050505050505050505050505','hex'), 'ACCEPTED', '2026-01-08 00:00:00+00', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000001001'), '2026-01-01 00:00:00+00', '2026-01-02 00:00:00+00', NULL, NULL, NULL);

SELECT results_eq(
  $$ SELECT client_user_id, auth_subject, normalized_email, account_status, is_active, latest_invitation_id, latest_invitation_status
     FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001001', '10000000-0000-0000-0000-000000000002') $$,
  $$ VALUES (
     '10000000-0000-0000-0000-000000000002'::uuid,
     '00000000-0000-0000-0000-000000001002'::uuid,
     'client.10@example.test'::text,
     'INVITED'::text,
     false,
     '20000000-0000-0000-0000-000000000004'::uuid,
     'EXPIRED'::text
  ) $$,
  'active Owner retrieves only the requested Client with deterministic latest invitation'
);

SELECT is((SELECT count(*)::integer FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001003', '10000000-0000-0000-0000-000000000002')), 0, 'Client caller is denied');
SELECT is((SELECT count(*)::integer FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001006', '10000000-0000-0000-0000-000000000002')), 0, 'reserved-role Staff caller is denied');
SELECT is((SELECT count(*)::integer FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001007', '10000000-0000-0000-0000-000000000002')), 0, 'inactive Owner caller is denied');
SELECT is((SELECT count(*)::integer FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001001', '10000000-0000-0000-0000-000000000005')), 0, 'Staff target is rejected');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001001', '10000000-0000-0000-0000-000000000002') WHERE normalized_email = 'other.client.10@example.test'), 'unrelated Client information is not returned');
SELECT results_eq(
  $$ SELECT latest_invitation_id, latest_invitation_status
     FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001001', '10000000-0000-0000-0000-000000000004') $$,
  $$ VALUES (NULL::uuid, NULL::text) $$,
  'Client with no invitation returns null invitation fields safely'
);

SET LOCAL ROLE service_role;
SELECT results_eq(
  $$ SELECT normalized_email
     FROM public.server_client_identity_context('00000000-0000-0000-0000-000000001001', '10000000-0000-0000-0000-000000000002') $$,
  $$ VALUES ('client.10@example.test'::text) $$,
  'service gateway executes correctly despite forced RLS'
);
RESET ROLE;

SELECT ok(NOT has_table_privilege('service_role', 'app.users', 'SELECT'), 'service_role has no direct users table select grant');
SELECT ok(NOT has_table_privilege('service_role', 'app.user_invitations', 'SELECT'), 'service_role has no direct invitations table select grant');
SELECT ok(NOT has_table_privilege('authenticated', 'app.users', 'SELECT'), 'authenticated direct app.users access remains absent');
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_invitations', 'SELECT'), 'authenticated direct invitation access remains absent');

SELECT * FROM finish();
ROLLBACK;
