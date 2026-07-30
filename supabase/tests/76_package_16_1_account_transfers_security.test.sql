BEGIN;
SELECT plan(23);

SELECT has_function('public','server_owner_create_account_transfer',ARRAY['uuid','uuid','uuid','numeric','character','date','text','text','text','text','text','inet'],'Owner create transfer wrapper exists');
SELECT has_function('public','server_owner_update_account_transfer',ARRAY['uuid','uuid','integer','uuid','uuid','numeric','character','date','text','text','text','text','text','inet'],'Owner update transfer wrapper exists');
SELECT has_function('public','server_owner_submit_account_transfer',ARRAY['uuid','uuid','integer','text','text','text','inet'],'Owner submit transfer wrapper exists');
SELECT has_function('public','server_owner_reject_account_transfer',ARRAY['uuid','uuid','integer','text','text','text','text','inet'],'Owner reject transfer wrapper exists');
SELECT has_function('public','server_owner_approve_account_transfer',ARRAY['uuid','uuid','integer','text','text','text','inet'],'Owner approve transfer wrapper exists');
SELECT has_function('public','server_owner_account_transfer_list',ARRAY['uuid','integer','integer'],'Owner transfer list wrapper exists');
SELECT has_function('public','server_owner_account_transfer_detail',ARRAY['uuid','uuid'],'Owner transfer detail wrapper exists');
SELECT hasnt_function('public','current_client_account_transfer_list',ARRAY['integer','integer'],'no Client transfer list gateway');
SELECT hasnt_function('public','current_client_account_transfer_detail',ARRAY['uuid'],'no Client transfer detail gateway');
SELECT hasnt_function('public','server_accountant_account_transfer_list',ARRAY['uuid','integer','integer'],'no Accountant transfer gateway');
SELECT hasnt_function('public','server_project_manager_account_transfer_list',ARRAY['uuid','integer','integer'],'no Project Manager transfer gateway');
SELECT hasnt_function('public','server_site_supervisor_account_transfer_list',ARRAY['uuid','integer','integer'],'no Site Supervisor transfer gateway');
SELECT ok(NOT has_table_privilege('anon','app.account_transfers','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),'anon has no direct transfer access');
SELECT ok(NOT has_table_privilege('authenticated','app.account_transfers','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),'authenticated has no direct transfer access');
SELECT ok(NOT has_table_privilege('service_role','app.account_transfers','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),'service role has no direct transfer table access');
SELECT ok(NOT has_function_privilege('service_role','app.owner_create_account_transfer(uuid,uuid,uuid,numeric,character,date,text,text,text,text,text,inet)','EXECUTE'),'service role cannot execute private create helper');
SELECT ok(NOT has_function_privilege('service_role','app.account_transfer_duplicate_fingerprint(uuid,uuid,character,date,numeric,text,text)','EXECUTE'),'service role cannot execute private duplicate helper');
SELECT ok(has_function_privilege('service_role','public.server_owner_create_account_transfer(uuid,uuid,uuid,numeric,character,date,text,text,text,text,text,inet)','EXECUTE'),'service role can execute Owner create wrapper');
SELECT ok(has_function_privilege('service_role','public.server_owner_approve_account_transfer(uuid,uuid,integer,text,text,text,inet)','EXECUTE'),'service role can execute Owner approve wrapper');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_create_account_transfer(uuid,uuid,uuid,numeric,character,date,text,text,text,text,text,inet)','EXECUTE'),'authenticated cannot execute Owner create wrapper');
SELECT is_empty($$ SELECT policyname FROM pg_policies WHERE schemaname='app' AND tablename='account_transfers' $$,'no broad transfer RLS policies');
SELECT ok(pg_get_function_result('public.server_owner_account_transfer_list(uuid, integer, integer)'::regprocedure) NOT LIKE '%notes%' AND pg_get_function_result('public.server_owner_account_transfer_list(uuid, integer, integer)'::regprocedure) NOT LIKE '%reference%','transfer list omits raw notes and reference');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%account_transfer%','current_account remains unrelated to transfers');

SELECT * FROM finish();
ROLLBACK;
