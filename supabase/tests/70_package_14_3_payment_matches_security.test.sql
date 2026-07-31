BEGIN;
SELECT plan(31);

SELECT ok(NOT has_table_privilege('public', 'app.payment_matches', 'SELECT'), 'PUBLIC cannot select payment matches');
SELECT ok(NOT has_table_privilege('anon', 'app.payment_matches', 'SELECT'), 'anon cannot select payment matches');
SELECT ok(NOT has_table_privilege('authenticated', 'app.payment_matches', 'SELECT'), 'authenticated cannot select payment matches');
SELECT ok(NOT has_table_privilege('service_role', 'app.payment_matches', 'SELECT'), 'service_role has no direct table select');
SELECT ok(NOT has_table_privilege('authenticated', 'app.payment_matches', 'INSERT'), 'authenticated cannot insert payment matches');
SELECT ok(NOT has_table_privilege('authenticated', 'app.payment_matches', 'UPDATE'), 'authenticated cannot update payment matches');
SELECT ok(NOT has_table_privilege('authenticated', 'app.payment_matches', 'DELETE'), 'authenticated cannot delete payment matches');

SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_create_payment_match(uuid,uuid,uuid,numeric,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute private create helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.validate_payment_match_relationship(uuid,uuid,numeric)', 'EXECUTE'), 'authenticated cannot execute validation helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.client_payment_economically_active(uuid)', 'EXECUTE'), 'authenticated cannot execute reversal helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.payment_request_amounts(uuid)', 'EXECUTE'), 'authenticated cannot execute aggregation helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.sync_payment_request_status_from_matches(uuid,uuid,text,uuid,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute status sync helper');

SELECT ok(has_function_privilege('service_role', 'public.server_owner_create_payment_match(uuid,uuid,uuid,numeric,text,text,text,inet)', 'EXECUTE'), 'service role can create match draft');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_update_payment_match(uuid,uuid,uuid,uuid,numeric,uuid,uuid,numeric,text,text,text,inet)', 'EXECUTE'), 'service role can update match draft');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_approve_payment_match(uuid,uuid,text,text,text,inet)', 'EXECUTE'), 'service role can approve match');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_void_payment_match(uuid,uuid,text,text,text,text,inet)', 'EXECUTE'), 'service role can void match');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_payment_match_list(uuid,integer,integer)', 'EXECUTE'), 'service role can list matches');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_payment_match_detail(uuid,uuid)', 'EXECUTE'), 'service role can inspect match detail');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_client_payment_availability(uuid,uuid)', 'EXECUTE'), 'service role can inspect payment availability');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_payment_request_balance(uuid,uuid)', 'EXECUTE'), 'service role can inspect request balance');

SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_create_payment_match(uuid,uuid,uuid,numeric,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot create match through wrapper');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_approve_payment_match(uuid,uuid,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot approve match through wrapper');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_void_payment_match(uuid,uuid,text,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot void match through wrapper');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_payment_request_list(integer,integer)', 'EXECUTE'), 'authenticated keeps request aggregate list gateway');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_view_payment_request_detail(uuid,text,text)', 'EXECUTE'), 'authenticated keeps request aggregate detail gateway');

SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%current_client%payment_match%' $$, 'no Client raw match gateway exists');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND (routine_name ILIKE '%accountant%payment_match%' OR routine_name ILIKE '%project_manager%payment_match%' OR routine_name ILIKE '%site_supervisor%payment_match%') $$, 'reserved role match gateways absent');
SELECT ok((SELECT pg_get_function_result('public.current_client_payment_request_list(integer,integer)'::regprocedure)) NOT ILIKE '%matched_by%' AND (SELECT pg_get_function_result('public.current_client_view_payment_request_detail(uuid,text,text)'::regprocedure)) NOT ILIKE '%void_reason%', 'Client request responses omit raw match internals');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%payment_match%', 'current_account is not modified');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%set%payment_match%status%' $$, 'no generic match status setter');
SELECT is_empty($$ SELECT table_name FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('refunds','payment_uploads','payment_evidence') $$, 'excluded finance workflow tables remain absent except approved project expenses, account transfers and currency exchanges');

SELECT * FROM finish();
ROLLBACK;
