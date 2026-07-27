BEGIN;
SELECT plan(30);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000003901', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.39a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000003902', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.39b@example.test', '', now(), '{}', '{}', now(), now());

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active)
VALUES
  ('10000000-0000-0000-0000-000000003901', '00000000-0000-0000-0000-000000003901', 'owner.39a@example.test', 'STAFF', 'ACTIVE', true),
  ('10000000-0000-0000-0000-000000003902', '00000000-0000-0000-0000-000000003902', 'owner.39b@example.test', 'STAFF', 'ACTIVE', true);

INSERT INTO app.clients (id, client_number, display_name, created_by, updated_by)
VALUES ('20000000-0000-0000-0000-000000003901', 'CL-939001', 'Override Schema Client', '10000000-0000-0000-0000-000000003901', '10000000-0000-0000-0000-000000003901');

INSERT INTO app.projects (id, project_number, client_id, name, reporting_currency_code, created_by, updated_by)
VALUES ('30000000-0000-0000-0000-000000003901', 'PRJ-2039-0001', '20000000-0000-0000-0000-000000003901', 'Override Schema Project', 'USD', '10000000-0000-0000-0000-000000003901', '10000000-0000-0000-0000-000000003901');

SELECT has_table('app', 'project_completion_overrides', 'Project completion override table exists');
SELECT columns_are(
  'app',
  'project_completion_overrides',
  ARRAY[
    'id',
    'project_id',
    'override_percent',
    'reason',
    'effective_at',
    'approved_at',
    'approved_by',
    'revoked_at',
    'revoked_by',
    'created_at',
    'created_by'
  ],
  'Project completion override has exactly eleven columns'
);
SELECT hasnt_column('app', 'project_completion_overrides', 'status', 'no stored status column');
SELECT hasnt_column('app', 'project_completion_overrides', 'calculated_percent', 'no calculated snapshot column');
SELECT hasnt_column('app', 'project_completion_overrides', 'version_number', 'no version column');
SELECT col_type_is('app', 'project_completion_overrides', 'override_percent', 'numeric(5,2)', 'override percentage uses numeric(5,2)');
SELECT col_type_is('app', 'project_completion_overrides', 'reason', 'text', 'reason uses text without arbitrary bounded varchar');
SELECT col_type_is('app', 'project_completion_overrides', 'effective_at', 'timestamp with time zone', 'effective timestamp uses timestamptz');
SELECT col_is_pk('app', 'project_completion_overrides', 'id', 'override id is primary key');
SELECT fk_ok('app', 'project_completion_overrides', 'project_id', 'app', 'projects', 'id', 'Project foreign key exists');
SELECT fk_ok('app', 'project_completion_overrides', 'approved_by', 'app', 'users', 'id', 'approver foreign key exists');
SELECT fk_ok('app', 'project_completion_overrides', 'revoked_by', 'app', 'users', 'id', 'revoker foreign key exists');
SELECT fk_ok('app', 'project_completion_overrides', 'created_by', 'app', 'users', 'id', 'creator foreign key exists');
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app'
      AND tablename = 'project_completion_overrides'
      AND indexname = 'project_completion_overrides_one_active_uk'
      AND indexdef ILIKE '%unique%'
      AND indexdef ILIKE '%where%'
      AND indexdef ILIKE '%approved_at is not null%'
      AND indexdef ILIKE '%revoked_at is null%'
  ),
  'one active approved override partial unique index exists'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app'
      AND tablename = 'project_completion_overrides'
      AND indexdef ILIKE '%approved_at is null%'
      AND indexdef ILIKE '%unique%'
  ),
  'no pending-request unique index exists'
);
SELECT has_index('app', 'project_completion_overrides', 'project_completion_overrides_project_history_idx', 'Project history ordering index exists');
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'app.project_completion_overrides'::regclass
      AND conname = 'project_completion_overrides_percent_ck'
  ),
  'percentage range constraint exists'
);
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, created_by) VALUES ('30000000-0000-0000-0000-000000003901', -0.01, 'bad', '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'negative percentage rejected');
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, created_by) VALUES ('30000000-0000-0000-0000-000000003901', 100.01, 'bad', '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'percentage above 100 rejected');
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, created_by) VALUES ('30000000-0000-0000-0000-000000003901', 50, '   ', '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'blank reason rejected');
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, approved_at, created_by) VALUES ('30000000-0000-0000-0000-000000003901', 50, 'reason', now(), '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'unpaired approval fields rejected');
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, revoked_at, revoked_by, created_by) VALUES ('30000000-0000-0000-0000-000000003901', 50, 'reason', now(), '10000000-0000-0000-0000-000000003902', '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'pending rows cannot contain revocation fields');
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, approved_at, approved_by, created_at, created_by) VALUES ('30000000-0000-0000-0000-000000003901', 50, 'reason', now(), '10000000-0000-0000-0000-000000003901', now(), '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'creator cannot also be approver');
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, approved_at, approved_by, created_at, created_by) VALUES ('30000000-0000-0000-0000-000000003901', 50, 'reason', now() - interval '1 minute', '10000000-0000-0000-0000-000000003902', now(), '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'approval cannot precede creation');
SELECT throws_ok($$ INSERT INTO app.project_completion_overrides(project_id, override_percent, reason, approved_at, approved_by, revoked_at, revoked_by, created_by) VALUES ('30000000-0000-0000-0000-000000003901', 50, 'reason', now(), '10000000-0000-0000-0000-000000003902', now() - interval '1 minute', '10000000-0000-0000-0000-000000003901', '10000000-0000-0000-0000-000000003901') $$, '23514', NULL, 'revocation cannot precede approval');
SELECT results_eq($$ SELECT app.derive_project_completion_override_state(NULL, NULL, NULL, NULL) $$, $$ VALUES ('PENDING'::text) $$, 'pending state is derived');
SELECT results_eq($$ SELECT app.derive_project_completion_override_state(now(), gen_random_uuid(), NULL, NULL) $$, $$ VALUES ('ACTIVE'::text) $$, 'active state is derived');
SELECT results_eq($$ SELECT app.derive_project_completion_override_state(now(), gen_random_uuid(), now(), gen_random_uuid()) $$, $$ VALUES ('SUPERSEDED_OR_REVOKED'::text) $$, 'revoked or superseded state is derived');
SELECT ok(
  EXISTS (SELECT 1 FROM pg_class WHERE oid = 'app.project_completion_overrides'::regclass AND relrowsecurity AND relforcerowsecurity),
  'RLS enabled and forced'
);
SELECT ok(
  pg_get_functiondef('app.owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet)'::regprocedure) NOT ILIKE '%p_effective_at > now()%'
  AND pg_get_functiondef('app.owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet)'::regprocedure) ILIKE '%p_effective_at > workflow_at%',
  'future effective timestamp is enforced in workflow code, not a time-relative table CHECK'
);

SELECT * FROM finish();
ROLLBACK;
