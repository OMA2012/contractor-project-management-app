BEGIN;
SELECT plan(34);

SELECT has_function('app', 'ensure_financial_asset_ledger_account', ARRAY['uuid'], 'private ledger sync helper exists');
SELECT has_function('app', 'sync_financial_account_ledger_account', ARRAY[]::text[], 'private ledger sync trigger exists');
SELECT has_function('app', 'owner_create_exchange_rate', ARRAY['uuid','date','character','character','numeric','text','text','text','text','text','inet'], 'private create exchange rate exists');
SELECT has_function('app', 'owner_exchange_rate_list', ARRAY['uuid','character','character','integer','integer'], 'private list exchange rates exists');
SELECT has_function('app', 'owner_exchange_rate_detail', ARRAY['uuid','uuid'], 'private detail exchange rate exists');
SELECT has_function('app', 'convert_amount_with_exchange_rate', ARRAY['numeric','character','character','character','character','numeric'], 'private conversion helper exists');
SELECT has_function('public', 'server_owner_create_exchange_rate', ARRAY['uuid','date','character','character','numeric','text','text','text','text','text','inet'], 'server create exchange rate exists');
SELECT has_function('public', 'server_owner_exchange_rate_list', ARRAY['uuid','character','character','integer','integer'], 'server list exchange rates exists');
SELECT has_function('public', 'server_owner_exchange_rate_detail', ARRAY['uuid','uuid'], 'server detail exchange rate exists');

SELECT ok(NOT has_table_privilege('authenticated', 'app.ledger_accounts', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated has no direct ledger account access');
SELECT ok(NOT has_table_privilege('service_role', 'app.ledger_accounts', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role has no direct ledger account access');
SELECT ok(NOT has_table_privilege('authenticated', 'app.exchange_rates', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated has no direct exchange rate access');
SELECT ok(NOT has_table_privilege('service_role', 'app.exchange_rates', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'service role has no direct exchange rate access');
SELECT ok(NOT has_function_privilege('authenticated', 'app.ensure_financial_asset_ledger_account(uuid)', 'EXECUTE'), 'authenticated cannot execute ledger sync helper');
SELECT ok(NOT has_function_privilege('service_role', 'app.ensure_financial_asset_ledger_account(uuid)', 'EXECUTE'), 'service role cannot execute ledger sync helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.convert_amount_with_exchange_rate(numeric,character,character,character,character,numeric)', 'EXECUTE'), 'authenticated cannot execute conversion helper');
SELECT ok(NOT has_function_privilege('service_role', 'app.convert_amount_with_exchange_rate(numeric,character,character,character,character,numeric)', 'EXECUTE'), 'service role cannot execute conversion helper');
SELECT ok(NOT has_function_privilege('authenticated', 'app.owner_create_exchange_rate(uuid,date,character,character,numeric,text,text,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute private rate create');
SELECT ok(NOT has_function_privilege('service_role', 'app.owner_create_exchange_rate(uuid,date,character,character,numeric,text,text,text,text,text,inet)', 'EXECUTE'), 'service role cannot execute private rate create');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_create_exchange_rate(uuid,date,character,character,numeric,text,text,text,text,text,inet)', 'EXECUTE'), 'service role can execute server rate create');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_exchange_rate_list(uuid,character,character,integer,integer)', 'EXECUTE'), 'service role can execute server rate list');
SELECT ok(has_function_privilege('service_role', 'public.server_owner_exchange_rate_detail(uuid,uuid)', 'EXECUTE'), 'service role can execute server rate detail');
SELECT ok(NOT has_function_privilege('authenticated', 'public.server_owner_create_exchange_rate(uuid,date,character,character,numeric,text,text,text,text,text,inet)', 'EXECUTE'), 'authenticated cannot execute server rate create');
SELECT is_empty($$ SELECT policyname FROM pg_policies WHERE schemaname = 'app' AND tablename IN ('ledger_accounts','exchange_rates') $$, 'no broad finance RLS policies');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_ledger_account','current_exchange_rate','current_client_ledger_accounts','current_client_exchange_rates','current_accountant_ledger_accounts','current_accountant_exchange_rates','current_project_manager_ledger_accounts','current_site_supervisor_ledger_accounts') $$, 'no Client or reserved-role ledger/rate RPCs');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%ledger_account%' AND (SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%exchange_rate%', 'current_account unchanged for Package 13.2');
SELECT ok(pg_get_function_result('public.server_owner_exchange_rate_list(uuid, character, character, integer, integer)'::regprocedure) NOT LIKE '%source_reference%', 'rate list output omits source reference');
SELECT ok(pg_get_function_result('public.server_owner_exchange_rate_detail(uuid, uuid)'::regprocedure) LIKE '%source_reference%', 'rate detail output includes source reference for Owner/Admin');
SELECT throws_ok($$ INSERT INTO app.ledger_accounts (code, name, account_kind, currency_code, normal_side) VALUES ('MANUAL-CONTROL', 'Manual Control', 'CONTROL', 'USD', 'CREDIT') $$, '23514', 'Ledger accounts are system-managed.', 'manual ledger insert denied');

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000005501', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.55@example.test', '', now(), '{}', '{}', now(), now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000005501', 'owner.55@example.test', 'Owner Fifty Five', decode('5555555555555555555555555555555555555555555555555555555555555555', 'hex'), 'req-55', 'corr-55');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005501', true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Security Rate Contractor', 'Security Rate Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005501'));
SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005501', DATE '2026-07-28', 'USD', 'SAR', 3.750000000000, 'MANUAL');

SELECT throws_ok($$ UPDATE app.exchange_rates SET source = 'CORRECTED' $$, '23514', 'Exchange rates are append-only.', 'exchange rate update prevented');
SELECT throws_ok($$ DELETE FROM app.exchange_rates $$, '23514', 'Exchange rates cannot be deleted.', 'exchange rate delete prevented');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%accountant%exchange%' $$, 'Accountant exchange-rate functions absent');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%client%exchange%' $$, 'Client exchange-rate functions absent');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('account_balances','payments','expenses','transfers','refunds','reversals','adjustments')), 'excluded finance workflow tables remain absent except approved currency exchanges');

SELECT * FROM finish();
ROLLBACK;
