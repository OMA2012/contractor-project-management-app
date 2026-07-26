BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(31);

SELECT has_table('app', 'project_phases', 'phase table exists');
SELECT is(
  (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'project_phases'),
  ARRAY[
    'id',
    'project_id',
    'name',
    'description',
    'sequence_no',
    'start_date',
    'end_date',
    'client_visible',
    'is_active',
    'created_at',
    'created_by',
    'updated_at',
    'updated_by',
    'version_number'
  ],
  'phase table has exact 14 columns'
);
SELECT is_empty(
  $$ SELECT column_name FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'project_phases' AND column_name IN ('status','completion_percent','weight_percent','milestone_count','task_count','completed_at','archived_at','archived_by','phase_number','colour','template_id') $$,
  'forbidden phase columns are absent'
);
SELECT col_type_is('app', 'project_phases', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'project_phases', 'project_id', 'uuid', 'project_id is uuid');
SELECT col_type_is('app', 'project_phases', 'name', 'character varying(160)', 'name is bounded varchar');
SELECT col_type_is('app', 'project_phases', 'description', 'text', 'description is text');
SELECT col_type_is('app', 'project_phases', 'sequence_no', 'integer', 'sequence is integer');
SELECT col_type_is('app', 'project_phases', 'client_visible', 'boolean', 'client_visible is boolean');
SELECT col_type_is('app', 'project_phases', 'is_active', 'boolean', 'is_active is boolean');
SELECT col_type_is('app', 'project_phases', 'created_at', 'timestamp with time zone', 'created_at is timestamptz');
SELECT col_type_is('app', 'project_phases', 'updated_at', 'timestamp with time zone', 'updated_at is timestamptz');
SELECT col_type_is('app', 'project_phases', 'version_number', 'integer', 'version is integer');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_phases'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_phases'::regclass AND attname = 'id')) LIKE '%gen_random_uuid%', 'id defaults to gen_random_uuid');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_phases'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_phases'::regclass AND attname = 'client_visible')) LIKE '%true%', 'client_visible defaults true');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.project_phases'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.project_phases'::regclass AND attname = 'is_active')) LIKE '%true%', 'is_active defaults true');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_phases_project_fk') = 'r', 'Project FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_phases_created_by_fk') = 'r', 'created_by FK uses ON DELETE RESTRICT');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'project_phases_updated_by_fk') = 'r', 'updated_by FK uses ON DELETE RESTRICT');
SELECT ok((SELECT condeferrable FROM pg_constraint WHERE conname = 'project_phases_project_sequence_uk'), 'Project sequence uniqueness is deferrable');
SELECT ok((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'project_phases_project_sequence_uk') LIKE '%UNIQUE (project_id, sequence_no)%', 'unique Project sequence constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_phases_name_ck') LIKE '%btrim%', 'nonblank name constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_phases_description_ck') LIKE '%4000%', 'description follows existing 4000-character text convention');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_phases_sequence_ck') LIKE '%sequence_no > 0%', 'positive sequence constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_phases_date_order_ck') LIKE '%start_date <= end_date%', 'phase date order constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'project_phases_version_ck') LIKE '%version_number >= 1%', 'version minimum constraint exists');
SELECT has_index('app', 'project_phases', 'project_phases_project_order_idx', 'Project phase listing index exists');
SELECT has_index('app', 'project_phases', 'project_phases_project_active_idx', 'active phase index exists');
SELECT has_index('app', 'project_phases', 'project_phases_client_visible_active_idx', 'Client-visible active index exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.project_phases'::regclass), 'phase table has RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.project_phases'::regclass), 'phase table has forced RLS');

SELECT * FROM finish();
ROLLBACK;
