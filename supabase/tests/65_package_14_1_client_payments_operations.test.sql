BEGIN;
SELECT plan(53);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000006501', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.65@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006502', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.65@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006503', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-a.65@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006504', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-b.65@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006505', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.65@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006506', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.65@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006507', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'site.65@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000006501', 'owner-a.65@example.test', 'Owner A Sixty Five', decode('6565656565656565656565656565656565656565656565656565656565656565', 'hex'), 'req-65', 'corr-65');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006501', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Client Payment Contractor', 'Client Payment Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000006502','00000000-0000-0000-0000-000000006502','owner-b.65@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501')),
  ('10000000-0000-0000-0000-000000006503','00000000-0000-0000-0000-000000006503','client-a.65@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501')),
  ('10000000-0000-0000-0000-000000006504','00000000-0000-0000-0000-000000006504','client-b.65@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501')),
  ('10000000-0000-0000-0000-000000006505','00000000-0000-0000-0000-000000006505','accountant.65@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501')),
  ('10000000-0000-0000-0000-000000006506','00000000-0000-0000-0000-000000006506','pm.65@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501')),
  ('10000000-0000-0000-0000-000000006507','00000000-0000-0000-0000-000000006507','site.65@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by) SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501') FROM app.users WHERE id BETWEEN '10000000-0000-0000-0000-000000006502' AND '10000000-0000-0000-0000-000000006507';
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000006502','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),true),
  ('10000000-0000-0000-0000-000000006503','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),true),
  ('10000000-0000-0000-0000-000000006504','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),true),
  ('10000000-0000-0000-0000-000000006505','accountant',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),true),
  ('10000000-0000-0000-0000-000000006506','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),true),
  ('10000000-0000-0000-0000-000000006507','site_supervisor',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006501'),true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000006501','Client A','Client A LLC','client-a.65@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000006501','Client B','Client B LLC','client-b.65@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.clients WHERE display_name='Client A'),'10000000-0000-0000-0000-000000006503',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.clients WHERE display_name='Client B'),'10000000-0000-0000-0000-000000006504',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.clients WHERE display_name='Client A'),'Project A','USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.clients WHERE display_name='Client B'),'Project B','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000006501','USD Bank','BANK','USD','Bank','****1000');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000006501','SAR Bank','BANK','SAR','Bank','****2000');
SELECT * FROM public.server_owner_create_exchange_rate('00000000-0000-0000-0000-000000006501', DATE '2026-07-30', 'USD', 'SAR', 4.000000000000, 'MANUAL', 'private ref');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project A'),100,'USD',DATE '2026-07-30',NULL,' ref-001 ','payer secret','private note') $$, 'Owner creates payment draft without receiving account');
SELECT results_eq($$ SELECT fe.status::text, ft.status::text, cp.is_client_submitted, cp.received_account_id IS NULL FROM app.client_payments cp JOIN app.financial_events fe ON fe.id=cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE cp.payment_reference='ref-001' $$, $$ VALUES ('DRAFT'::text,'DRAFT'::text,false,true) $$, 'Owner draft starts draft and account may be null');
SELECT throws_ok($$ SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='ref-001'),1) $$, '23514', 'Invalid receiving account.', 'Owner submit requires receiving account');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='ref-001'),1,125,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'REF-001','payer changed','note changed') $$, 'Owner updates draft facts');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='REF-001'),1,126,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001')) $$, '40001', 'Client payment version conflict.', 'stale draft update rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='REF-001'),2) $$, 'Owner submits payment');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries), 0, 'submission creates no ledger entries');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='REF-001'),3) $$, '42501', 'Client payment requires different Owner approval.', 'creator self approval denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000006502',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='REF-001'),3) $$, 'different Owner approves payment');
SELECT results_eq($$ SELECT fe.status::text, ft.status::text FROM app.client_payments cp JOIN app.financial_events fe ON fe.id=cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE cp.payment_reference='REF-001' $$, $$ VALUES ('APPROVED'::text,'POSTED'::text) $$, 'approval posts');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.event_type='CLIENT_PAYMENT'), 2, 'exactly two client payment ledger lines');
SELECT results_eq($$ SELECT le.line_no, le.debit_amount, le.credit_amount, le.currency_code, le.reporting_debit_amount, le.reporting_credit_amount, le.project_id IS NOT NULL, le.client_id IS NOT NULL FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.event_type='CLIENT_PAYMENT' ORDER BY le.line_no $$, $$ VALUES (1,125::numeric,0::numeric,'USD'::char(3),125::numeric,0::numeric,true,true),(2,0::numeric,125::numeric,'USD'::char(3),0::numeric,125::numeric,true,true) $$, 'same-currency client payment lines are balanced');
SELECT is((SELECT normal_side::text FROM app.ledger_accounts WHERE code='CTRL-CLIENT-PAYMENT-USD'), 'CREDIT', 'client payment control account has credit normal side');
SELECT is((SELECT total_received FROM public.server_owner_project_client_payment_totals('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project A')) WHERE currency_code='USD'), 125::numeric, 'posted Project payment totals are ledger-derived');
SELECT is((SELECT balance FROM public.server_owner_financial_account_balance('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'))), 125::numeric, 'posted account balance includes client payment');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000006502',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='REF-001'),4) $$, 'approval retry is idempotent');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='client_payment_transaction_posted'), 1, 'idempotent retry does not duplicate posting log');
SELECT throws_ok($$ UPDATE app.client_payments SET notes='mutate' WHERE payment_reference='REF-001' $$, '23514', 'Client payments require trusted functions.', 'direct payment update denied');
SELECT throws_ok($$ DELETE FROM app.client_payments WHERE payment_reference='REF-001' $$, '23514', 'Client payments cannot be deleted.', 'payment delete denied');

