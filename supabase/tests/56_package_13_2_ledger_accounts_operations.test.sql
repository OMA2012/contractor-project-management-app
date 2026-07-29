BEGIN;
SELECT plan(42);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000005601', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.56@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005602', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.56@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005603', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.56@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005604', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.56@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005605', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'site.56@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000005601', 'owner.56@example.test', 'Owner Fifty Six', decode('5656565656565656565656565656565656565656565656565656565656565656', 'hex'), 'req-56', 'corr-56');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005601', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Ledger Contractor', 'Ledger Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000005602', '00000000-0000-0000-0000-000000005602', 'client.56@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601')),
  ('10000000-0000-0000-0000-000000005603', '00000000-0000-0000-0000-000000005603', 'accountant.56@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601')),
  ('10000000-0000-0000-0000-000000005604', '00000000-0000-0000-0000-000000005604', 'pm.56@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601')),
  ('10000000-0000-0000-0000-000000005605', '00000000-0000-0000-0000-000000005605', 'site.56@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601')
FROM app.users
WHERE auth_subject IN (
  '00000000-0000-0000-0000-000000005602',
  '00000000-0000-0000-0000-000000005603',
  '00000000-0000-0000-0000-000000005604',
  '00000000-0000-0000-0000-000000005605'
);

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000005602', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), true),
  ('10000000-0000-0000-0000-000000005603', 'accountant', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), true),
  ('10000000-0000-0000-0000-000000005604', 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), true),
  ('10000000-0000-0000-0000-000000005605', 'site_supervisor', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005601'), true);

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005601', 'Operating Cash', 'CASH', 'USD') $$, 'Owner create financial account triggers asset ledger');
SELECT results_eq($$ SELECT account_number::text FROM app.financial_accounts $$, $$ VALUES ('FA-000001'::text) $$, 'financial account sequence remains global six digits');
SELECT results_eq($$ SELECT code::text, name::text, account_kind::text, currency_code, normal_side::text, is_system, is_active FROM app.ledger_accounts $$, $$ VALUES ('ASSET-FA-000001'::text, 'Operating Cash'::text, 'FINANCIAL_ASSET'::text, 'USD'::char(3), 'DEBIT'::text, true, true) $$, 'asset ledger account uses deterministic code and copied metadata');
SELECT is((SELECT count(*)::integer FROM app.ledger_accounts WHERE financial_account_id = (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001')), 1, 'one asset ledger account per financial account');
SELECT lives_ok($$ SELECT * FROM app.ensure_financial_asset_ledger_account((SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001')) $$, 'trusted sync helper is idempotent');
SELECT is((SELECT count(*)::integer FROM app.ledger_accounts WHERE code = 'ASSET-FA-000001'), 1, 'idempotent sync does not duplicate ledger account');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account('00000000-0000-0000-0000-000000005601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 1, 'Updated Cash', 'CASH', 'SAR') $$, 'financial account update synchronizes asset ledger');
SELECT results_eq($$ SELECT code::text, name::text, currency_code FROM app.ledger_accounts WHERE code = 'ASSET-FA-000001' $$, $$ VALUES ('ASSET-FA-000001'::text, 'Updated Cash'::text, 'SAR'::char(3)) $$, 'ledger code preserved while name and currency synchronize');
SELECT lives_ok($$ SELECT * FROM public.server_owner_deactivate_financial_account('00000000-0000-0000-0000-000000005601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 2) $$, 'deactivate synchronizes asset ledger');
SELECT is((SELECT is_active FROM app.ledger_accounts WHERE code = 'ASSET-FA-000001'), false, 'ledger inactive after financial account deactivation');
SELECT lives_ok($$ SELECT * FROM public.server_owner_activate_financial_account('00000000-0000-0000-0000-000000005601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 3) $$, 'activate synchronizes asset ledger');
SELECT is((SELECT is_active FROM app.ledger_accounts WHERE code = 'ASSET-FA-000001'), true, 'ledger active after financial account activation');
SELECT lives_ok($$ SELECT * FROM public.server_owner_archive_financial_account('00000000-0000-0000-0000-000000005601', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 4) $$, 'archive synchronizes asset ledger');
SELECT is((SELECT is_active FROM app.ledger_accounts WHERE code = 'ASSET-FA-000001'), false, 'ledger inactive after archive');
SELECT throws_ok($$ UPDATE app.ledger_accounts SET code = 'ASSET-FA-999999' WHERE code = 'ASSET-FA-000001' $$, '23514', 'Ledger accounts are system-managed.', 'manual ledger update denied');
SELECT throws_ok($$ DELETE FROM app.ledger_accounts WHERE code = 'ASSET-FA-000001' $$, '23514', 'Ledger accounts cannot be deleted.', 'ledger delete prevented');
SELECT is_empty($$ SELECT id FROM app.ledger_accounts WHERE account_kind = 'CONTROL' $$, 'CONTROL accounts are not seeded');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005601', DATE '2026-07-26', 'USD', 'SAR', 3.750000000000, 'MANUAL', 'desk ticket 123') $$, 'Owner can create manual exchange rate');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005601', DATE '2026-07-28', 'USD', 'SAR', 3.760000000000, 'MANUAL', 'correction row') $$, 'different rate value for same pair/date/source is valid');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005601', DATE '2026-07-29', 'USD', 'SAR', 3.750000000000, 'BANK_QUOTE', 'bank quote') $$, 'different source for same pair/date/rate is valid');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005601', DATE '2026-07-26', 'USD', 'SAR', 3.750000000000, 'MANUAL', 'duplicate') $$, '23505', 'Duplicate exchange rate.', 'exact duplicate exchange rate fails safely');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005601', DATE '2026-07-28', 'USD', 'USD', 1.000000000000, 'MANUAL') $$, '23514', 'Invalid exchange rate.', 'same-currency rate rejected');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005601', DATE '2026-07-28', 'USD', 'SAR', 0, 'MANUAL') $$, '23514', 'Invalid exchange rate.', 'zero rate rejected');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005601', DATE '2026-07-28', 'USD', 'SAR', 3.750000000000, '') $$, '23514', 'Invalid exchange rate.', 'blank source rejected');
SELECT results_eq($$ SELECT rate_value, source FROM public.server_owner_exchange_rate_list('00000000-0000-0000-0000-000000005601', 'USD', 'SAR', 2, 0) $$, $$ VALUES (3.750000000000::numeric, 'BANK_QUOTE'::text), (3.760000000000::numeric, 'MANUAL'::text) $$, 'rate list uses deterministic ordering and bounded pagination');
SELECT results_eq($$ SELECT source_reference FROM public.server_owner_exchange_rate_detail('00000000-0000-0000-0000-000000005601', (SELECT id FROM app.exchange_rates WHERE source = 'BANK_QUOTE')) $$, $$ VALUES ('bank quote'::text) $$, 'Owner detail can retrieve source reference');
SELECT throws_ok($$ UPDATE app.exchange_rates SET rate_value = 4 WHERE source = 'BANK_QUOTE' $$, '23514', 'Exchange rates are append-only.', 'exchange rates are append-only');
SELECT throws_ok($$ DELETE FROM app.exchange_rates WHERE source = 'BANK_QUOTE' $$, '23514', 'Exchange rates cannot be deleted.', 'exchange rate delete prevented');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'exchange_rate_created'), 3, 'exchange rate create activity logged');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'exchange_rate_created' AND (new_values::text LIKE '%desk ticket%' OR metadata::text LIKE '%desk ticket%' OR new_values::text LIKE '%bank quote%' OR metadata::text LIKE '%bank quote%')), 'exchange rate activity logs omit source reference');

SELECT is(app.convert_amount_with_exchange_rate(10, 'USD', 'USD', 'USD', 'SAR', 3.75), 10::numeric, 'same currency conversion returns amount');
SELECT is(app.convert_amount_with_exchange_rate(10, 'USD', 'SAR', 'USD', 'SAR', 3.75), 37.5::numeric, 'base to quote conversion multiplies');
SELECT is(app.convert_amount_with_exchange_rate(37.5, 'SAR', 'USD', 'USD', 'SAR', 3.75), 10::numeric, 'quote to base conversion divides');
SELECT throws_ok($$ SELECT app.convert_amount_with_exchange_rate(10, 'USD', 'YER', 'USD', 'SAR', 3.75) $$, '23514', 'Exchange rate does not match conversion currencies.', 'unrelated conversion rejected');
SELECT throws_ok($$ SELECT app.convert_amount_with_exchange_rate(-1, 'USD', 'SAR', 'USD', 'SAR', 3.75) $$, '23514', 'Amount cannot be negative.', 'negative amount rejected');
SELECT throws_ok($$ SELECT app.convert_amount_with_exchange_rate(1, 'USD', 'SAR', 'USD', 'SAR', 0) $$, '23514', 'Exchange rate must be greater than zero.', 'non-positive rate rejected');

SELECT throws_ok($$ SELECT * FROM public.server_owner_exchange_rate_list('00000000-0000-0000-0000-000000005602', NULL, NULL, 50, 0) $$, '42501', 'Privileged operation denied.', 'Client cannot list exchange rates');
SELECT throws_ok($$ SELECT * FROM public.server_owner_exchange_rate_list('00000000-0000-0000-0000-000000005603', NULL, NULL, 50, 0) $$, '42501', 'Privileged operation denied.', 'Accountant cannot list exchange rates');
SELECT throws_ok($$ SELECT * FROM public.server_owner_exchange_rate_list('00000000-0000-0000-0000-000000005604', NULL, NULL, 50, 0) $$, '42501', 'Privileged operation denied.', 'Project Manager cannot list exchange rates');
SELECT throws_ok($$ SELECT * FROM public.server_owner_exchange_rate_list('00000000-0000-0000-0000-000000005605', NULL, NULL, 50, 0) $$, '42501', 'Privileged operation denied.', 'Site Supervisor cannot list exchange rates');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('account_balances','payments','expenses','transfers','currency_exchanges','refunds','reversals','adjustments')), 'excluded finance workflow tables remain absent');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%ledger_account%' AND (SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%exchange_rate%', 'current_account not changed');

SELECT * FROM finish();
ROLLBACK;
