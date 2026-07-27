BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(31);

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.project_staff_assignments'::regclass), 'assignment RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.project_staff_assignments'::regclass), 'assignment RLS forced');
SELECT ok(NOT has_table_privilege('anon', 'app.project_staff_assignments', 'SELECT'), 'anon cannot select assignments');
SELECT ok(NOT has_table_privilege('authenticated', 'app.project_staff_assignments', 'SELECT'), 'authenticated cannot select assignments');
SELECT ok(NOT has_table_privilege('service_role', 'app.project_staff_assignments', 'SELECT'), 'service_role has no direct assignment table SELECT');
SELECT ok(NOT has_table_privilege('authenticated', 'app.project_staff_assignments', 'INSERT'), 'authenticated cannot insert assignments');
SELECT ok(NOT has_table_privilege('authenticated', 'app.project_staff_assignments', 'UPDATE'), 'authenticated cannot update assignments');
SELECT ok(NOT has_table_privilege('authenticated', 'app.project_staff_assignments', 'DELETE'), 'authenticated cannot delete assignments');

SELECT ok(NOT has_function_privilege('anon', 'app.create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet)', 'EXECUTE'), 'anon cannot execute private create');
SELECT ok(NOT has_function_privilege('authenticated', 'app.create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet)', 'EXECUTE'), 'authenticated cannot execute private create');
SELECT ok(NOT has_function_privilege('service_role', 'app.create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet)', 'EXECUTE'), 'service_role cannot execute private create directly');
SELECT ok(NOT has_function_privilege('authenticated', 'app.remove_project_staff_assignment(uuid, uuid, text, text, text, inet)', 'EXECUTE'), 'authenticated cannot execute private remove');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_project_staff_assignment_list(uuid, uuid, boolean)', 'EXECUTE'), 'authenticated cannot execute private list');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_project_staff_assignment_detail(uuid, uuid)', 'EXECUTE'), 'authenticated cannot execute private detail');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_eligible_project_staff_list(uuid, varchar, integer, integer)', 'EXECUTE'), 'authenticated cannot execute private eligible staff list');
SELECT ok(NOT has_function_privilege('authenticated', 'app.has_active_project_assignment(uuid, uuid)', 'EXECUTE'), 'authenticated cannot execute private helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.has_active_project_assignment_role(uuid, uuid, varchar)', 'EXECUTE'), 'authenticated cannot execute private role helper');

SELECT ok(has_function_privilege('service_role', 'public.server_create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet)', 'EXECUTE'), 'service_role can execute service create gateway');
SELECT ok(has_function_privilege('service_role', 'public.server_remove_project_staff_assignment(uuid, uuid, text, text, text, inet)', 'EXECUTE'), 'service_role can execute service remove gateway');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_project_staff_assignment_list(uuid, uuid, boolean)', 'EXECUTE'), 'service_role can execute service list gateway');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_project_staff_assignment_detail(uuid, uuid)', 'EXECUTE'), 'service_role can execute service detail gateway');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_eligible_project_staff_list(uuid, varchar, integer, integer)', 'EXECUTE'), 'service_role can execute eligible staff gateway');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet)', 'EXECUTE'), 'authenticated cannot execute service create gateway');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_project_staff_assignment_list(uuid, uuid, boolean)', 'EXECUTE'), 'authenticated cannot execute service list gateway');

SELECT is_empty(
  $$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_staff_project_records', 'current_project_manager_project_records', 'current_site_supervisor_project_records') $$,
  'no public staff Project read RPCs exist'
);
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) LIKE '%ARRAY[''owner_admin'']%' AND (SELECT pg_get_functiondef('public.current_account()'::regprocedure)) LIKE '%ARRAY[''client'']%', 'current_account still exposes only owner_admin and client usable roles');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%ARRAY[''project_manager''%' AND (SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%ARRAY[''site_supervisor''%', 'current_account does not activate reserved staff roles');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'app' AND tablename = 'projects' AND policyname ILIKE '%staff%'), 'no staff RLS policy added to Projects');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('financial_transactions','ledger_entries','documents')), 'later finance and document tables remain absent');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'app.create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet)'::regprocedure), 'private create is SECURITY DEFINER');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'app.create_project_staff_assignment(uuid, uuid, uuid, varchar, text, text, text, text, inet)'::regprocedure), ARRAY['search_path=""'], 'private create has empty search path');

SELECT * FROM finish();
ROLLBACK;
