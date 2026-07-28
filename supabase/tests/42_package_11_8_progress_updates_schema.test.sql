BEGIN;
SELECT plan(31);

SELECT has_type('app', 'progress_update_status', 'progress update status enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'app' AND t.typname = 'progress_update_status' ORDER BY enumsortorder $$,
  $$ VALUES ('DRAFT'::name), ('SUBMITTED'::name), ('APPROVED'::name), ('REJECTED'::name) $$,
  'progress update enum values are exact'
);
SELECT has_table('app', 'progress_updates', 'progress updates table exists');
SELECT columns_are('app', 'progress_updates', ARRAY[
  'id','project_id','milestone_id','title','summary','reported_completion_percent','status','client_visible',
  'submitted_at','submitted_by','approved_at','approved_by','rejected_at','rejected_by','rejection_reason',
  'published_at','archived_at','archived_by','created_at','created_by','updated_at','updated_by','version_number'
], 'progress updates have exact 23 columns');
SELECT hasnt_column('app', 'progress_updates', 'task_id', 'task_id absent');
SELECT hasnt_column('app', 'progress_updates', 'phase_id', 'phase_id absent');
SELECT hasnt_column('app', 'progress_updates', 'private_summary', 'private summary absent');
SELECT hasnt_column('app', 'progress_updates', 'client_summary', 'client summary absent');
SELECT hasnt_column('app', 'progress_updates', 'delay_reason', 'delay reason absent');
SELECT hasnt_column('app', 'progress_updates', 'next_planned_work', 'next planned work absent');
SELECT col_type_is('app', 'progress_updates', 'title', 'character varying(200)', 'title is varchar(200)');
SELECT col_type_is('app', 'progress_updates', 'summary', 'text', 'summary is text');
SELECT col_type_is('app', 'progress_updates', 'reported_completion_percent', 'numeric(5,2)', 'reported completion precision exact');
SELECT col_type_is('app', 'progress_updates', 'status', 'app.progress_update_status', 'status type exact');
SELECT is((SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum WHERE a.attrelid = 'app.progress_updates'::regclass AND a.attname = 'status'), '''DRAFT''::app.progress_update_status', 'status defaults to draft');
SELECT col_default_is('app', 'progress_updates', 'client_visible', 'false', 'client visibility defaults false');
SELECT col_default_is('app', 'progress_updates', 'version_number', '1', 'version starts at 1');
SELECT fk_ok('app', 'progress_updates', 'project_id', 'app', 'projects', 'id', 'project foreign key exists');
SELECT fk_ok('app', 'progress_updates', 'milestone_id', 'app', 'project_milestones', 'id', 'milestone foreign key exists');
SELECT fk_ok('app', 'progress_updates', 'created_by', 'app', 'users', 'id', 'creator foreign key exists');
SELECT fk_ok('app', 'progress_updates', 'updated_by', 'app', 'users', 'id', 'updater foreign key exists');
SELECT fk_ok('app', 'progress_updates', 'approved_by', 'app', 'users', 'id', 'approver foreign key exists');
SELECT fk_ok('app', 'progress_updates', 'archived_by', 'app', 'users', 'id', 'archiver foreign key exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'progress_updates_state_ck'), 'state consistency constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'progress_updates_publication_visibility_ck'), 'publication visibility constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'progress_updates_approver_differs_ck'), 'approver separation constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'progress_updates' AND indexname = 'progress_updates_client_feed_idx'), 'Client feed index exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.progress_updates'::regclass), 'RLS is enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.progress_updates'::regclass), 'RLS is forced');
SELECT throws_ok($$ INSERT INTO app.progress_updates DEFAULT VALUES $$, '23502', 'null value in column "project_id" of relation "progress_updates" violates not-null constraint', 'direct incomplete insert rejected by constraints');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('notifications','documents','document_links','financial_transactions','ledger_entries')), 'notifications, documents and finance remain absent');

SELECT * FROM finish();
ROLLBACK;
