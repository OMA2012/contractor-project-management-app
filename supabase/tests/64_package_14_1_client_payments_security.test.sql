BEGIN;
SELECT plan(35);

SELECT ok(NOT has_table_privilege('public', 'app.client_payments', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'PUBLIC has no direct table access');
SELECT ok(NOT has_table_privilege('anon', 'app.client_payments', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'anon has no direct table access');
SELECT ok(NOT has_table_privilege('authenticated', 'app.client_payments', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated has no direct table access');
SELECT ok(NOT has_table_privilege('service_role', 'app.client_payments', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service_role has no direct table access');
SELECT is_empty($$ SELECT policyname FROM pg_policies WHERE schemaname='app' AND tablename='client_payments' $$, 'no broad client payment RLS policies');

SELECT ok(NOT has_function_privilege('authenticated', 'app.ensure_client_payment_control_ledger_account(char)', 'EXECUTE'), 'authenticated cannot execute control helper');
SELECT ok(NOT has_function_privilege('service_role', 'app.ensure_client_payment_control_ledger_account(char)', 'EXECUTE'), 'service_role cannot execute private control helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_approve_client_payment(uuid,uuid,integer,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute private approval helper');

SELECT ok(has_function_privilege('service_role', 'public.server_owner_create_client_payment(uuid,uuid,numeric,char,date,uuid,text,text,text,text,text,text,inet)', 'EXECUTE'), 'service role can create Owner payment');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_update_client_payment(uuid,uuid,integer,numeric,char,date,uuid,text,text,text,text,text,text,inet)', 'EXECUTE'), 'service role can update Owner payment');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_verify_client_submitted_payment(uuid,uuid,integer,uuid,text,text,text,text,inet)', 'EXECUTE'), 'service role can verify Client submission');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_submit_client_payment(uuid,uuid,integer,text,text,text,inet)', 'EXECUTE'), 'service role can submit Owner payment');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_reject_client_payment(uuid,uuid,integer,text,text,text,text,inet)', 'EXECUTE'), 'service role can reject payment');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_approve_client_payment(uuid,uuid,integer,text,text,text,inet)', 'EXECUTE'), 'service role can approve payment');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_client_payment_list(uuid,integer,integer)', 'EXECUTE'), 'service role can list payments');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_client_payment_detail(uuid,uuid)', 'EXECUTE'), 'service role can view payment detail');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_project_client_payment_totals(uuid,uuid)', 'EXECUTE'), 'service role can query project totals');

SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_approve_client_payment(uuid,uuid,integer,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute Owner approval wrapper');
SELECT ok(NOT has_function_privilege('anon', 'public.server_owner_approve_client_payment(uuid,uuid,integer,text,text,text,inet)', 'EXECUTE'), 'anon cannot execute Owner approval wrapper');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_submit_payment(uuid,numeric,char,date,text,text,text,text)', 'EXECUTE'), 'authenticated can execute Client submission gateway');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_approved_payment_list(integer,integer)', 'EXECUTE'), 'authenticated can list own approved payments');
SELECT ok(has_function_privilege('authenticated', 'public.current_client_approved_payment_detail(uuid)', 'EXECUTE'), 'authenticated can view own approved payment detail');
SELECT ok(NOT has_function_privilege('service_role', 'public.current_client_submit_payment(uuid,numeric,char,date,text,text,text,text)', 'EXECUTE'), 'service role cannot use current Client submission gateway');

SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND routine_name IN ('current_client_update_payment','current_client_approve_payment','current_client_reject_payment','current_client_select_payment_account','current_client_payment_notes') $$, 'no forbidden Client payment gateways');

SELECT ok((SELECT pg_get_function_result('public.current_client_approved_payment_list(integer,integer)'::regprocedure)) NOT ILIKE '%payer_name%', 'Client list omits payer name');
SELECT ok((SELECT pg_get_function_result('public.current_client_approved_payment_list(integer,integer)'::regprocedure)) NOT ILIKE '%received_account_id%', 'Client list omits received account');
SELECT ok((SELECT pg_get_function_result('public.current_client_approved_payment_list(integer,integer)'::regprocedure)) NOT ILIKE '%notes%', 'Client list omits notes');
SELECT ok((SELECT pg_get_function_result('public.current_client_approved_payment_detail(uuid)'::regprocedure)) NOT ILIKE '%approved_by%', 'Client detail omits approver');
SELECT ok((SELECT pg_get_function_result('public.current_client_approved_payment_detail(uuid)'::regprocedure)) NOT ILIKE '%exchange_rate%', 'Client detail omits exchange-rate internals');

SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%client_payment%', 'current_account is not modified for payments');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%accountant%payment%' $$, 'Accountant payment access is not activated');
SELECT is_empty($$ SELECT table_name FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('account_transfers','currency_exchanges','refunds','payment_uploads','payment_evidence') $$, 'excluded finance workflow tables absent except approved request, matching and expense packages');
SELECT ok((SELECT pg_get_functiondef('app.owner_approve_client_payment(uuid,uuid,integer,text,text,text,inet)'::regprocedure)) NOT ILIKE '%create_progress_update_published_notification%', 'payment approval does not produce notifications');
SELECT ok((SELECT pg_get_functiondef('app.owner_approve_client_payment(uuid,uuid,integer,text,text,text,inet)'::regprocedure)) NOT ILIKE '%document_links%', 'payment approval does not activate document links');
SELECT ok((SELECT pg_get_function_arguments('public.current_client_submit_payment(uuid,numeric,char,date,text,text,text,text)'::regprocedure)) NOT ILIKE '%notes%', 'Client submission gateway does not accept contractor notes');

SELECT * FROM finish();
ROLLBACK;
