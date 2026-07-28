BEGIN;
SELECT plan(21);

SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'app.calculate_project_completion(uuid)'::regprocedure), 'private Project calculator is security definer');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.current_client_project_completion(uuid)'::regprocedure), 'public Client Project completion is security definer');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'app.calculate_project_completion(uuid)'::regprocedure), ARRAY['search_path=""'], 'private Project calculator has empty search path');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'public.current_client_project_phase_completion(uuid)'::regprocedure), ARRAY['search_path=""'], 'public Client phase completion has empty search path');
SELECT ok(NOT has_function_privilege('authenticated', 'app.calculate_project_completion(uuid)', 'EXECUTE'), 'authenticated cannot execute private Project calculator');
SELECT ok(NOT has_function_privilege('service_role', 'app.calculate_project_completion(uuid)', 'EXECUTE'), 'service_role cannot execute private Project calculator directly');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_project_completion(uuid, uuid)', 'EXECUTE'), 'authenticated cannot execute private Owner Project completion');
SELECT ok(NOT has_function_privilege('service_role', 'app.owner_project_completion(uuid, uuid)', 'EXECUTE'), 'service_role cannot execute private Owner Project completion directly');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_project_completion(uuid, uuid)', 'EXECUTE'), 'service_role can execute Owner Project gateway');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_project_phase_completion(uuid, uuid)', 'EXECUTE'), 'service_role can execute Owner phase gateway');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_project_completion(uuid, uuid)', 'EXECUTE'), 'authenticated cannot execute Owner Project gateway');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_project_completion(uuid)', 'EXECUTE'), 'authenticated can execute Client Project completion');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_project_phase_completion(uuid)', 'EXECUTE'), 'authenticated can execute Client phase completion');
SELECT ok(NOT has_function_privilege('anon', 'public.current_client_project_completion(uuid)', 'EXECUTE'), 'anon cannot execute Client Project completion');
SELECT ok(NOT has_function_privilege('service_role', 'public.current_client_project_completion(uuid)', 'EXECUTE'), 'service_role cannot execute Client Project completion');
SELECT ok(NOT has_table_privilege('authenticated', 'app.tasks', 'SELECT'), 'authenticated has no direct task SELECT');
SELECT ok(NOT has_table_privilege('service_role', 'app.tasks', 'SELECT'), 'service_role has no direct task SELECT');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_project_manager_completion','current_site_supervisor_completion','current_accountant_completion','current_assigned_project_completion','current_assigned_phase_completion') $$, 'no reserved-role or assigned completion RPC exists');
SELECT ok(pg_get_functiondef('public.current_account()'::regprocedure) NOT ILIKE '%project_manager%access_allowed%true%' AND pg_get_functiondef('public.current_account()'::regprocedure) NOT ILIKE '%site_supervisor%access_allowed%true%' AND pg_get_functiondef('public.current_account()'::regprocedure) NOT ILIKE '%accountant%access_allowed%true%', 'current_account does not activate reserved roles');
SELECT ok(pg_get_functiondef('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%counted_task_count%' AND pg_get_functiondef('public.current_client_project_completion(uuid)'::regprocedure) NOT ILIKE '%total_weight%', 'Client Project completion exposes aggregate only');
SELECT ok(pg_get_functiondef('public.current_client_project_phase_completion(uuid)'::regprocedure) NOT ILIKE '%counted_task_count%' AND pg_get_functiondef('public.current_client_project_phase_completion(uuid)'::regprocedure) NOT ILIKE '%total_weight%', 'Client phase completion exposes aggregate only');

SELECT * FROM finish();
ROLLBACK;