SELECT throws_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project A'),125,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),' ref-001 ') $$, '23505', 'Duplicate client payment.', 'normalized duplicate reference rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project B'),125,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),' ref-001 ') $$, 'same reference allowed for different Project');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006503', true);
SELECT lives_ok($$ SELECT * FROM public.current_client_submit_payment((SELECT id FROM app.projects WHERE name='Project A'),50,'USD',DATE '2026-07-30','client-ref','payer hidden') $$, 'Client submits own Project payment directly as submitted');
SELECT results_eq($$ SELECT fe.status::text, ft.status::text, cp.is_client_submitted, cp.submitted_by_client_user_id FROM app.client_payments cp JOIN app.financial_events fe ON fe.id=cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE cp.payment_reference='client-ref' $$, $$ VALUES ('SUBMITTED'::text,'SUBMITTED'::text,true,'10000000-0000-0000-0000-000000006503'::uuid) $$, 'Client submission identity and status are correct');
SELECT throws_ok($$ SELECT * FROM public.current_client_submit_payment((SELECT id FROM app.projects WHERE name='Project B'),10,'USD',DATE '2026-07-30','cross') $$, '23514', 'Invalid client payment.', 'Client cannot submit for another Client Project');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006501', true);
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='client-ref'),1,60,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'changed') $$, '23514', 'Client payment cannot be updated.', 'Owner cannot mutate Client-submitted facts');
SELECT lives_ok($$ SELECT * FROM public.server_owner_verify_client_submitted_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='client-ref'),1,(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'verified note') $$, 'Owner verifies Client submission account and notes only');
SELECT throws_ok($$ SELECT * FROM public.server_owner_verify_client_submitted_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='client-ref'),2,(SELECT id FROM app.financial_accounts WHERE account_number='FA-000002')) $$, '23514', 'Invalid receiving account.', 'verification rejects wrong currency receiving account');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000006502',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='client-ref'),2) $$, 'different Owner approves Client submission');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006503', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_approved_payment_list(50,0)), 2, 'Client sees own approved posted payments only');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.current_client_approved_payment_detail((SELECT id FROM app.client_payments WHERE payment_reference='ref-001')) WHERE payment_reference IS NULL), 'Client detail returns safe approved payment fields');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006504', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_approved_payment_list(50,0)), 0, 'cross-Client approved reads denied safely');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006501', true);
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project A'),400,'SAR',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000002'),'sar-ref') $$, 'multi-currency client payment draft');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='sar-ref'),1) $$, 'multi-currency client payment submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000006502',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='sar-ref'),2) $$, 'multi-currency client payment approved');
SELECT results_eq($$ SELECT rate_base_currency_code, rate_quote_currency_code, rate_value, rate_source::text, exchange_rate_id IS NOT NULL, reporting_debit_amount, reporting_credit_amount FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id JOIN app.financial_events fe ON fe.id=ft.financial_event_id JOIN app.client_payments cp ON cp.financial_event_id=fe.id WHERE cp.payment_reference='sar-ref' ORDER BY line_no $$, $$ VALUES ('USD'::char(3),'SAR'::char(3),4.000000000000::numeric,'MANUAL'::text,true,100::numeric,0::numeric),('USD'::char(3),'SAR'::char(3),4.000000000000::numeric,'MANUAL'::text,true,0::numeric,100::numeric) $$, 'multi-currency snapshot is preserved on both lines');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project A'),10,'SAR',DATE '2026-07-31',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000002'),'missing-rate') $$, 'missing-rate draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='missing-rate'),1) $$, 'missing-rate submitted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000006502',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='missing-rate'),2) $$, '23514', 'Transaction-date exchange rate is required.', 'missing transaction-date rate rolls back');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id JOIN app.client_payments cp ON cp.financial_event_id=ft.financial_event_id WHERE cp.payment_reference='missing-rate'), 0, 'failed posting leaves no ledger rows');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project A'),77,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'reject-ref') $$, 'reject draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000006501',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='reject-ref'),1) $$, 'reject draft submitted');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reject_client_payment('00000000-0000-0000-0000-000000006502',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='reject-ref'),2,'') $$, '23514', 'Rejection reason is required.', 'blank rejection rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reject_client_payment('00000000-0000-0000-0000-000000006502',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='reject-ref'),2,'bad facts') $$, 'reject submitted payment');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000006501',(SELECT id FROM app.projects WHERE name='Project A'),77,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'reject-ref') $$, 'rejected fingerprint can be reused');

