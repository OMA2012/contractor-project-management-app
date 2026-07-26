BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(34);

SELECT has_type('app', 'project_staff_assignment_status', 'assignment status enum exists');
SELECT is((SELECT array_agg(enumlabel::text ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid = 'app.project_staff_assignment_status'::regtype), ARRAY['ACTIVE','REMOVED']::text[], 'assignment status enum has exact values');
SELECT has_table('app', 'project_staff_assignments', 'assignment table exists');
SELECT is(
  (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'project_staff_assignments'),
  ARRAY['id','project_id','user_id','assignment_role_code','status','assigned_at','assigned_by','removed_at','removed_by','notes']::text[],
  'assignment table has exact columns'
);
SELECT ok(NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema = 'app'
    AND table_name = 'project_staff_assignments'
    AND column_name IN ('client_id','phase_id','milestone_id','task_id','permission_flags','financial_flags','is_project_owner','version_number','created_at','created_by','updated_at','updated_by','removal_reason','deleted_at','archived_at')
), 'forbidden assignment columns are absent');
SELECT col_type_is('app', 'project_staff_assignments', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'project_staff_assignments', 'project_id', 'uuid', 'project_id is uuid');
SELECT col_type_is('app', 'project_staff_assignments', 'user_id', 'uuid', 'user_id is uuid');
SELECT col_type_is('app', 'project_staff_assignments', 'assignment_role_code', 'character varying(40)', 'assignment role code reuses role code type');
SELECT col_type_is('app', 'project_staff_assignments', 'status', 'app.project_staff_assignment_status', 'status uses exact enum');
SELECT col_type_is('app', 'project_staff_assignments', 'assigned_at', 'timestamp with time zone', 'assigned_at is timestamptz');
SELECT col_type_is('app', 'project_staff_assignments', 'removed_at', 'timestamp with time zone', 'removed_at is timestamptz');
SELECT col_type_is('app', 'project_staff_assignments', 'notes', 'text', 'notes is text');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_staff_assignments'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_staff_assignments'::regclass AND attname = 'id')) LIKE '%gen_random_uuid%', 'id defaults to gen_random_uuid');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_staff_assignments'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_staff_assignments'::regclass AND attname = 'status')) LIKE '%ACTIVE%', 'status defaults to ACTIVE');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_staff_assignments'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_staff_assignments'::regclass AND attname = 'assigned_at')) LIKE '%now%', 'assigned_at defaults to trusted transaction time');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_staff_assignments_project_fk') = 'r', 'Project FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_staff_assignments_user_fk') = 'r', 'user FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_staff_assignments_role_fk') = 'r', 'role FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_staff_assignments_assigned_by_fk') = 'r', 'assigned_by FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_staff_assignments_removed_by_fk') = 'r', 'removed_by FK uses ON DELETE RESTRICT');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_staff_assignments_role_allowlist_ck') LIKE '%project_manager%' AND (SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_staff_assignments_role_allowlist_ck') LIKE '%site_supervisor%', 'role allowlist is lower-case Project Manager and Site Supervisor only');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_staff_assignments_role_allowlist_ck') NOT LIKE '%accountant%' AND (SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_staff_assignments_role_allowlist_ck') NOT LIKE '%owner_admin%' AND (SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_staff_assignments_role_allowlist_ck') NOT LIKE '%client%', 'role allowlist excludes owner, accountant and client');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_staff_assignments_lifecycle_ck') LIKE '%REMOVED%', 'ACTIVE/REMOVED consistency constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_staff_assignments_notes_ck') LIKE '%4000%', 'notes use established 4000 character Project notes convention');
SELECT has_index('app', 'project_staff_assignments', 'project_staff_assignments_one_active_idx', 'partial unique active assignment index exists');
SELECT ok((SELECT pg_get_indexdef('app.project_staff_assignments_one_active_idx'::regclass)) LIKE '%WHERE (status = ''ACTIVE''%', 'unique active index is partial on ACTIVE rows');
SELECT has_index('app', 'project_staff_assignments', 'project_staff_assignments_project_order_idx', 'Project assignment listing index exists');
SELECT has_index('app', 'project_staff_assignments', 'project_staff_assignments_user_active_idx', 'active assignment by user index exists');
SELECT has_index('app', 'project_staff_assignments', 'project_staff_assignments_role_active_idx', 'active assignment by role index exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.project_staff_assignments'::regclass), 'assignment table has RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.project_staff_assignments'::regclass), 'assignment table has forced RLS');
SELECT ok((SELECT pg_get_functiondef('app.prevent_project_staff_assignment_delete()'::regprocedure)) LIKE '%Project staff assignments cannot be deleted.%', 'hard delete prevention exists');
SELECT ok((SELECT pg_get_functiondef('app.project_staff_assignments_trusted_update_guard()'::regprocedure)) LIKE '%Project staff assignment identity is immutable.%', 'assignment identity immutability guard exists');

SELECT * FROM finish();
ROLLBACK;
