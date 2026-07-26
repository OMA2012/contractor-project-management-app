BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(36);

SELECT has_table('app', 'project_milestones', 'milestone table exists');
SELECT is(
  (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'project_milestones'),
  ARRAY[
    'id',
    'project_id',
    'phase_id',
    'name',
    'description',
    'due_date',
    'completed_at',
    'client_visible',
    'is_active',
    'created_at',
    'created_by',
    'updated_at',
    'updated_by',
    'version_number'
  ],
  'milestone table has exact 14 columns'
);
SELECT is_empty(
  $$ SELECT column_name FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'project_milestones' AND column_name IN ('status','sequence_no','milestone_number','completion_percent','weight_percent','actual_completion_date','completed_by','archived_at','archived_by','cancellation_reason','payment_request_id','amount','currency_code','predecessor_id','template_id','colour','task_count') $$,
  'forbidden milestone columns are absent'
);
SELECT is_empty($$ SELECT typname FROM pg_type WHERE typnamespace = 'app'::regnamespace AND typname LIKE '%milestone%status%' $$, 'no milestone status enum exists');
SELECT col_type_is('app', 'project_milestones', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'project_milestones', 'project_id', 'uuid', 'project_id is uuid');
SELECT col_type_is('app', 'project_milestones', 'phase_id', 'uuid', 'phase_id is uuid');
SELECT col_type_is('app', 'project_milestones', 'name', 'character varying(160)', 'name is bounded varchar');
SELECT col_type_is('app', 'project_milestones', 'description', 'text', 'description is text');
SELECT col_type_is('app', 'project_milestones', 'due_date', 'date', 'due_date is date');
SELECT col_type_is('app', 'project_milestones', 'completed_at', 'timestamp with time zone', 'completed_at is timestamptz');
SELECT col_type_is('app', 'project_milestones', 'client_visible', 'boolean', 'client_visible is boolean');
SELECT col_type_is('app', 'project_milestones', 'is_active', 'boolean', 'is_active is boolean');
SELECT col_type_is('app', 'project_milestones', 'created_at', 'timestamp with time zone', 'created_at is timestamptz');
SELECT col_type_is('app', 'project_milestones', 'updated_at', 'timestamp with time zone', 'updated_at is timestamptz');
SELECT col_type_is('app', 'project_milestones', 'version_number', 'integer', 'version is integer');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_milestones'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_milestones'::regclass AND attname = 'id')) LIKE '%gen_random_uuid%', 'id defaults to gen_random_uuid');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_milestones'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_milestones'::regclass AND attname = 'client_visible')) LIKE '%true%', 'client_visible defaults true');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_milestones'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_milestones'::regclass AND attname = 'is_active')) LIKE '%true%', 'is_active defaults true');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_milestones'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_milestones'::regclass AND attname = 'version_number')) LIKE '%1%', 'version defaults 1');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_milestones_project_fk') = 'r', 'Project FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_milestones_phase_fk') = 'r', 'phase FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_milestones_created_by_fk') = 'r', 'created_by FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_milestones_updated_by_fk') = 'r', 'updated_by FK uses ON DELETE RESTRICT');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_milestones_name_ck') LIKE '%btrim%', 'nonblank name constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_milestones_description_ck') LIKE '%4000%', 'description follows existing 4000-character text convention');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_milestones_version_ck') LIKE '%version_number >= 1%', 'version minimum constraint exists');
SELECT has_index('app', 'project_milestones', 'project_milestones_project_order_idx', 'Project milestone listing index exists');
SELECT has_index('app', 'project_milestones', 'project_milestones_project_active_idx', 'active Project milestone index exists');
SELECT has_index('app', 'project_milestones', 'project_milestones_phase_idx', 'phase milestone index exists');
SELECT has_index('app', 'project_milestones', 'project_milestones_client_visible_active_idx', 'Client-visible active milestone index exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.project_milestones'::regclass AND tgname = 'project_milestones_no_delete'), 'hard-delete prevention trigger exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.project_milestones'::regclass AND tgname = 'project_milestones_validate_relationships'), 'same-Project and date validation trigger exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.project_milestones'::regclass AND tgname = 'project_milestones_trusted_update'), 'trusted update guard trigger exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.project_milestones'::regclass), 'milestone table has RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.project_milestones'::regclass), 'milestone table has forced RLS');

SELECT * FROM finish();
ROLLBACK;
