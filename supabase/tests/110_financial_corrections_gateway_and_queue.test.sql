BEGIN;
SELECT plan(26);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;
ALTER SEQUENCE app.project_expense_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000011001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner-a.110@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000011002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner-b.110@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000011003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.110@example.test','',now(),'{}','{}',now(),now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000011001','owner-a.110@example.test','Owner A One Ten',decode('1101101101101101101101101101101101101101101101101101101101101101','hex'),'req-110','corr-110');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000011001',true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Correction Gateway Contractor','Correction Gateway Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000011002','00000000-0000-0000-0000-000000011002','owner-b.110@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001')),
  ('10000000-0000-0000-0000-000000011003','00000000-0000-0000-0000-000000011003','client.110@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001')
FROM app.users WHERE id IN ('10000000-0000-0000-0000-000000011002','10000000-0000-0000-0000-000000011003');
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000011002','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'),true),
  ('10000000-0000-0000-0000-000000011003','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000011001'),true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000011001','Client 110','Client 110 LLC','client.110@example.test');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.clients WHERE display_name='Client 110'),'Project 110','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000011001','Main USD 110','BANK','USD','Bank','****1101');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000011001','Second USD 110','CASH','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000011001','SAR 110','CASH','SAR');
SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000011001', DATE '2026-08-17', 'USD', 'SAR', 3.75, 'MANUAL', 'rate');

SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),100,DATE '2026-08-17','USD','posted opening 110',NULL,'ob-110');
SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='posted opening 110'),1);
SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000011002',(SELECT id FROM app.financial_events WHERE description='posted opening 110'),2);
SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),9,DATE '2026-08-17','USD','draft opening 110',NULL,'draft-ob-110');
SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.projects WHERE name='Project 110'),20,'USD',DATE '2026-08-17',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'cp-110');
SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000011001',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='cp-110'),1);
SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000011002',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='cp-110'),2);
SELECT * FROM public.server_owner_create_project_expense('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.projects WHERE name='Project 110'),(SELECT id FROM app.expense_categories WHERE code='OTHER'),5,'USD',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),DATE '2026-08-17','Vendor','pex-110','posted expense 110','notes');
SELECT * FROM public.server_owner_submit_project_expense('00000000-0000-0000-0000-000000011001',(SELECT financial_event_id FROM app.project_expenses WHERE vendor_reference='PEX-110'),1);
SELECT * FROM public.server_owner_approve_project_expense('00000000-0000-0000-0000-000000011002',(SELECT financial_event_id FROM app.project_expenses WHERE vendor_reference='PEX-110'),2);
SELECT * FROM public.server_owner_create_account_transfer('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),(SELECT id FROM app.financial_accounts WHERE account_number='FA-000002'),7,'USD',DATE '2026-08-17','at-110','notes');
SELECT * FROM public.server_owner_submit_account_transfer('00000000-0000-0000-0000-000000011001',(SELECT financial_event_id FROM app.account_transfers WHERE reference='AT-110'),1);
SELECT * FROM public.server_owner_approve_account_transfer('00000000-0000-0000-0000-000000011002',(SELECT financial_event_id FROM app.account_transfers WHERE reference='AT-110'),2);
SELECT * FROM public.server_owner_create_currency_exchange('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),(SELECT id FROM app.financial_accounts WHERE account_number='FA-000003'),11,(SELECT id FROM app.exchange_rates WHERE rate_date=DATE '2026-08-17'),0,NULL,DATE '2026-08-17',NULL,'ce-110');
SELECT * FROM public.server_owner_submit_currency_exchange('00000000-0000-0000-0000-000000011001',(SELECT financial_event_id FROM app.currency_exchanges WHERE reference='CE-110'),1);
SELECT * FROM public.server_owner_approve_currency_exchange('00000000-0000-0000-0000-000000011002',(SELECT financial_event_id FROM app.currency_exchanges WHERE reference='CE-110'),2);

SELECT results_eq($$ SELECT event_type FROM public.server_owner_financial_correction_source_list('00000000-0000-0000-0000-000000011001',50,0) ORDER BY event_type $$,$$ VALUES ('ACCOUNT_TRANSFER'::text),('CLIENT_PAYMENT'::text),('CURRENCY_EXCHANGE'::text),('OPENING_BALANCE'::text),('PROJECT_EXPENSE'::text) $$,'source lookup includes all approved posted source types');
SELECT is_empty($$ SELECT * FROM public.server_owner_financial_correction_source_list('00000000-0000-0000-0000-000000011001',50,0) WHERE event_number=(SELECT event_number FROM app.financial_events WHERE description='draft opening 110') $$,'non-posted source excluded');
SELECT throws_ok($$ SELECT * FROM public.server_owner_financial_correction_source_list('00000000-0000-0000-0000-000000011003',50,0) $$,'42501','Privileged operation denied.','Client cannot read correction sources');
SELECT results_eq($$ SELECT event_type, amount, currency_code FROM public.server_owner_financial_correction_source_list('00000000-0000-0000-0000-000000011001',50,0) WHERE event_type IN ('ACCOUNT_TRANSFER','CURRENCY_EXCHANGE') ORDER BY event_type $$,$$ VALUES ('ACCOUNT_TRANSFER'::text,7::numeric,'USD'::char(3)),('CURRENCY_EXCHANGE'::text,11::numeric,'USD'::char(3)) $$,'source lookup projects subtype amount and currency safely');

SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000011001',(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.event_type='CLIENT_PAYMENT'),DATE '2026-08-17','reject first','rejected reversal 110','rej-rev-110');
SELECT * FROM public.server_owner_submit_reversal('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='rejected reversal 110'),1);
SELECT * FROM public.server_owner_reject_reversal('00000000-0000-0000-0000-000000011002',(SELECT id FROM app.financial_events WHERE description='rejected reversal 110'),2,'not needed');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='rejected reversal 110'),0,'rejected reversal has no posted ledger effect');
SELECT ok((SELECT can_reverse FROM public.server_owner_financial_correction_source_list('00000000-0000-0000-0000-000000011001',50,0) WHERE event_type='CLIENT_PAYMENT'),'rejected reversal does not block later full reversal');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000011001',(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.event_type='CLIENT_PAYMENT'),DATE '2026-08-17','valid reversal','valid reversal 110','valid-rev-110') $$,'valid reversal created after rejected reversal');
SELECT results_eq($$ SELECT ft.status::text, ft.transaction_date, ft.reporting_currency_code FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.event_type='CLIENT_PAYMENT' $$,$$ VALUES ('POSTED'::text,DATE '2026-08-17','USD'::char(3)) $$,'original transaction remains unchanged before reversal approval');
SELECT * FROM public.server_owner_submit_reversal('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='valid reversal 110'),1);
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='valid reversal 110'),2) $$,'42501','Financial reversal requires different Owner approval.','reversal self approval rejected');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000011002','eligible',50,0) WHERE event_type='REVERSAL'),'REVERSAL appears for eligible second Owner');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000011001','created_by_me',50,0) WHERE event_type='REVERSAL'),'REVERSAL appears created-by-me for creator');
SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000011002',(SELECT id FROM app.financial_events WHERE description='valid reversal 110'),2);
SELECT ok(EXISTS (SELECT 1 FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id JOIN app.financial_reversals fr ON fr.financial_event_id=fe.id WHERE fe.description='valid reversal 110' AND ft.status='POSTED' AND ft.reverses_transaction_id=fr.original_transaction_id),'approved reversal posts separate linked history');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='valid reversal 110')),(SELECT count(*)::integer FROM app.ledger_entries WHERE financial_transaction_id=(SELECT original_transaction_id FROM app.financial_reversals fr JOIN app.financial_events fe ON fe.id=fr.financial_event_id WHERE fe.description='valid reversal 110')),'reversal creates compensating ledger history');
SELECT ok(NOT (SELECT can_reverse FROM public.server_owner_financial_correction_source_list('00000000-0000-0000-0000-000000011001',50,0) WHERE event_type='CLIENT_PAYMENT'),'approved full reversal removes source from new reversal eligibility');
SELECT throws_ok($$ SELECT set_config('app.financial_transaction_context','owner_financial_mutation',true); UPDATE app.financial_transactions SET description='mutate posted reversal' WHERE financial_event_id=(SELECT id FROM app.financial_events WHERE description='valid reversal 110') $$,'23514','Terminal financial transactions are immutable.','posted reversal immutable');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_adjustment('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'INCREASE',3,DATE '2026-08-17','USD','delta adjust',(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='posted opening 110'),'adjustment 110','adj-110') $$,'adjustment created against posted source');
SELECT * FROM public.server_owner_submit_adjustment('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='adjustment 110'),1);
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='adjustment 110'),2) $$,'42501','Financial adjustment requires different Owner approval.','adjustment self approval rejected');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000011002','eligible',50,0) WHERE event_type='ADJUSTMENT'),'ADJUSTMENT appears for eligible second Owner');
SELECT * FROM public.server_owner_approve_adjustment('00000000-0000-0000-0000-000000011002',(SELECT id FROM app.financial_events WHERE description='adjustment 110'),2);
SELECT results_eq($$ SELECT fa.direction::text, fa.amount, fa.adjusted_transaction_id IS NOT NULL, ft.status::text FROM app.financial_adjustments fa JOIN app.financial_events fe ON fe.id=fa.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.description='adjustment 110' $$,$$ VALUES ('INCREASE'::text,3::numeric,true,'POSTED'::text) $$,'adjustment delta and lineage preserved in posted correction');
SELECT results_eq($$ SELECT line_no, debit_amount, credit_amount FROM app.ledger_entries WHERE financial_transaction_id=(SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='adjustment 110') ORDER BY line_no $$,$$ VALUES (1,3::numeric,0::numeric),(2,0::numeric,3::numeric) $$,'adjustment posts only the correcting delta');
SELECT results_eq($$ SELECT ft.status::text FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='posted opening 110' $$,$$ VALUES ('POSTED'::text) $$,'adjustment leaves original posted transaction unchanged');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_adjustment('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='adjustment 110'),3,(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'INCREASE',4,DATE '2026-08-17','USD','mutate posted',NULL,'bad') $$,'23514','Financial adjustment cannot be updated.','posted adjustment immutable');

SELECT * FROM public.server_owner_create_adjustment('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'DECREASE',2,DATE '2026-08-17','USD','reject adjustment',NULL,'rejected adjustment 110','adj-rej-110');
SELECT * FROM public.server_owner_submit_adjustment('00000000-0000-0000-0000-000000011001',(SELECT id FROM app.financial_events WHERE description='rejected adjustment 110'),1);
SELECT * FROM public.server_owner_reject_adjustment('00000000-0000-0000-0000-000000011002',(SELECT id FROM app.financial_events WHERE description='rejected adjustment 110'),2,'no');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000011001','recent',50,0) WHERE event_type IN ('OPENING_BALANCE','CLIENT_PAYMENT','PROJECT_EXPENSE','REVERSAL','ADJUSTMENT')),'recent queue includes existing and correction event types safely');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000011001','rejected',50,0) WHERE event_type='ADJUSTMENT'),'rejected queue includes rejected adjustment');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='rejected adjustment 110'),0,'rejected adjustment has no posted ledger effect');
SELECT ok((SELECT bool_and(event_type IN ('OPENING_BALANCE','CLIENT_PAYMENT','PROJECT_EXPENSE','REVERSAL','ADJUSTMENT') AND financial_event_id IS NOT NULL AND financial_transaction_id IS NOT NULL AND related_label IS NOT NULL) FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000011001','recent',50,0)),'queue projects safe routable event types');

SELECT * FROM finish();
ROLLBACK;
