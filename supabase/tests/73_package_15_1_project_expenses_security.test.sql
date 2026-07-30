BEGIN;
SELECT plan(15);

SELECT has_function('public','server_owner_create_project_expense',ARRAY['uuid','uuid','uuid','numeric','character','uuid','date','text','text','text','text','text','text','text','inet'],'Owner create expense wrapper exists');
SELECT has_function('public','server_owner_approve_project_expense',ARRAY['uuid','uuid','integer','text','text','text','inet'],'Owner approve expense wrapper exists');
SELECT has_function('public','server_owner_project_expense_totals',ARRAY['uuid','uuid'],'Owner project expense totals wrapper exists');
SELECT hasnt_function('public','current_client_project_expense_list',ARRAY['integer','integer'],'no Client expense list gateway');
SELECT hasnt_function('public','current_client_project_expense_detail',ARRAY['uuid'],'no Client expense detail gateway');
SELECT hasnt_function('public','server_accountant_project_expense_list',ARRAY['uuid','integer','integer'],'no Accountant gateway');
SELECT hasnt_function('public','server_project_manager_project_expense_list',ARRAY['uuid','integer','integer'],'no Project Manager gateway');
SELECT hasnt_function('public','server_site_supervisor_project_expense_list',ARRAY['uuid','integer','integer'],'no Site Supervisor gateway');
SELECT ok(NOT has_table_privilege('anon','app.project_expenses','SELECT'),'anon cannot select project expenses');
SELECT ok(NOT has_table_privilege('authenticated','app.project_expenses','SELECT'),'authenticated cannot select project expenses');
SELECT ok(NOT has_table_privilege('service_role','app.project_expenses','INSERT'),'service role has no direct insert');
SELECT ok(NOT has_table_privilege('authenticated','app.expense_categories','UPDATE'),'authenticated cannot update categories directly');
SELECT ok(NOT has_sequence_privilege('authenticated','app.project_expense_number_seq','USAGE'),'authenticated cannot use EXP sequence');
SELECT ok(has_function_privilege('service_role','public.server_owner_create_project_expense(uuid,uuid,uuid,numeric,character,uuid,date,text,text,text,text,text,text,text,inet)','EXECUTE'),'service role can execute Owner create wrapper');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_create_project_expense(uuid,uuid,uuid,numeric,character,uuid,date,text,text,text,text,text,text,text,inet)','EXECUTE'),'authenticated cannot execute Owner create wrapper');

SELECT * FROM finish();
ROLLBACK;
