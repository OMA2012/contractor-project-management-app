BEGIN;
SELECT plan(55);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000005901', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.59@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005902', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.59@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005903', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.59@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005904', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.59@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005905', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.59@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000005906', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'site.59@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000005901', 'owner-a.59@example.test', 'Owner A Fifty Nine', decode('5959595959595959595959595959595959595959595959595959595959595959', 'hex'), 'req-59', 'corr-59');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005901', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Posting Contractor', 'Posting Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005901'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000005901'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000005902','00000000-0000-0000-0000-000000005902','owner-b.59@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901')),
  ('10000000-0000-0000-0000-000000005903','00000000-0000-0000-0000-000000005903','client.59@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901')),
  ('10000000-0000-0000-0000-000000005904','00000000-0000-0000-0000-000000005904','accountant.59@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901')),
  ('10000000-0000-0000-0000-000000005905','00000000-0000-0000-0000-000000005905','pm.59@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901')),
  ('10000000-0000-0000-0000-000000005906','00000000-0000-0000-0000-000000005906','site.59@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901')
FROM app.users WHERE id IN ('10000000-0000-0000-0000-000000005902','10000000-0000-0000-0000-000000005903','10000000-0000-0000-0000-000000005904','10000000-0000-0000-0000-000000005905','10000000-0000-0000-0000-000000005906');
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000005902','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),true),
  ('10000000-0000-0000-0000-000000005903','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),true),
  ('10000000-0000-0000-0000-000000005904','accountant',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),true),
  ('10000000-0000-0000-0000-000000005905','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),true),
  ('10000000-0000-0000-0000-000000005906','site_supervisor',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000005901'),true);

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005901','Cash Till','CASH','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005901','YER Bank','BANK','YER','Bank Y','****4321');
SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000005901', DATE '2026-07-29', 'USD', 'YER', 250.000000000000, 'MANUAL', 'do not log this source ref');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 100.25, DATE '2026-07-29', 'USD', 'cash opening', 'raw note', 'open-cash') $$, 'Owner creates draft opening balance atomically');
SELECT results_eq($$ SELECT event_number::text, status::text, version_number FROM app.financial_events $$, $$ VALUES ('FE-000001'::text, 'DRAFT'::text, 1) $$, 'event numbering and draft status');
SELECT results_eq($$ SELECT transaction_number::text, status::text FROM app.financial_transactions $$, $$ VALUES ('FT-000001'::text, 'DRAFT'::text) $$, 'transaction numbering and draft status');
SELECT is((SELECT count(*)::integer FROM app.account_opening_balances), 1, 'opening balance row created');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 100.25, DATE '2026-07-29', 'USD', 'cash opening', NULL, 'open-cash') $$, '23505', 'Duplicate opening balance.', 'non-rejected duplicate fingerprint rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 1, 125.50, DATE '2026-07-29', 'USD', 'cash opening updated', 'new note') $$, 'draft update succeeds');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 1, 130, DATE '2026-07-29', 'USD') $$, '40001', 'Opening balance version conflict.', 'stale update rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 2) $$, 'submit succeeds');
SELECT results_eq($$ SELECT fe.status::text, ft.status::text, fe.version_number FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.event_number='FE-000001' $$, $$ VALUES ('SUBMITTED'::text, 'SUBMITTED'::text, 3) $$, 'submission moves event and transaction');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 3) $$, '42501', 'Opening balance requires different Owner approval.', 'creator self-approval denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000005902', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 3) $$, 'different Owner approves and posts atomically');
SELECT results_eq($$ SELECT fe.status::text, ft.status::text FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.event_number='FE-000001' $$, $$ VALUES ('APPROVED'::text, 'POSTED'::text) $$, 'approval posts transaction');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001')), 2, 'exactly two ledger entries');
SELECT results_eq($$ SELECT line_no, debit_amount, credit_amount, currency_code, reporting_debit_amount, reporting_credit_amount, exchange_rate_id IS NULL FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001') ORDER BY line_no $$, $$ VALUES (1,125.50::numeric,0::numeric,'USD'::char(3),125.50::numeric,0::numeric,true),(2,0::numeric,125.50::numeric,'USD'::char(3),0::numeric,125.50::numeric,true) $$, 'same-currency entries use no exchange-rate row');
SELECT is((SELECT code::text FROM app.ledger_accounts WHERE code='CTRL-OPENING-USD'), 'CTRL-OPENING-USD', 'opening control account created on demand');
SELECT is((SELECT normal_side::text FROM app.ledger_accounts WHERE code='CTRL-OPENING-USD'), 'CREDIT', 'opening control account normal side credit');
SELECT results_eq($$ SELECT currency_code, sum(debit_amount), sum(credit_amount) FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001') GROUP BY currency_code $$, $$ VALUES ('USD'::char(3),125.50::numeric,125.50::numeric) $$, 'entries balance by currency');
SELECT results_eq($$ SELECT reporting_currency_code, sum(reporting_debit_amount), sum(reporting_credit_amount) FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001') GROUP BY reporting_currency_code $$, $$ VALUES ('USD'::char(3),125.50::numeric,125.50::numeric) $$, 'entries balance by reporting currency');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'))), 125.50::numeric, 'single account balance derived from posted ledger entries');
SELECT results_eq($$ SELECT currency_code, balance FROM public.server_owner_cash_totals_by_currency('00000000-0000-0000-0000-000000005901') $$, $$ VALUES ('USD'::char(3),125.50::numeric) $$, 'cash totals grouped by currency');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='opening_balance_approved'), 1, 'approval activity logged once');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='financial_transaction_posted'), 1, 'posting activity logged once');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000005902', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 4) $$, 'idempotent approval retry returns posted result');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001')), 2, 'idempotent retry creates no duplicate ledger entries');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='financial_transaction_posted'), 1, 'idempotent retry creates no duplicate posting log');
SELECT throws_ok($$ UPDATE app.ledger_entries SET debit_amount = 1 WHERE financial_transaction_id=(SELECT id FROM app.financial_transactions WHERE transaction_number='FT-000001') $$, '23514', 'Posted ledger entries are immutable.', 'posted ledger entry update rejected');
SELECT throws_ok($$ DELETE FROM app.financial_events WHERE event_number='FE-000001' $$, '23514', 'Financial events cannot be deleted.', 'approved event delete rejected');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000002'), 1000, DATE '2026-07-29', 'USD', 'yer opening', NULL, 'open-yer') $$, 'multi-currency draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_events WHERE description='yer opening'), 1) $$, 'multi-currency submit');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000005902', (SELECT id FROM app.financial_events WHERE description='yer opening'), 2) $$, 'multi-currency approve uses snapshot');
SELECT results_eq($$ SELECT rate_base_currency_code, rate_quote_currency_code, rate_value, rate_source::text, exchange_rate_id IS NOT NULL FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='yer opening') ORDER BY line_no LIMIT 1 $$, $$ VALUES ('USD'::char(3),'YER'::char(3),250.000000000000::numeric,'MANUAL'::text,true) $$, 'multi-currency snapshot stores explicit rate direction');
SELECT results_eq($$ SELECT reporting_debit_amount, reporting_credit_amount FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='yer opening') ORDER BY line_no $$, $$ VALUES (4::numeric,0::numeric),(0::numeric,4::numeric) $$, 'multi-currency reporting amounts rounded at posting boundary');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000002'))), 1000::numeric, 'multi-currency source balance derived');
SELECT results_eq($$ SELECT currency_code, balance FROM public.server_owner_bank_totals_by_currency('00000000-0000-0000-0000-000000005901') $$, $$ VALUES ('YER'::char(3),1000::numeric) $$, 'bank totals grouped separately');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action='exchange_rate_created' AND (new_values::text LIKE '%do not log%' OR metadata::text LIKE '%do not log%')), 'source reference omitted from logs');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000005901','No Rate Cash','CASH','SAR') $$, 'third financial account created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000003'), 10, DATE '2026-07-29', 'USD', 'missing rate') $$, 'missing-rate opening draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_events WHERE description='missing rate'), 1) $$, 'missing-rate opening submitted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000005902', (SELECT id FROM app.financial_events WHERE description='missing rate'), 2) $$, '23514', 'Transaction-date exchange rate is required.', 'missing transaction-date exchange rate fails safely');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='missing rate')), 0, 'failed posting leaves no partial ledger entries');
SELECT results_eq($$ SELECT ft.status::text FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='missing rate' $$, $$ VALUES ('SUBMITTED'::text) $$, 'failed posting leaves transaction submitted');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000003'), 11, DATE '2026-07-30', 'SAR', 'reject me', NULL, 'reject-me') $$, 'reject-path opening draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_events WHERE description='reject me'), 1) $$, 'reject-path opening submitted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reject_opening_balance('00000000-0000-0000-0000-000000005902', (SELECT id FROM app.financial_events WHERE description='reject me'), 2, '') $$, '23514', 'Rejection reason is required.', 'blank rejection reason rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reject_opening_balance('00000000-0000-0000-0000-000000005902', (SELECT id FROM app.financial_events WHERE description='reject me'), 2, 'not valid') $$, 'submitted opening balance rejected');
SELECT results_eq($$ SELECT fe.status::text, ft.status::text FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.description='reject me' $$, $$ VALUES ('REJECTED'::text,'REJECTED'::text) $$, 'rejection updates event and transaction');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='reject me')), 0, 'rejection creates no ledger entries');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000005901', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000003'), 11, DATE '2026-07-30', 'SAR', 'after rejection', NULL, 'reject-me') $$, 'rejected fingerprint may be reused');

SELECT throws_ok($$ SELECT * FROM public.server_owner_opening_balance_list('00000000-0000-0000-0000-000000005903', 50, 0) $$, '42501', 'Privileged operation denied.', 'Client denied opening balance list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_opening_balance_list('00000000-0000-0000-0000-000000005904', 50, 0) $$, '42501', 'Privileged operation denied.', 'Accountant denied opening balance list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_opening_balance_list('00000000-0000-0000-0000-000000005905', 50, 0) $$, '42501', 'Privileged operation denied.', 'Project Manager denied opening balance list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_opening_balance_list('00000000-0000-0000-0000-000000005906', 50, 0) $$, '42501', 'Privileged operation denied.', 'Site Supervisor denied opening balance list');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payments','expenses','transfers','refunds','reversals','adjustments','account_balances')), 'excluded workflow tables remain absent except approved later packages');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_event%', 'current_account not changed');
SELECT is((SELECT count(*)::integer FROM app.financial_transactions WHERE reverses_transaction_id IS NOT NULL), 0, 'no reversal workflow rows created');

SELECT * FROM finish();
ROLLBACK;
