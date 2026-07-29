BEGIN;
SELECT plan(41);
-- Coverage marker: PREQ-000001

SELECT ok(NOT has_table_privilege('public', 'app.payment_requests', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'PUBLIC has no direct table access');
SELECT ok(NOT has_table_privilege('anon', 'app.payment_requests', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'anon has no direct table access');
SELECT ok(NOT has_table_privilege('authenticated', 'app.payment_requests', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated has no direct table access');
SELECT ok(NOT has_table_privilege('service_role', 'app.payment_requests', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role has no direct table access');
SELECT ok(NOT has_sequence_privilege('public', 'app.payment_request_number_seq', 'USAGE,SELECT,UPDATE'), 'PUBLIC cannot use request sequence');
SELECT ok(NOT has_sequence_privilege('anon', 'app.payment_request_number_seq', 'USAGE,SELECT,UPDATE'), 'anon cannot use request sequence');
SELECT ok(NOT has_sequence_privilege('authenticated', 'app.payment_request_number_seq', 'USAGE,SELECT,UPDATE'), 'authenticated cannot use request sequence');
SELECT ok(NOT has_sequence_privilege('service_role', 'app.payment_request_number_seq', 'USAGE,SELECT,UPDATE'), 'service role cannot use request sequence directly');
SELECT is_empty($$ SELECT policyname FROM pg_policies WHERE schemaname='app' AND tablename='payment_requests' $$, 'no broad payment request RLS policies');

SELECT ok(NOT has_function_privilege('authenticated', 'app.contractor_local_date()', 'EXECUTE'), 'authenticated cannot execute private date helper');
SELECT ok(NOT has_function_privilege('service_role', 'app.payment_request_effective_status(app.payment_request_status,date)', 'EXECUTE'), 'service role cannot execute private effective status helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_create_payment_request(uuid,uuid,numeric,char,date,date,text,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute private Owner create helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_refresh_payment_request_overdue(uuid,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute private overdue helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.current_payment_request_client_context()', 'EXECUTE'), 'authenticated cannot execute private Client context helper');

SELECT ok(has_function_privilege('service_role', 'public.server_owner_create_payment_request(uuid,uuid,numeric,char,date,date,text,text,text,text,inet)', 'EXECUTE'), 'service role can create payment request');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_update_payment_request(uuid,uuid,integer,uuid,numeric,char,date,date,text,text,text,text,inet)', 'EXECUTE'), 'service role can update payment request');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_send_payment_request(uuid,uuid,integer,text,text,text,inet)', 'EXECUTE'), 'service role can send payment request');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_cancel_payment_request(uuid,uuid,integer,text,text,text,text,inet)', 'EXECUTE'), 'service role can cancel payment request');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_payment_request_list(uuid,integer,integer)', 'EXECUTE'), 'service role can list payment requests');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_payment_request_detail(uuid,uuid)', 'EXECUTE'), 'service role can view payment request detail');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_refresh_payment_request_overdue(uuid,text,text,text,inet)', 'EXECUTE'), 'service role can refresh overdue requests');

SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_create_payment_request(uuid,uuid,numeric,char,date,date,text,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot create through Owner wrapper');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_cancel_payment_request(uuid,uuid,integer,text,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot cancel through Owner wrapper');
SELECT ok(NOT has_function_privilege('anon', 'public.server_owner_payment_request_list(uuid,integer,integer)', 'EXECUTE'), 'anon cannot use Owner list');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_payment_request_list(integer,integer)', 'EXECUTE'), 'authenticated can list own payment requests');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_view_payment_request_detail(uuid,text,text)', 'EXECUTE'), 'authenticated can explicitly view own payment request detail');
SELECT ok(NOT has_function_privilege('service_role', 'public.current_client_payment_request_list(integer,integer)', 'EXECUTE'), 'service role cannot use current Client list');

SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND routine_name IN ('current_client_create_payment_request','current_client_update_payment_request','current_client_send_payment_request','current_client_cancel_payment_request','current_client_set_payment_request_status','server_owner_set_payment_request_status') $$, 'no forbidden payment request status or Client mutation gateways');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%payment%match%' $$, 'payment matching gateways remain absent');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND (routine_name ILIKE '%accountant%payment_request%' OR routine_name ILIKE '%project_manager%payment_request%' OR routine_name ILIKE '%site_supervisor%payment_request%') $$, 'reserved role payment request gateways absent');

SELECT ok((SELECT pg_get_function_result('public.current_client_payment_request_list(integer,integer)'::regprocedure)) NOT ILIKE '%created_by%', 'Client list omits created_by');
SELECT ok((SELECT pg_get_function_result('public.current_client_payment_request_list(integer,integer)'::regprocedure)) NOT ILIKE '%cancelled_by%', 'Client list omits cancelled_by');
SELECT ok((SELECT pg_get_function_result('public.current_client_view_payment_request_detail(uuid,text,text)'::regprocedure)) NOT ILIKE '%cancellation_reason%', 'Client detail omits cancellation reason');
SELECT ok((SELECT pg_get_function_result('public.current_client_view_payment_request_detail(uuid,text,text)'::regprocedure)) NOT ILIKE '%client_id%', 'Client detail omits unrelated Client ID');
SELECT ok((SELECT pg_get_function_result('public.current_client_view_payment_request_detail(uuid,text,text)'::regprocedure)) ILIKE '%paid_amount numeric%', 'Client detail returns calculated paid amount');
SELECT ok((SELECT pg_get_function_result('public.current_client_view_payment_request_detail(uuid,text,text)'::regprocedure)) ILIKE '%remaining_amount numeric%', 'Client detail returns calculated remaining amount');

SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%payment_request%', 'current_account is not modified');
SELECT ok((SELECT pg_get_functiondef('app.owner_create_payment_request(uuid,uuid,numeric,char,date,date,text,text,text,text,inet)'::regprocedure)) NOT ILIKE '%financial_events%' AND (SELECT pg_get_functiondef('app.owner_create_payment_request(uuid,uuid,numeric,char,date,date,text,text,text,text,inet)'::regprocedure)) NOT ILIKE '%ledger_entries%' AND (SELECT pg_get_functiondef('app.owner_create_payment_request(uuid,uuid,numeric,char,date,date,text,text,text,text,inet)'::regprocedure)) NOT ILIKE '%notifications%', 'create request does not create financial or notification records');
SELECT ok((SELECT pg_get_functiondef('app.owner_send_payment_request(uuid,uuid,integer,text,text,text,inet)'::regprocedure)) NOT ILIKE '%insert into app.notifications%' AND (SELECT pg_get_functiondef('app.owner_send_payment_request(uuid,uuid,integer,text,text,text,inet)'::regprocedure)) NOT ILIKE '%ledger_entries%', 'send request has no notification or ledger side effect');
SELECT is_empty($$ SELECT table_name FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payment_matches','project_expenses','account_transfers','currency_exchanges','refunds','payment_uploads','payment_evidence') $$, 'excluded finance workflow tables remain absent');
SELECT is_empty($$ SELECT constraint_name FROM information_schema.table_constraints WHERE table_schema='app' AND table_name='document_links' AND constraint_name ILIKE '%payment_request%fk%' $$, 'document payment request links are not activated');

SELECT * FROM finish();
ROLLBACK;