SELECT throws_ok($$ SELECT * FROM public.server_owner_client_payment_list('00000000-0000-0000-0000-000000006503',50,0) $$, '42501', 'Privileged operation denied.', 'Client denied Owner list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_client_payment_list('00000000-0000-0000-0000-000000006505',50,0) $$, '42501', 'Privileged operation denied.', 'Accountant denied Owner list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_client_payment_list('00000000-0000-0000-0000-000000006506',50,0) $$, '42501', 'Privileged operation denied.', 'Project Manager denied Owner list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_client_payment_list('00000000-0000-0000-0000-000000006507',50,0) $$, '42501', 'Privileged operation denied.', 'Site Supervisor denied Owner list');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('currency_exchanges','refunds','payment_uploads','payment_evidence')), 'excluded workflow tables remain absent except approved request, matching, expense and account transfer packages');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.notifications WHERE notification_type ILIKE '%payment%'), 'payment notifications are absent');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.document_links WHERE client_payment_id IS NOT NULL), 'document payment links remain inactive');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action LIKE 'client_payment_%' AND (previous_values::text ILIKE '%private note%' OR new_values::text ILIKE '%payer secret%' OR metadata::text ILIKE '%private ref%')), 'sensitive payment details omitted from activity logs');
SELECT is_empty($$ SELECT table_name FROM information_schema.tables WHERE table_schema='app' AND table_name='account_balances' $$, 'no editable or cached account balances');

SELECT * FROM finish();
ROLLBACK;
