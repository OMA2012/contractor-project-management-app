BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(31);

SELECT has_table('app', 'user_invitations', 'user_invitations table exists');
SELECT has_column('app', 'user_invitations', 'id', 'user_invitations.id exists');
SELECT has_column('app', 'user_invitations', 'invited_user_id', 'user_invitations.invited_user_id exists');
SELECT has_column('app', 'user_invitations', 'token_hash', 'user_invitations.token_hash exists');
SELECT col_type_is('app', 'user_invitations', 'token_hash', 'bytea', 'token_hash is bytea');
SELECT has_column('app', 'user_invitations', 'status', 'user_invitations.status exists');
SELECT has_column('app', 'user_invitations', 'expires_at', 'user_invitations.expires_at exists');
SELECT has_column('app', 'user_invitations', 'accepted_at', 'user_invitations.accepted_at exists');
SELECT has_column('app', 'user_invitations', 'revoked_at', 'user_invitations.revoked_at exists');
SELECT has_column('app', 'user_invitations', 'revoked_by', 'user_invitations.revoked_by exists');
SELECT has_column('app', 'user_invitations', 'revoke_reason', 'user_invitations.revoke_reason exists');
SELECT has_column('app', 'user_invitations', 'invited_by', 'user_invitations.invited_by exists');
SELECT has_column('app', 'user_invitations', 'created_at', 'user_invitations.created_at exists');
SELECT has_column('app', 'user_invitations', 'resent_from_invitation_id', 'user_invitations.resent_from_invitation_id exists');
SELECT has_column('app', 'user_invitations', 'version_number', 'user_invitations.version_number exists');
SELECT hasnt_column('app', 'user_invitations', 'email', 'user_invitations does not duplicate email');
SELECT hasnt_column('app', 'user_invitations', 'auth_subject', 'user_invitations does not duplicate auth subject');
SELECT hasnt_column('app', 'user_invitations', 'plaintext_token', 'user_invitations has no plaintext token');
SELECT hasnt_column('app', 'user_invitations', 'application_user_id', 'user_invitations uses invited_user_id instead of duplicate application_user_id');
SELECT ok(relrowsecurity, 'user_invitations has RLS enabled') FROM pg_class WHERE oid = 'app.user_invitations'::regclass;
SELECT ok(relforcerowsecurity, 'user_invitations forces RLS') FROM pg_class WHERE oid = 'app.user_invitations'::regclass;
SELECT ok(NOT has_table_privilege('authenticated', 'app.user_invitations', 'INSERT,UPDATE,DELETE'), 'authenticated cannot write user_invitations');

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.0912@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000602', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invite.0912@example.test', '', now(), '{}', '{}', now(), now());

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active)
VALUES
  ('10000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000601', 'owner.0912@example.test', 'STAFF', 'ACTIVE', true),
  ('10000000-0000-0000-0000-000000000602', '00000000-0000-0000-0000-000000000602', 'invite.0912@example.test', 'CLIENT', 'INVITED', false);

SELECT lives_ok(
  $$ INSERT INTO app.user_invitations (
       id,
       invited_user_id,
       token_hash,
       status,
       created_at,
       expires_at,
       invited_by
     )
     VALUES (
       '20000000-0000-0000-0000-000000000601',
       '10000000-0000-0000-0000-000000000602',
       decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'),
       'PENDING',
       timestamptz '2026-07-24 00:00:00+00',
       timestamptz '2026-07-31 00:00:00+00',
       '10000000-0000-0000-0000-000000000601'
     ) $$,
  'a 32-byte SHA-256 token hash is accepted'
);

SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', ''::bytea, 'EXPIRED', timestamptz '2026-07-24 00:00:00+00', timestamptz '2026-07-31 00:00:00+00', '10000000-0000-0000-0000-000000000601') $$,
  '23514',
  NULL,
  'empty token hash is rejected'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'hex'), 'EXPIRED', timestamptz '2026-07-24 00:00:00+00', timestamptz '2026-07-31 00:00:00+00', '10000000-0000-0000-0000-000000000601') $$,
  '23514',
  NULL,
  '31-byte token hash is rejected'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'hex'), 'EXPIRED', timestamptz '2026-07-24 00:00:00+00', timestamptz '2026-07-31 00:00:00+00', '10000000-0000-0000-0000-000000000601') $$,
  '23514',
  NULL,
  '33-byte token hash is rejected'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', NULL, 'EXPIRED', timestamptz '2026-07-24 00:00:00+00', timestamptz '2026-07-31 00:00:00+00', '10000000-0000-0000-0000-000000000601') $$,
  '23502',
  NULL,
  'null token hash remains rejected'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'), 'EXPIRED', timestamptz '2026-07-24 00:00:00+00', timestamptz '2026-07-31 00:00:00+00', '10000000-0000-0000-0000-000000000601') $$,
  '23505',
  NULL,
  'token hash uniqueness still works'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'hex'), 'PENDING', timestamptz '2026-07-24 00:00:00+00', timestamptz '2026-07-30 00:00:00+00', '10000000-0000-0000-0000-000000000601') $$,
  '23514',
  NULL,
  'invitation expiry must be exactly seven days after creation'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'hex'), 'PENDING', timestamptz '2026-07-25 00:00:00+00', timestamptz '2026-08-01 00:00:00+00', '10000000-0000-0000-0000-000000000601') $$,
  '23505',
  NULL,
  'only one pending invitation per invited user is allowed'
);
SELECT throws_ok(
  $$ INSERT INTO app.user_invitations (invited_user_id, token_hash, status, created_at, expires_at, revoked_at, invited_by)
     VALUES ('10000000-0000-0000-0000-000000000602', decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd', 'hex'), 'REVOKED', timestamptz '2026-07-25 00:00:00+00', timestamptz '2026-08-01 00:00:00+00', now(), '10000000-0000-0000-0000-000000000601') $$,
  '23514',
  NULL,
  'terminal revoked state requires revoked_by and reason'
);

SELECT * FROM finish();
ROLLBACK;
