BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(29);

SELECT has_table('app', 'task_assignments', 'task assignments table exists');
SELECT columns_are('app', 'task_assignments', ARRAY[
  'id',
  'task_id',
  'project_staff_assignment_id',
  'assigned_at',
  'assigned_by',
  'removed_at',
  'is_active'
]::name[], 'task assignments table has exact approved columns');
SELECT col_is_pk('app', 'task_assignments', 'id', 'task assignment id is primary key');
SELECT col_type_is('app', 'task_assignments', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'task_assignments', 'task_id', 'uuid', 'task_id is uuid');
SELECT col_type_is('app', 'task_assignments', 'project_staff_assignment_id', 'uuid', 'project_staff_assignment_id is uuid');
SELECT col_type_is('app', 'task_assignments', 'assigned_at', 'timestamp with time zone', 'assigned_at uses timestamptz');
SELECT col_type_is('app', 'task_assignments', 'assigned_by', 'uuid', 'assigned_by is uuid');
SELECT col_type_is('app', 'task_assignments', 'removed_at', 'timestamp with time zone', 'removed_at uses timestamptz');
SELECT col_type_is('app', 'task_assignments', 'is_active', 'boolean', 'is_active is boolean');
SELECT fk_ok('app', 'task_assignments', 'task_id', 'app', 'tasks', 'id', 'task FK exists');
SELECT fk_ok('app', 'task_assignments', 'project_staff_assignment_id', 'app', 'project_staff_assignments', 'id', 'Project staff assignment FK exists');
SELECT fk_ok('app', 'task_assignments', 'assigned_by', 'app', 'users', 'id', 'assigned_by FK exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.task_assignments'::regclass AND conname = 'task_assignments_lifecycle_ck'), 'assignment active/removal lifecycle constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'task_assignments' AND indexname = 'task_assignments_one_active_pair_idx' AND indexdef ILIKE '%unique%' AND indexdef ILIKE '%where is_active%'), 'partial active-pair uniqueness exists');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app.task_assignments'::regclass AND contype = 'u' AND pg_get_constraintdef(oid) ILIKE '%task_id%' AND pg_get_constraintdef(oid) NOT ILIKE '%project_staff_assignment_id%'), 'no single-task unique constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'task_assignments' AND indexname = 'task_assignments_task_order_idx'), 'task assignment ordering index exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.task_assignments'::regclass AND tgname = 'task_assignments_no_delete' AND NOT tgisinternal), 'hard-delete prevention trigger exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.task_assignments'::regclass AND tgname = 'task_assignments_trusted_update' AND NOT tgisinternal), 'trusted update guard exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.task_assignments'::regclass), 'task assignment RLS is enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.task_assignments'::regclass), 'task assignment RLS is forced');
SELECT ok(pg_get_functiondef('app.task_assignments_trusted_update_guard()'::regprocedure) ILIKE '%Inactive Project task assignments are immutable%', 'inactive assignment history is immutable');
SELECT ok(pg_get_functiondef('app.task_assignments_trusted_update_guard()'::regprocedure) ILIKE '%cannot be reactivated%', 'assignment reactivation is prohibited');
SELECT ok(pg_get_functiondef('app.prevent_task_assignment_delete()'::regprocedure) ILIKE '%Project task assignments cannot be deleted%', 'delete trigger raises deterministic error');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'task_assignments' AND column_name IN ('user_id','project_id','role_code','assigned_role','task_status','completion_percent','notes','removal_reason','removed_by','updated_at','updated_by','version_number','client_visible')), 'forbidden task-assignment columns are absent');
SELECT has_table('app', 'task_updates', 'task updates are implemented in Package 11.5');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('financial_transactions','ledger_entries')), 'later finance tables remain absent');
SELECT ok(pg_get_functiondef('app.assign_project_task(uuid,uuid,uuid,text,text,text,inet)'::regprocedure) NOT ILIKE '%insert into app.user_roles%', 'assignment does not create user roles');
SELECT ok(pg_get_functiondef('app.assign_project_task(uuid,uuid,uuid,text,text,text,inet)'::regprocedure) NOT ILIKE '%public.current_account%', 'assignment does not activate current_account');

SELECT * FROM finish();
ROLLBACK;
