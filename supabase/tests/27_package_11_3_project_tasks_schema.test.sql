BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(36);

SELECT has_type('app', 'project_task_status', 'task status enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum WHERE enumtypid = 'app.project_task_status'::regtype ORDER BY enumsortorder $$,
  $$ VALUES ('TODO'::name), ('IN_PROGRESS'::name), ('BLOCKED'::name), ('COMPLETED'::name), ('CANCELLED'::name) $$,
  'task status enum has exact values'
);
SELECT has_table('app', 'project_task_number_counters', 'internal task-number counter exists');
SELECT has_table('app', 'tasks', 'tasks table exists');
SELECT columns_are('app', 'tasks', ARRAY[
  'id',
  'project_id',
  'phase_id',
  'milestone_id',
  'task_number',
  'title',
  'description',
  'client_summary',
  'status',
  'completion_percent',
  'weight_percent',
  'counts_toward_completion',
  'start_date',
  'due_date',
  'completed_at',
  'client_visible',
  'is_active',
  'created_at',
  'created_by',
  'updated_at',
  'updated_by',
  'version_number'
]::name[], 'tasks table has exact approved columns');
SELECT col_type_is('app', 'tasks', 'task_number', 'character varying(40)', 'task number type is varchar(40)');
SELECT col_type_is('app', 'tasks', 'status', 'app.project_task_status', 'task status uses enum');
SELECT col_type_is('app', 'tasks', 'completion_percent', 'numeric(5,2)', 'completion percent precision is fixed');
SELECT col_type_is('app', 'tasks', 'weight_percent', 'numeric(7,4)', 'weight precision is fixed');
SELECT col_is_pk('app', 'tasks', 'id', 'task id is primary key');
SELECT fk_ok('app', 'tasks', 'project_id', 'app', 'projects', 'id', 'task project FK exists');
SELECT fk_ok('app', 'tasks', 'phase_id', 'app', 'project_phases', 'id', 'task phase FK exists');
SELECT fk_ok('app', 'tasks', 'milestone_id', 'app', 'project_milestones', 'id', 'task milestone FK exists');
SELECT fk_ok('app', 'tasks', 'created_by', 'app', 'users', 'id', 'created_by FK exists');
SELECT fk_ok('app', 'tasks', 'updated_by', 'app', 'users', 'id', 'updated_by FK exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_project_task_number_uk'), 'Project-local task-number uniqueness exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_task_number_ck'), 'task-number format constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_workflow_state_ck'), 'workflow state constraint is implemented in Package 11.5');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_completion_weight_integrity_ck'), 'task weight rule constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_date_order_ck'), 'task date ordering constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_version_ck'), 'task version minimum constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.tasks'::regclass AND tgname = 'tasks_no_delete' AND NOT tgisinternal), 'hard-delete prevention trigger exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.tasks'::regclass AND tgname = 'tasks_validate_relationships' AND NOT tgisinternal), 'relationship validation trigger exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.tasks'::regclass AND tgname = 'tasks_trusted_update' AND NOT tgisinternal), 'trusted update guard trigger exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'tasks' AND indexname = 'tasks_project_order_idx'), 'deterministic Project task ordering index exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'tasks' AND indexname = 'tasks_client_visible_active_idx'), 'Client-visible task lookup index exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.tasks'::regclass), 'tasks RLS is enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.tasks'::regclass), 'tasks RLS is forced');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.project_task_number_counters'::regclass), 'task counter RLS is enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.project_task_number_counters'::regclass), 'task counter RLS is forced');
SELECT ok(pg_get_functiondef('app.generate_project_task_number(uuid)'::regprocedure) ILIKE '%insert into app.project_task_number_counters%' AND pg_get_functiondef('app.generate_project_task_number(uuid)'::regprocedure) ILIKE '%on conflict%' AND pg_get_functiondef('app.generate_project_task_number(uuid)'::regprocedure) NOT ILIKE '%max(%', 'task-number generator is counter-based and avoids MAX');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'tasks' AND column_name IN ('priority','assigned_user_id','operational_notes','cancellation_reason','completed_by','cancelled_by','archived_at','archived_by','dependency_fields','estimated_cost','actual_cost','attachment_fields')), 'forbidden task columns are absent');
SELECT has_table('app', 'task_updates', 'task updates are implemented in Package 11.5');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('payments')), 'later finance tables remain absent');
SELECT ok(pg_get_functiondef('app.prevent_task_delete()'::regprocedure) ILIKE '%Project tasks cannot be deleted%', 'task delete trigger raises deterministic error');
SELECT ok(pg_get_functiondef('app.prevent_project_task_number_counter_delete()'::regprocedure) ILIKE '%Project task number counters cannot be deleted%', 'task counter delete trigger raises deterministic error');

SELECT * FROM finish();
ROLLBACK;
