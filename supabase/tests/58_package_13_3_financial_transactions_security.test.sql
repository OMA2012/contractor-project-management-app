BEGIN;
SELECT plan(43);

SELECT has_function('app','owner_create_opening_balance',ARRAY['uuid','uuid','numeric','date','character','text','text','text','text','text','text','inet'],'private create opening balance exists');
SELECT has_function('app','owner_update_opening_balance',ARRAY['uuid','uuid','integer','numeric','date','character','text','text','text','text','text','inet'],'private update opening balance exists');
SELECT has_function('app','owner_submit_opening_balance',ARRAY['uuid','uuid','integer','text','text','text','inet'],'private submit opening balance exists');
SELECT has_function('app','owner_reject_opening_balance',ARRAY['uuid','uuid','integer','text','text','text','text','inet'],'private reject opening balance exists');
SELECT has_function('app','owner_approve_opening_balance',ARRAY['uuid','uuid','integer','text','text','text','inet'],'private approve opening balance exists');
SELECT has_function('app','ensure_opening_balance_control_ledger_account',ARRAY['character'],'private control account helper exists');
SELECT has_function('public','server_owner_create_opening_balance',ARRAY['uuid','uuid','numeric','date','character','text','text','text','text','text','text','inet'],'server create opening balance exists');
SELECT has_function('public','server_owner_approve_opening_balance',ARRAY['uuid','uuid','integer','text','text','text','inet'],'server approve opening balance exists');
SELECT has_function('public','server_owner_financial_account_balance',ARRAY['uuid','uuid'],'server account balance exists');
SELECT has_function('public','server_owner_cash_totals_by_currency',ARRAY['uuid'],'server cash totals exists');
SELECT has_function('public','server_owner_bank_totals_by_currency',ARRAY['uuid'],'server bank totals exists');

SELECT ok(NOT has_table_privilege('authenticated','app.financial_events','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated no direct financial event access');
SELECT ok(NOT has_table_privilege('service_role','app.financial_events','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role no direct financial event access');
SELECT ok(NOT has_table_privilege('authenticated','app.financial_transactions','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated no direct financial transaction access');
SELECT ok(NOT has_table_privilege('service_role','app.financial_transactions','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role no direct financial transaction access');
SELECT ok(NOT has_table_privilege('authenticated','app.ledger_entries','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated no direct ledger entry access');
SELECT ok(NOT has_table_privilege('service_role','app.ledger_entries','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role no direct ledger entry access');
SELECT ok(NOT has_table_privilege('authenticated','app.account_opening_balances','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated no direct opening balance access');
SELECT ok(NOT has_sequence_privilege('service_role','app.financial_event_number_seq','USAGE'), 'service role no event sequence usage');
SELECT ok(NOT has_sequence_privilege('service_role','app.financial_transaction_number_seq','USAGE'), 'service role no transaction sequence usage');

SELECT ok(NOT has_function_privilege('authenticated','app.owner_create_opening_balance(uuid,uuid,numeric,date,character,text,text,text,text,text,text,inet)','EXECUTE'), 'authenticated cannot execute private create');
SELECT ok(NOT has_function_privilege('service_role','app.owner_create_opening_balance(uuid,uuid,numeric,date,character,text,text,text,text,text,text,inet)','EXECUTE'), 'service role cannot execute private create');
SELECT ok(NOT has_function_privilege('service_role','app.ensure_opening_balance_control_ledger_account(character)','EXECUTE'), 'service role cannot execute control helper');
SELECT ok(has_function_privilege('service_role','public.server_owner_create_opening_balance(uuid,uuid,numeric,date,character,text,text,text,text,text,text,inet)','EXECUTE'), 'service role can execute server create');
SELECT ok(has_function_privilege('service_role','public.server_owner_update_opening_balance(uuid,uuid,integer,numeric,date,character,text,text,text,text,text,inet)','EXECUTE'), 'service role can execute server update');
SELECT ok(has_function_privilege('service_role','public.server_owner_submit_opening_balance(uuid,uuid,integer,text,text,text,inet)','EXECUTE'), 'service role can execute server submit');
SELECT ok(has_function_privilege('service_role','public.server_owner_reject_opening_balance(uuid,uuid,integer,text,text,text,text,inet)','EXECUTE'), 'service role can execute server reject');
SELECT ok(has_function_privilege('service_role','public.server_owner_approve_opening_balance(uuid,uuid,integer,text,text,text,inet)','EXECUTE'), 'service role can execute server approve');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_create_opening_balance(uuid,uuid,numeric,date,character,text,text,text,text,text,text,inet)','EXECUTE'), 'authenticated cannot execute server create');
SELECT is_empty($$ SELECT policyname FROM pg_policies WHERE schemaname='app' AND tablename IN ('financial_events','financial_transactions','ledger_entries','account_opening_balances') $$, 'no broad central-ledger RLS policies');

SELECT throws_ok($$ INSERT INTO app.financial_events(event_type,event_date,created_by,updated_by) VALUES ('OPENING_BALANCE', current_date, '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000') $$, '23514', 'Financial events require trusted functions.', 'manual event insert denied');
SELECT throws_ok($$ INSERT INTO app.ledger_entries(financial_transaction_id,line_no,ledger_account_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,created_by) VALUES ('00000000-0000-0000-0000-000000000000',1,'00000000-0000-0000-0000-000000000000','USD',1,0,'USD',1,0,'00000000-0000-0000-0000-000000000000') $$, '23514', 'Ledger entries require trusted posting.', 'manual ledger entry insert denied');

SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%client%opening%' $$, 'Client opening balance functions absent');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%accountant%opening%' $$, 'Accountant opening balance functions absent');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%project_manager%opening%' $$, 'Project Manager opening balance functions absent');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%site_supervisor%opening%' $$, 'Site Supervisor opening balance functions absent');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_event%' AND (SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%ledger_entries%', 'current_account unchanged for Package 13.3');
SELECT ok(pg_get_function_result('public.server_owner_opening_balance_list(uuid, integer, integer)'::regprocedure) NOT LIKE '%notes%', 'opening balance list omits raw notes');
SELECT ok(pg_get_function_result('public.server_owner_opening_balance_detail(uuid, uuid)'::regprocedure) LIKE '%notes%', 'opening balance detail includes notes for Owner/Admin');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payments','expenses','transfers','currency_exchanges','refunds','reversals','adjustments','account_balances')), 'excluded workflow tables remain absent except Package 14.2 payment requests');
SELECT has_function('public','server_owner_create_client_payment',ARRAY['uuid','uuid','numeric','character','date','uuid','text','text','text','text','text','text','inet'],'Package 14.1 client payment gateway exists');
SELECT hasnt_function('public','server_owner_create_project_expense',ARRAY['uuid'],'project expense gateway absent');
SELECT hasnt_function('public','server_owner_create_account_transfer',ARRAY['uuid'],'transfer gateway absent');

SELECT * FROM finish();
ROLLBACK;
