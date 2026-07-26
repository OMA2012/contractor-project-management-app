BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(42);

SELECT has_type('app', 'project_record_status', 'Project status enum exists');
SELECT is((SELECT array_agg(enumlabel::text ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid = 'app.project_record_status'::regtype), ARRAY['DRAFT','QUOTATION','APPROVED','ACTIVE','ON_HOLD','COMPLETED','CANCELLED','ARCHIVED'], 'Project status enum has exact values');
SELECT has_table('app', 'project_number_counters', 'Project number counter table exists');
SELECT has_table('app', 'projects', 'Project table exists');
SELECT is(
  (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'projects'),
  ARRAY['id','project_number','client_id','name','project_type','location','status','start_date','end_date','contract_amount','contract_currency_code','budget_amount','budget_currency_code','reporting_currency_code','client_visible_summary','internal_notes','completed_at','cancelled_at','cancellation_reason','archived_at','archived_by','created_at','created_by','updated_at','updated_by','version_number']::text[],
  'projects table has exact columns'
);
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'projects' AND column_name IN ('is_active','completion_percent','current_balance','total_paid','total_expenses','outstanding_amount','assigned_project_manager_id','assigned_supervisor_id','ledger_entry_id','document_id')), 'forbidden Project fields are absent');
SELECT col_type_is('app', 'projects', 'project_number', 'citext', 'project_number is citext');
SELECT col_type_is('app', 'projects', 'contract_amount', 'numeric(20,6)', 'contract amount precision is numeric(20,6)');
SELECT col_type_is('app', 'projects', 'budget_amount', 'numeric(20,6)', 'budget amount precision is numeric(20,6)');
SELECT col_type_is('app', 'projects', 'status', 'app.project_record_status', 'status uses exact enum');
SELECT has_index('app', 'projects', 'projects_project_number_uk', 'Project number unique constraint index exists');
SELECT has_index('app', 'projects', 'projects_client_status_idx', 'Client/status lookup index exists');
SELECT has_index('app', 'projects', 'projects_owner_list_order_idx', 'Owner list ordering index exists');
SELECT has_index('app', 'projects', 'projects_name_lower_idx', 'case-insensitive name lookup index exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_project_number_ck') LIKE '%^PRJ-[0-9]{4}-[0-9]{4}$%', 'Project number format constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_contract_pair_ck') LIKE '%contract_amount IS NULL%', 'contract amount/currency pairing exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_budget_pair_ck') LIKE '%budget_amount IS NULL%', 'budget amount/currency pairing exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_contract_amount_ck') LIKE '%contract_amount >=%', 'zero/nonnegative contract values are allowed');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_budget_amount_ck') LIKE '%budget_amount >=%', 'zero/nonnegative budget values are allowed');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_date_order_ck') LIKE '%start_date <= end_date%', 'date ordering constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_lifecycle_ck') LIKE '%COMPLETED%', 'lifecycle history constraint covers completion');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_lifecycle_ck') LIKE '%CANCELLED%', 'lifecycle history constraint covers cancellation');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'projects_lifecycle_ck') LIKE '%ARCHIVED%', 'lifecycle history constraint covers archive');
SELECT ok((SELECT confdeltype FROM pg_constraint WHERE conname = 'projects_client_fk') = 'r', 'Client FK uses ON DELETE RESTRICT');
SELECT ok((SELECT count(*) FROM pg_constraint WHERE conrelid = 'app.projects'::regclass AND conname IN ('projects_contract_currency_fk','projects_budget_currency_fk','projects_reporting_currency_fk')) = 3, 'currency foreign keys exist');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.projects'::regclass), 'projects RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.projects'::regclass), 'projects RLS forced');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.project_number_counters'::regclass), 'counter RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.project_number_counters'::regclass), 'counter RLS forced');
SELECT has_function('app', 'generate_project_number', ARRAY[]::name[], 'trusted Project number generator exists');
SELECT ok((SELECT pg_get_functiondef('app.generate_project_number()'::regprocedure)) LIKE '%cp.time_zone%', 'generator reads contractor time_zone');
SELECT ok((SELECT pg_get_functiondef('app.generate_project_number()'::regprocedure)) LIKE '%AT TIME ZONE contractor_time_zone%', 'generator uses contractor-local calendar year');
SELECT ok((SELECT pg_get_functiondef('app.generate_project_number()'::regprocedure)) LIKE '%ON CONFLICT (project_year)%', 'generator uses concurrency-safe upsert');
SELECT ok((SELECT pg_get_functiondef('app.generate_project_number()'::regprocedure)) LIKE '%last_value < 9999%', 'generator enforces yearly limit');
SELECT ok(lower((SELECT string_agg(pg_get_functiondef(p.oid), ' ') FROM pg_proc AS p INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace WHERE n.nspname = 'app' OR (n.nspname = 'public' AND p.proname LIKE '%project%'))) NOT LIKE '%max(%+ 1%', 'Project numbers never use MAX plus one');
SELECT ok((SELECT pg_get_functiondef('app.projects_trusted_update_guard()'::regprocedure)) LIKE '%Project number is immutable.%', 'Project number immutable trigger exists');
SELECT ok((SELECT pg_get_functiondef('app.prevent_project_delete()'::regprocedure)) LIKE '%Project records cannot be deleted.%', 'hard-delete prevention exists');
SELECT ok((SELECT pg_get_functiondef('app.projects_trusted_update_guard()'::regprocedure)) LIKE '%NEW.version_number := OLD.version_number + 1%', 'trusted update guard increments version once');
SELECT ok((SELECT pg_get_functiondef('app.projects_trusted_update_guard()'::regprocedure)) LIKE '%app.allow_project_status_change%', 'direct status updates are blocked');
SELECT ok((SELECT pg_get_functiondef('app.projects_trusted_update_guard()'::regprocedure)) LIKE '%app.allow_project_client_change%', 'direct Client reassignment is blocked');
SELECT ok((SELECT pg_get_functiondef('app.prevent_project_number_counter_delete()'::regprocedure)) LIKE '%Project number counters cannot be deleted.%', 'counter hard-delete prevention exists');
SELECT ok((SELECT column_default FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'contractor_profiles' AND column_name = 'time_zone') LIKE '%Asia/Kuching%', 'contractor singleton time_zone has approved Asia/Kuching default');

SELECT * FROM finish();
ROLLBACK;
