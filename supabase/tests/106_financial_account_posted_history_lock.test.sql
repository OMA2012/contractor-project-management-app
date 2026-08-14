BEGIN;
SELECT plan(33);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010601', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.106@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010602', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.106@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010603', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.106@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010601', 'owner-a.106@example.test', 'Owner A 106', decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'), 'req-106', 'corr-106');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010601', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('History Lock Contractor', 'History Lock Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010602', '00000000-0000-0000-0000-000000010602', 'owner-b.106@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601')),
  ('10000000-0000-0000-0000-000000010603', '00000000-0000-0000-0000-000000010603', 'client.106@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601')
FROM app.users
WHERE auth_subject IN ('00000000-0000-0000-0000-000000010602','00000000-0000-0000-0000-000000010603');

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000010602', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'), true),
  ('10000000-0000-0000-0000-000000010603', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010601'), true);

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010601', 'Prehistory Cash', 'CASH', 'USD');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE name = 'Prehistory Cash'), 1, 'Prehistory Bank', 'BANK', 'USD', 'Bank 106', '****0106') $$, 'no-history account can make otherwise-valid account_type change');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE name = 'Prehistory Bank'), 2, 'Prehistory Bank SAR', 'BANK', 'SAR', 'Bank 106', '****0106') $$, 'no-history account can make otherwise-valid currency_code change');
SELECT results_eq($$ SELECT fa.currency_code, la.currency_code FROM app.financial_accounts fa JOIN app.ledger_accounts la ON la.financial_account_id = fa.id AND la.account_kind = 'FINANCIAL_ASSET' WHERE fa.account_number = 'FA-000001' $$, $$ VALUES ('SAR'::char(3), 'SAR'::char(3)) $$, 'linked FINANCIAL_ASSET ledger currency follows permitted pre-history currency change');
SELECT is(app.financial_account_has_posted_history((SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001')), false, 'unused synced ledger account does not create posted history');

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010601', 'Opening Locked Cash', 'CASH', 'USD');
SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 100, DATE '2026-08-01', 'USD', 'posted opening lock', NULL, 'open-106');
SELECT is(app.financial_account_has_posted_history((SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002')), false, 'draft financial event alone does not create posted history');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_events WHERE description = 'posted opening lock'), 1) $$, 'opening balance submitted for posted-history test');
SELECT is(app.financial_account_has_posted_history((SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002')), false, 'submitted financial event alone does not create posted history');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000010602', (SELECT id FROM app.financial_events WHERE description = 'posted opening lock'), 2) $$, 'posted Opening Balance approved');
SELECT is(app.financial_account_has_posted_history((SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002')), true, 'POSTED Opening Balance counts as posted history');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 1, 'Blocked Type', 'BANK', 'USD', 'Blocked Bank', '****9999') $$, '23514', 'Financial account type and currency are immutable after posted financial history.', 'account_type change rejected after posted history');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 1, 'Blocked Currency', 'CASH', 'SAR') $$, '23514', 'Financial account type and currency are immutable after posted financial history.', 'currency_code change rejected after posted history');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 1, 'Posted History Name Change', 'CASH', 'USD', NULL, NULL, NULL, 'notes may still change') $$, 'name and notes remain mutable after posted history');
SELECT lives_ok($$ SELECT * FROM public.server_owner_deactivate_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 2) $$, 'deactivate remains allowed after posted history');
SELECT lives_ok($$ SELECT * FROM public.server_owner_activate_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 3) $$, 'activate remains allowed after posted history');
SELECT lives_ok($$ SELECT * FROM public.server_owner_archive_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 4) $$, 'archive remains governed by existing archive rule');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 5, 'Archived Posted Account', 'CASH', 'USD') $$, '23514', 'Financial account cannot be updated.', 'archived account update remains governed by existing rule');

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010601', 'Rejected Path Cash', 'CASH', 'USD');
SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000003'), 10, DATE '2026-08-02', 'USD', 'reject path', NULL, 'reject-106');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_events WHERE description = 'reject path'), 1) $$, 'rejected path opening submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reject_opening_balance('00000000-0000-0000-0000-000000010602', (SELECT id FROM app.financial_events WHERE description = 'reject path'), 2, 'not authoritative') $$, 'rejected financial event created without ledger history');
SELECT is(app.financial_account_has_posted_history((SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000003')), false, 'rejected financial event without posted ledger entries does not lock');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000003'), 1, 'Rejected Path Bank', 'BANK', 'SAR', 'Rejected Bank', '****0303') $$, 'rejected state alone does not block otherwise-valid type and currency changes');

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010601', 'Zero Balance Cash', 'CASH', 'USD');
SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000004'), 50, DATE '2026-08-03', 'USD', 'zero original', NULL, 'zero-open-106');
SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_events WHERE description = 'zero original'), 1);
SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000010602', (SELECT id FROM app.financial_events WHERE description = 'zero original'), 2);
SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000010601', (SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id = ft.financial_event_id WHERE fe.description = 'zero original'), DATE '2026-08-03', 'reverse to zero', 'zero reversal', 'zero-rev-106');
SELECT * FROM public.server_owner_submit_reversal('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_events WHERE description = 'zero reversal'), 1);
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000010602', (SELECT id FROM app.financial_events WHERE description = 'zero reversal'), 2) $$, 'posted reversal creates authoritative zero-balance history');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000004'))), 0::numeric, 'valid reversal reduces economic balance to zero');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000004'), 1, 'Zero Type Blocked', 'BANK', 'USD', 'Zero Bank', '****0404') $$, '23514', 'Financial account type and currency are immutable after posted financial history.', 'zero-balance reversed history still blocks account_type change');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000004'), 1, 'Zero Currency Blocked', 'CASH', 'SAR') $$, '23514', 'Financial account type and currency are immutable after posted financial history.', 'zero-balance reversed history still blocks currency_code change');

