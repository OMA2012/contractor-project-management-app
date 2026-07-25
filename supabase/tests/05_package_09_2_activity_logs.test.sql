BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(28);

SELECT has_table('app', 'activity_logs', 'central activity_logs table exists');
SELECT has_column('app', 'activity_logs', 'id', 'activity_logs.id exists');
SELECT has_column('app', 'activity_logs', 'occurred_at', 'activity_logs.occurred_at exists');
SELECT has_column('app', 'activity_logs', 'actor_user_id', 'activity_logs.actor_user_id exists');
SELECT has_column('app', 'activity_logs', 'actor_auth_subject', 'activity_logs.actor_auth_subject exists');
SELECT has_column('app', 'activity_logs', 'effective_role_code', 'activity_logs.effective_role_code exists');
SELECT has_column('app', 'activity_logs', 'action', 'activity_logs.action exists');
SELECT has_column('app', 'activity_logs', 'entity_type', 'activity_logs.entity_type exists');
SELECT has_column('app', 'activity_logs', 'entity_id', 'activity_logs.entity_id exists');
SELECT has_column('app', 'activity_logs', 'project_id', 'activity_logs.project_id exists without Stage 09 project fk');
SELECT has_column('app', 'activity_logs', 'outcome', 'activity_logs.outcome exists');
SELECT has_column('app', 'activity_logs', 'previous_values', 'activity_logs.previous_values exists');
SELECT has_column('app', 'activity_logs', 'new_values', 'activity_logs.new_values exists');
SELECT has_column('app', 'activity_logs', 'metadata', 'activity_logs.metadata exists');
SELECT has_function('app', 'mask_audit_json', ARRAY['jsonb']::name[], 'mask_audit_json exists');
SELECT has_function(
  'app',
  'write_activity_log',
  ARRAY['uuid', 'uuid', 'character varying', 'character varying', 'character varying', 'uuid', 'uuid', 'character varying', 'jsonb', 'jsonb', 'text', 'inet', 'text', 'text', 'text', 'jsonb']::name[],
  'write_activity_log exists'
);
SELECT ok(relrowsecurity, 'activity_logs has RLS enabled') FROM pg_class WHERE oid = 'app.activity_logs'::regclass;
SELECT ok(relforcerowsecurity, 'activity_logs forces RLS') FROM pg_class WHERE oid = 'app.activity_logs'::regclass;
SELECT ok(NOT has_table_privilege('anon', 'app.activity_logs', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'anon cannot write activity_logs');
SELECT ok(NOT has_table_privilege('authenticated', 'app.activity_logs', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated cannot write activity_logs');
SELECT ok(NOT has_function_privilege('authenticated', 'app.mask_audit_json(jsonb)', 'EXECUTE'), 'authenticated cannot execute mask_audit_json');
SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'app.write_activity_log(uuid, uuid, character varying, character varying, character varying, uuid, uuid, character varying, jsonb, jsonb, text, inet, text, text, text, jsonb)',
    'EXECUTE'
  ),
  'authenticated cannot execute write_activity_log'
);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit.0911@example.test', '', now(), '{}', '{}', now(), now());

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active)
VALUES ('10000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000501', 'audit.0911@example.test', 'STAFF', 'ACTIVE', true);

SELECT app.write_activity_log(
  '10000000-0000-0000-0000-000000000501',
  '00000000-0000-0000-0000-000000000501',
  NULL,
  'test.action',
  'test_entity',
  '20000000-0000-0000-0000-000000000501',
  NULL,
  'success',
  '{"password":"x","nested":{"access_token":"x","keep":"yes"},"items":[{"refresh-token":"x","safe":1}]}'::jsonb,
  '{"service_role":"x","child":{"private_note":"x","visible":true}}'::jsonb,
  'test',
  '127.0.0.1',
  'session',
  'request',
  'correlation',
  '{"token":"x","signed_url":"x","outer":{"full_account_number":"x","safe":"ok"}}'::jsonb
);

SELECT is(
  (SELECT previous_values FROM app.activity_logs ORDER BY occurred_at DESC LIMIT 1),
  '{"nested":{"keep":"yes"},"items":[{"safe":1}]}'::jsonb,
  'mask_audit_json recursively removes prohibited keys from previous values'
);
SELECT is(
  (SELECT new_values FROM app.activity_logs ORDER BY occurred_at DESC LIMIT 1),
  '{"child":{"visible":true}}'::jsonb,
  'write_activity_log stores masked new values'
);
SELECT is(
  (SELECT metadata FROM app.activity_logs ORDER BY occurred_at DESC LIMIT 1),
  '{"outer":{"safe":"ok"}}'::jsonb,
  'write_activity_log stores masked metadata'
);

SELECT throws_ok(
  $$ UPDATE app.activity_logs SET outcome = 'changed' $$,
  '23514',
  'activity_logs rows are append-only.',
  'activity_logs update is rejected'
);
SELECT throws_ok(
  $$ DELETE FROM app.activity_logs $$,
  '23514',
  'activity_logs rows cannot be deleted.',
  'activity_logs delete is rejected'
);
SELECT throws_ok(
  $$ TRUNCATE app.activity_logs $$,
  '23514',
  'activity_logs cannot be truncated.',
  'activity_logs truncate is rejected'
);

SELECT * FROM finish();
ROLLBACK;
