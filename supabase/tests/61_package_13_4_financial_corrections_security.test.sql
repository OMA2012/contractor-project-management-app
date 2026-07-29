BEGIN;
SELECT plan(43);

SELECT has_function('app','owner_create_reversal',ARRAY['uuid','uuid','date','text','text','text','text','text','text','inet'],'private create reversal exists');
SELECT has_function('app','owner_submit_reversal',ARRAY['uuid','uuid','integer','text','text','text','inet'],'private submit reversal exists');
SELECT has_function('app','owner_reject_reversal',ARRAY['uuid','uuid','integer','text','text','text','text','inet'],'private reject reversal exists');
SELECT has_function('app','owner_approve_reversal',ARRAY['uuid','uuid','integer','text','text','text','inet'],'private approve reversal exists');
SELECT has_function('app','owner_reversal_list',ARRAY['uuid','integer','integer'],'private reversal list exists');
SELECT has_function('app','owner_reversal_detail',ARRAY['uuid','uuid'],'private reversal detail exists');
SELECT has_function('app','owner_create_adjustment',ARRAY['uuid','uuid','app.adjustment_direction','numeric','date','character','text','uuid','text','text','text','text','text','inet'],'private create adjustment exists');
SELECT has_function('app','owner_update_adjustment',ARRAY['uuid','uuid','integer','uuid','app.adjustment_direction','numeric','date','character','text','uuid','text','text','text','text','inet'],'private update adjustment exists');
SELECT has_function('app','owner_submit_adjustment',ARRAY['uuid','uuid','integer','text','text','text','inet'],'private submit adjustment exists');
SELECT has_function('app','owner_reject_adjustment',ARRAY['uuid','uuid','integer','text','text','text','text','inet'],'private reject adjustment exists');
SELECT has_function('app','owner_approve_adjustment',ARRAY['uuid','uuid','integer','text','text','text','inet'],'private approve adjustment exists');
SELECT has_function('app','owner_adjustment_list',ARRAY['uuid','integer','integer'],'private adjustment list exists');
SELECT has_function('app','owner_adjustment_detail',ARRAY['uuid','uuid'],'private adjustment detail exists');
SELECT has_function('app','ensure_adjustment_control_ledger_account',ARRAY['character'],'private adjustment control helper exists');

SELECT has_function('public','server_owner_create_reversal',ARRAY['uuid','uuid','date','text','text','text','text','text','text','inet'],'server create reversal exists');
SELECT has_function('public','server_owner_approve_reversal',ARRAY['uuid','uuid','integer','text','text','text','inet'],'server approve reversal exists');
SELECT has_function('public','server_owner_create_adjustment',ARRAY['uuid','uuid','app.adjustment_direction','numeric','date','character','text','uuid','text','text','text','text','text','inet'],'server create adjustment exists');
SELECT has_function('public','server_owner_update_adjustment',ARRAY['uuid','uuid','integer','uuid','app.adjustment_direction','numeric','date','character','text','uuid','text','text','text','text','inet'],'server update adjustment exists');
SELECT has_function('public','server_owner_approve_adjustment',ARRAY['uuid','uuid','integer','text','text','text','inet'],'server approve adjustment exists');

SELECT ok(NOT has_table_privilege('authenticated','app.financial_reversals','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated no direct reversal table access');
SELECT ok(NOT has_table_privilege('service_role','app.financial_reversals','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role no direct reversal table access');
SELECT ok(NOT has_table_privilege('authenticated','app.financial_adjustments','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated no direct adjustment table access');
SELECT ok(NOT has_table_privilege('service_role','app.financial_adjustments','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role no direct adjustment table access');
SELECT is_empty($$ SELECT policyname FROM pg_policies WHERE schemaname='app' AND tablename IN ('financial_reversals','financial_adjustments') $$, 'no broad correction RLS policies');

SELECT ok(NOT has_function_privilege('service_role','app.owner_create_reversal(uuid,uuid,date,text,text,text,text,text,text,inet)','EXECUTE'), 'service role cannot execute private create reversal');
SELECT ok(NOT has_function_privilege('authenticated','app.owner_create_reversal(uuid,uuid,date,text,text,text,text,text,text,inet)','EXECUTE'), 'authenticated cannot execute private create reversal');
SELECT ok(NOT has_function_privilege('service_role','app.ensure_adjustment_control_ledger_account(character)','EXECUTE'), 'service role cannot execute adjustment control helper');
SELECT ok(has_function_privilege('service_role','public.server_owner_create_reversal(uuid,uuid,date,text,text,text,text,text,text,inet)','EXECUTE'), 'service role can execute server create reversal');
SELECT ok(has_function_privilege('service_role','public.server_owner_submit_reversal(uuid,uuid,integer,text,text,text,inet)','EXECUTE'), 'service role can execute server submit reversal');
SELECT ok(has_function_privilege('service_role','public.server_owner_reject_reversal(uuid,uuid,integer,text,text,text,text,inet)','EXECUTE'), 'service role can execute server reject reversal');
SELECT ok(has_function_privilege('service_role','public.server_owner_approve_reversal(uuid,uuid,integer,text,text,text,inet)','EXECUTE'), 'service role can execute server approve reversal');
SELECT ok(has_function_privilege('service_role','public.server_owner_create_adjustment(uuid,uuid,app.adjustment_direction,numeric,date,character,text,uuid,text,text,text,text,text,inet)','EXECUTE'), 'service role can execute server create adjustment');
SELECT ok(has_function_privilege('service_role','public.server_owner_update_adjustment(uuid,uuid,integer,uuid,app.adjustment_direction,numeric,date,character,text,uuid,text,text,text,text,inet)','EXECUTE'), 'service role can execute server update adjustment');
SELECT ok(has_function_privilege('service_role','public.server_owner_submit_adjustment(uuid,uuid,integer,text,text,text,inet)','EXECUTE'), 'service role can execute server submit adjustment');
SELECT ok(has_function_privilege('service_role','public.server_owner_reject_adjustment(uuid,uuid,integer,text,text,text,text,inet)','EXECUTE'), 'service role can execute server reject adjustment');
SELECT ok(has_function_privilege('service_role','public.server_owner_approve_adjustment(uuid,uuid,integer,text,text,text,inet)','EXECUTE'), 'service role can execute server approve adjustment');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_create_adjustment(uuid,uuid,app.adjustment_direction,numeric,date,character,text,uuid,text,text,text,text,text,inet)','EXECUTE'), 'authenticated cannot execute server create adjustment');

SELECT throws_ok($$ INSERT INTO app.financial_reversals(financial_event_id,original_transaction_id,reason,full_reversal,reversal_date) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','no',true,current_date) $$, '23514', 'Financial reversals require trusted functions.', 'manual reversal insert denied');
SELECT throws_ok($$ INSERT INTO app.financial_adjustments(financial_event_id,financial_account_id,direction,amount,currency_code,adjustment_date,reason) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','INCREASE',1,'USD',current_date,'no') $$, '23514', 'Financial adjustments require trusted functions.', 'manual adjustment insert denied');

SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%client%reversal%' $$, 'Client reversal functions absent');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%accountant%adjustment%' $$, 'Accountant adjustment functions absent');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_reversal%' AND (SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_adjustment%', 'current_account unchanged for corrections');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payments','payment_matches','expenses','project_expenses','transfers','account_transfers','currency_exchanges','refunds','account_balances')), 'excluded finance workflow tables remain absent except Package 14.2 payment requests');

SELECT * FROM finish();
ROLLBACK;