SELECT * FROM public.server_owner_create_adjustment('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000004'), 'INCREASE', 5, DATE '2026-08-03', 'USD', 'adjust after reversal', NULL, 'adjusted lock', 'adj-106');
SELECT * FROM public.server_owner_submit_adjustment('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_events WHERE description = 'adjusted lock'), 1);
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000010602', (SELECT id FROM app.financial_events WHERE description = 'adjusted lock'), 2) $$, 'approved adjustment fixture remains practical and posted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000010601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000004'), 1, 'Adjusted Type Blocked', 'BANK', 'USD', 'Adjusted Bank', '****0404') $$, '23514', 'Financial account type and currency are immutable after posted financial history.', 'posted adjustment history remains locked');

SELECT throws_ok($$ UPDATE app.financial_accounts SET account_type = 'BANK', bank_name = 'Bypass Bank', masked_account_identifier = '****9999' WHERE account_number = 'FA-000004' $$, '23514', 'Financial account type and currency are immutable after posted financial history.', 'direct table mutation cannot bypass account_type lock after history');
SELECT throws_ok($$ UPDATE app.financial_accounts SET currency_code = 'SAR' WHERE account_number = 'FA-000004' $$, '23514', 'Financial account type and currency are immutable after posted financial history.', 'direct table mutation cannot bypass currency_code lock after history');
SELECT results_eq($$ SELECT currency_code FROM app.ledger_accounts WHERE financial_account_id = (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000004') AND account_kind = 'FINANCIAL_ASSET' $$, $$ VALUES ('USD'::char(3)) $$, 'failed post-history currency update leaves asset ledger currency consistent');

SELECT ok(NOT has_function_privilege('anon', 'app.financial_account_has_posted_history(uuid)', 'EXECUTE'), 'helper is not executable by anon');
SELECT ok(NOT has_function_privilege('authenticated', 'app.financial_account_has_posted_history(uuid)', 'EXECUTE'), 'helper is not executable by authenticated');
SELECT ok(NOT has_function_privilege('service_role', 'app.financial_account_has_posted_history(uuid)', 'EXECUTE'), 'helper is not executable by service_role');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name LIKE '%financial_account%posted%history%' $$, 'no Client/public posted-history RPC introduced');

SELECT * FROM finish();
ROLLBACK;
