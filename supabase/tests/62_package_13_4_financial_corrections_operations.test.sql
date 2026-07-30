BEGIN;
SELECT plan(60);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000006201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.62@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006202', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.62@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006203', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.62@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006204', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.62@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006205', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.62@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006206', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'site.62@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000006201', 'owner-a.62@example.test', 'Owner A Sixty Two', decode('6262626262626262626262626262626262626262626262626262626262626262', 'hex'), 'req-62', 'corr-62');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006201', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Correction Contractor', 'Correction Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000006202','00000000-0000-0000-0000-000000006202','owner-b.62@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201')),
  ('10000000-0000-0000-0000-000000006203','00000000-0000-0000-0000-000000006203','client.62@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201')),
  ('10000000-0000-0000-0000-000000006204','00000000-0000-0000-0000-000000006204','accountant.62@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201')),
  ('10000000-0000-0000-0000-000000006205','00000000-0000-0000-0000-000000006205','pm.62@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201')),
  ('10000000-0000-0000-0000-000000006206','00000000-0000-0000-0000-000000006206','site.62@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201')
FROM app.users WHERE id IN ('10000000-0000-0000-0000-000000006202','10000000-0000-0000-0000-000000006203','10000000-0000-0000-0000-000000006204','10000000-0000-0000-0000-000000006205','10000000-0000-0000-0000-000000006206');
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000006202','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),true),
  ('10000000-0000-0000-0000-000000006203','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),true),
  ('10000000-0000-0000-0000-000000006204','accountant',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),true),
  ('10000000-0000-0000-0000-000000006205','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),true),
  ('10000000-0000-0000-0000-000000006206','site_supervisor',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006201'),true);

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000006201','Correction Cash','CASH','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000006201','Correction Riyal','CASH','SAR');
SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000006201', DATE '2026-07-29', 'USD', 'SAR', 3.750000000000, 'MANUAL', 'hidden source ref');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 100, DATE '2026-07-29', 'USD', 'opening', NULL, 'open-62') $$, 'opening balance draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 1) $$, 'opening balance submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 2) $$, 'opening balance approved');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000006201',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'))), 100::numeric, 'opening balance affects posted balance');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001'), DATE '2026-07-29', 'reverse opening', 'reverse opening', 'rev-open') $$, 'reversal draft of opening-balance transaction created');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000002'), DATE '2026-07-29', 'self impossible') $$, '23514', 'Invalid financial reversal.', 'reversal of non-posted correction draft denied');
SELECT throws_ok($$ SELECT set_config('app.financial_transaction_context','owner_financial_mutation',true); UPDATE app.financial_reversals SET original_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000002') WHERE financial_event_id=(SELECT id FROM app.financial_events WHERE event_number='FE-000002') $$, '23514', 'Financial reversal identity fields are immutable.', 'self-reference and protected identity update denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_reversal('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE event_number='FE-000002'), 1) $$, 'reversal submitted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE event_number='FE-000002'), 2) $$, '42501', 'Financial reversal requires different Owner approval.', 'reversal self approval denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE event_number='FE-000002'), 2) $$, 'different Owner approves reversal atomically');
SELECT results_eq($$ SELECT fe.status::text, ft.status::text, ft.reverses_transaction_id = (SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001') FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.event_number='FE-000002' $$, $$ VALUES ('APPROVED'::text,'POSTED'::text,true) $$, 'reversal approved and transaction posted with reverse link');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000002')), 2, 'reversal has copied ledger line count');
SELECT results_eq($$ SELECT line_no, debit_amount, credit_amount, reporting_debit_amount, reporting_credit_amount FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000002') ORDER BY line_no $$, $$ VALUES (1,0::numeric,100::numeric,0::numeric,100::numeric),(2,100::numeric,0::numeric,100::numeric,0::numeric) $$, 'reversal has exact opposite source and reporting totals');
SELECT results_eq($$ SELECT transaction_number::text, status::text FROM app.financial_transactions WHERE transaction_number='FT-000001' $$, $$ VALUES ('FT-000001'::text,'POSTED'::text) $$, 'original transaction remains unchanged');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001')), 2, 'original ledger history remains unchanged');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000006201',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'))), 0::numeric, 'posted reversal cancels account balance');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE event_number='FE-000002'), 3) $$, 'idempotent reversal approval retry returns existing result');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000002')), 2, 'idempotent reversal retry creates no duplicate entries');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001'), DATE '2026-07-29', 'repeat reversal') $$, '23505', 'Duplicate financial reversal.', 'repeated full reversal of same target denied');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000002'), DATE '2026-07-29', 'reverse reversal', 'reverse reversal', 'rev-reversal') $$, 'reversal of previous reversal transaction created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_reversal('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='reverse reversal'), 1) $$, 'reversal of reversal submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE description='reverse reversal'), 2) $$, 'reversal of reversal approved');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000006201',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'))), 100::numeric, 'reversal of reversal restores posted balance');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 'INCREASE', 25, DATE '2026-07-29', 'USD', 'increase reason', (SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='reverse reversal'), 'increase', 'adj-inc') $$, 'adjustment linked to previous reversal created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='increase'), 1, (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 'INCREASE', 25, DATE '2026-07-29', 'USD', 'increase reason updated', (SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='reverse reversal'), 'increase updated') $$, 'draft adjustment optimistic update succeeds');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='increase updated'), 1, (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 'INCREASE', 25, DATE '2026-07-29', 'USD', 'stale', NULL) $$, '40001', 'Financial adjustment version conflict.', 'stale adjustment update denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='increase updated'), 2) $$, 'adjustment submitted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='increase updated'), 3) $$, '42501', 'Financial adjustment requires different Owner approval.', 'adjustment self approval denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE description='increase updated'), 3) $$, 'adjustment increase approved');
SELECT results_eq($$ SELECT line_no, debit_amount, credit_amount FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='increase updated') ORDER BY line_no $$, $$ VALUES (1,25::numeric,0::numeric),(2,0::numeric,25::numeric) $$, 'increase debits asset and credits control');
SELECT is((SELECT code::text FROM app.ledger_accounts WHERE code='CTRL-ADJUSTMENT-USD'), 'CTRL-ADJUSTMENT-USD', 'adjustment control account deterministic code created');
SELECT is((SELECT name::text FROM app.ledger_accounts WHERE code='CTRL-ADJUSTMENT-USD'), 'Adjustment Control - USD', 'adjustment control account deterministic name created');
SELECT is((SELECT normal_side::text FROM app.ledger_accounts WHERE code='CTRL-ADJUSTMENT-USD'), 'CREDIT', 'adjustment control normal side credit');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE description='increase updated'), 4) $$, 'idempotent adjustment approval retry returns existing result');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='increase updated')), 2, 'idempotent adjustment retry creates no duplicate entries');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000006201',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'))), 125::numeric, 'increase affects posted balance');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 'DECREASE', 5, DATE '2026-07-29', 'USD', 'decrease reason', (SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='increase updated'), 'decrease', 'adj-dec') $$, 'adjustment linked to previous adjustment created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='decrease'), 1) $$, 'decrease adjustment submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE description='decrease'), 2) $$, 'decrease adjustment approved');
SELECT results_eq($$ SELECT line_no, debit_amount, credit_amount FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='decrease') ORDER BY line_no $$, $$ VALUES (1,5::numeric,0::numeric),(2,0::numeric,5::numeric) $$, 'decrease debits control and credits asset');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000006201',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'))), 120::numeric, 'decrease affects posted balance');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 'INCREASE', 2, DATE '2026-07-29', 'USD', 'null link reason', NULL, 'null link', 'adj-null') $$, 'adjustment with null adjusted transaction link created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='null link'), 1) $$, 'null-link adjustment submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reject_adjustment('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE description='null link'), 2, 'not needed') $$, 'submitted adjustment rejected');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='null link')), 0, 'rejection creates no ledger effect');

SELECT throws_ok($$ SELECT set_config('app.financial_transaction_context','owner_financial_mutation',true); UPDATE app.financial_adjustments SET currency_code='SAR' WHERE financial_event_id=(SELECT id FROM app.financial_events WHERE description='null link') $$, '23514', 'Adjustment currency must match account currency.', 'account and adjustment currency mismatch denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000002'), 10, DATE '2026-07-29', 'USD', 'sar opening', NULL, 'open-sar-62') $$, 'SAR opening draft created for exchange snapshot');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='sar opening'), 1) $$, 'SAR opening submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE description='sar opening'), 2) $$, 'SAR opening approved with rate');
SELECT results_eq($$ SELECT rate_base_currency_code, rate_quote_currency_code, rate_value, exchange_rate_id IS NOT NULL FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='sar opening') ORDER BY line_no LIMIT 1 $$, $$ VALUES ('USD'::char(3),'SAR'::char(3),3.750000000000::numeric,true) $$, 'transaction-date exchange-rate snapshot preserved');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000002'), 'INCREASE', 1, DATE '2026-07-30', 'USD', 'missing rate', NULL, 'missing rate adjustment', 'adj-missing-rate') $$, 'missing-rate adjustment draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_adjustment('00000000-0000-0000-0000-000000006201', (SELECT id FROM app.financial_events WHERE description='missing rate adjustment'), 1) $$, 'missing-rate adjustment submitted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000006202', (SELECT id FROM app.financial_events WHERE description='missing rate adjustment'), 2) $$, '23514', 'Transaction-date exchange rate is required.', 'approval rolls back safely when transaction-date rate is missing');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='missing rate adjustment')), 0, 'failed adjustment approval leaves no partial entries');

SELECT throws_ok($$ SELECT * FROM public.server_owner_reversal_list('00000000-0000-0000-0000-000000006203',50,0) $$, '42501', 'Privileged operation denied.', 'Client denied reversal list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_adjustment_list('00000000-0000-0000-0000-000000006204',50,0) $$, '42501', 'Privileged operation denied.', 'Accountant denied adjustment list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_adjustment_list('00000000-0000-0000-0000-000000006205',50,0) $$, '42501', 'Privileged operation denied.', 'Project Manager denied adjustment list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_adjustment_list('00000000-0000-0000-0000-000000006206',50,0) $$, '42501', 'Privileged operation denied.', 'Site Supervisor denied adjustment list');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payments','expenses','project_expenses','transfers','account_transfers','currency_exchanges','refunds','account_balances')), 'excluded workflows remain absent except Package 14.2 payment requests and Package 14.3 payment matches');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_adjustment%', 'current_account not changed');

SELECT * FROM finish();
ROLLBACK;
