BEGIN;
SELECT plan(39);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000005301', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.53@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005302', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.53@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005303', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.53@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000005301', 'owner.53@example.test', 'Owner Fifty Three', decode('5353535353535353535353535353535353535353535353535353535353535353', 'hex'), 'req-53', 'corr-53');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005301', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Financial Account Contractor', 'Financial Account Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000005302', '00000000-0000-0000-0000-000000005302', 'client.53@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301')),
  ('10000000-0000-0000-0000-000000005303', '00000000-0000-0000-0000-000000005303', 'accountant.53@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000005302', 'Client Fifty Three', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301')),
  ('10000000-0000-0000-0000-000000005303', 'Accountant Fifty Three', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000005302', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'), true),
  ('10000000-0000-0000-0000-000000005303', 'accountant', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005301'), true);

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005301', 'Main Cash', 'CASH', 'USD') $$, 'Owner can create CASH account');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005301', 'Main Bank', 'BANK', 'SAR', 'Bank One', '****1234', decode('1234', 'hex')) $$, 'Owner can create BANK account');
SELECT results_eq($$ SELECT account_number::text FROM app.financial_accounts ORDER BY account_number $$, $$ VALUES ('FA-000001'::text), ('FA-000002'::text) $$, 'global six digit financial account numbers generated');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005301', 'Bad Cash', 'CASH', 'USD', 'Bank', '****9999') $$, '23514', NULL, 'CASH rejects bank metadata');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005301', 'Bad Bank', 'BANK', 'USD') $$, '23514', NULL, 'BANK requires masked bank metadata');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005301', 'Bad Cash Secret', 'CASH', 'USD', NULL, NULL, decode('1234', 'hex')) $$, '23514', NULL, 'CASH rejects encrypted account details');
SELECT results_eq($$ SELECT account_type::text, currency_code, is_active, encrypted_account_details IS NOT NULL FROM app.financial_accounts WHERE name = 'Main Bank' $$, $$ VALUES ('BANK'::text, 'SAR'::char(3), true, true) $$, 'BANK row stores type currency active flag and encrypted details');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE name = 'Main Cash'), 1, 'Petty Cash', 'CASH', 'SAR', NULL, NULL, NULL, 'safe note') $$, 'Owner can update metadata before ledger posting exists');
SELECT results_eq($$ SELECT name::text, currency_code, version_number FROM app.financial_accounts WHERE account_number = 'FA-000001' $$, $$ VALUES ('Petty Cash'::text, 'SAR'::char(3), 2) $$, 'update changes name/currency and increments version');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 1, 'Stale Cash', 'CASH', 'SAR') $$, '40001', 'Financial account version conflict.', 'stale update rejected');
SELECT throws_ok($$ UPDATE app.financial_accounts SET account_number = 'FA-999999' WHERE account_number = 'FA-000001' $$, '23514', 'Financial account number is immutable.', 'account number immutable');
SELECT lives_ok($$ SELECT * FROM public.server_owner_deactivate_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 2) $$, 'Owner can deactivate account');
SELECT results_eq($$ SELECT is_active, version_number FROM app.financial_accounts WHERE account_number = 'FA-000001' $$, $$ VALUES (false, 3) $$, 'deactivate sets inactive and increments version');
SELECT lives_ok($$ SELECT * FROM public.server_owner_deactivate_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 3) $$, 'repeat deactivate is idempotent');
SELECT results_eq($$ SELECT is_active, version_number FROM app.financial_accounts WHERE account_number = 'FA-000001' $$, $$ VALUES (false, 3) $$, 'idempotent deactivate does not increment');
SELECT lives_ok($$ SELECT * FROM public.server_owner_activate_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 3) $$, 'Owner can activate account');
SELECT results_eq($$ SELECT is_active, version_number FROM app.financial_accounts WHERE account_number = 'FA-000001' $$, $$ VALUES (true, 4) $$, 'activate sets active and increments version');
SELECT lives_ok($$ SELECT * FROM public.server_owner_archive_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 4) $$, 'Owner can archive account');
SELECT ok((SELECT NOT is_active AND archived_at IS NOT NULL AND archived_by IS NOT NULL AND version_number = 5 FROM app.financial_accounts WHERE account_number = 'FA-000001'), 'archive sets inactive archive fields and version');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 5, 'Archived Cash', 'CASH', 'USD') $$, '23514', 'Financial account cannot be updated.', 'archived account cannot be updated');
SELECT throws_ok($$ SELECT * FROM public.server_owner_activate_financial_account('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 5) $$, '23514', 'Financial account cannot be activated.', 'archived account cannot be activated');
SELECT throws_ok($$ DELETE FROM app.financial_accounts WHERE account_number = 'FA-000001' $$, '23514', 'Financial accounts cannot be deleted.', 'financial account cannot be deleted');
SELECT results_eq($$ SELECT account_number, name FROM public.server_owner_financial_account_list('00000000-0000-0000-0000-000000005301', false, 50, 0) $$, $$ VALUES ('FA-000002'::text, 'Main Bank'::text) $$, 'default Owner list excludes archived rows');
SELECT results_eq($$ SELECT count(*)::integer FROM public.server_owner_financial_account_list('00000000-0000-0000-0000-000000005301', true, 50, 0) $$, $$ VALUES (2) $$, 'Owner list can include archived rows');
SELECT ok(pg_get_function_result('public.server_owner_financial_account_list(uuid, boolean, integer, integer)'::regprocedure) NOT LIKE '%encrypted_account_details%', 'list return omits encrypted details');
SELECT ok(pg_get_function_result('public.server_owner_financial_account_detail(uuid, uuid)'::regprocedure) NOT LIKE '%encrypted_account_details%', 'detail return omits encrypted details');
SELECT results_eq($$ SELECT account_number, notes FROM public.server_owner_financial_account_detail('00000000-0000-0000-0000-000000005301', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001')) $$, $$ VALUES ('FA-000001'::text, 'safe note'::text) $$, 'Owner detail returns safe account metadata');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'financial_account_created'), 2, 'create activity logged twice');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'financial_account_updated'), 1, 'update activity logged once');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'financial_account_deactivated'), 1, 'deactivate activity logged once');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'financial_account_activated'), 1, 'activate activity logged once');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'financial_account_archived'), 1, 'archive activity logged once');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE previous_values::text LIKE '%1234%' OR new_values::text LIKE '%1234%' OR metadata::text LIKE '%1234%' OR previous_values::text LIKE '%safe note%' OR new_values::text LIKE '%safe note%' OR metadata::text LIKE '%safe note%'), 'activity logs omit encrypted details and notes');
SELECT throws_ok($$ SELECT * FROM public.server_owner_financial_account_list('00000000-0000-0000-0000-000000005302', true, 50, 0) $$, '42501', 'Privileged operation denied.', 'Client cannot list financial accounts');
SELECT throws_ok($$ SELECT * FROM public.server_owner_financial_account_list('00000000-0000-0000-0000-000000005303', true, 50, 0) $$, '42501', 'Privileged operation denied.', 'Accountant cannot list financial accounts');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_financial_account_list','current_accountant_financial_accounts','current_project_manager_financial_accounts','current_site_supervisor_financial_accounts') $$, 'reserved role current financial RPCs absent');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('account_balances','payments','expenses','transfers','refunds','reversals','adjustments')), 'excluded financial workflow tables remain absent');
SELECT is((SELECT count(*)::integer FROM app.financial_accounts), 2, 'only account rows created');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_account%', 'current_account not changed');

SELECT * FROM finish();
ROLLBACK;
