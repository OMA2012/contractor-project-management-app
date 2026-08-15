BEGIN;
SELECT plan(14);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;
ALTER SEQUENCE app.project_expense_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010901','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner-a.109@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010902','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner-b.109@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000010903','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.109@example.test','',now(),'{}','{}',now(),now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010901','owner-a.109@example.test','Owner A One Zero Nine',decode('1091091091091091091091091091091091091091091091091091091091091091','hex'),'req-109','corr-109');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000010901',true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Queue Expansion Contractor','Queue Expansion Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010902','00000000-0000-0000-0000-000000010902','owner-b.109@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901')),
  ('10000000-0000-0000-0000-000000010903','00000000-0000-0000-0000-000000010903','client.109@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901')
FROM app.users WHERE id IN ('10000000-0000-0000-0000-000000010902','10000000-0000-0000-0000-000000010903');
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000010902','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'),true),
  ('10000000-0000-0000-0000-000000010903','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010901'),true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010901','Client 109','Client 109 LLC','client.109@example.test');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010901',(SELECT id FROM app.clients WHERE display_name='Client 109'),'Project 109','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010901','Queue Bank 109','BANK','USD','Bank','****109');

SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000010901',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),10,'2026-08-15','USD','opening queue',NULL,'ob-109');
SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000010901',(SELECT id FROM app.financial_events WHERE event_number='FE-000001'),1);
SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000010901',(SELECT id FROM app.projects WHERE name='Project 109'),20,'USD','2026-08-15',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'cp-109');
SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000010901',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='cp-109'),1);
SELECT * FROM public.server_owner_create_project_expense('00000000-0000-0000-0000-000000010901',(SELECT id FROM app.projects WHERE name='Project 109'),(SELECT id FROM app.expense_categories WHERE code='OTHER'),5,'USD',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'2026-08-15','Vendor','pex-109','expense queue','private notes');
SELECT * FROM public.server_owner_submit_project_expense('00000000-0000-0000-0000-000000010901',(SELECT financial_event_id FROM app.project_expenses WHERE vendor_reference='PEX-109'),1);

SELECT results_eq($$ SELECT event_type FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010902','eligible',50,0) ORDER BY event_type $$,$$ VALUES ('CLIENT_PAYMENT'::text),('OPENING_BALANCE'::text),('PROJECT_EXPENSE'::text) $$,'all three event types appear as eligible for another Owner');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010902','eligible',50,0) WHERE event_type='OPENING_BALANCE'), 'Opening Balance remains in queue');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010902','eligible',50,0) WHERE event_type='CLIENT_PAYMENT'), 'Client Payment now appears');
SELECT ok(EXISTS (SELECT 1 FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010902','eligible',50,0) WHERE event_type='PROJECT_EXPENSE'), 'Project Expense now appears');
SELECT results_eq($$ SELECT bool_and(eligible_for_my_approval), bool_and(NOT created_by_me) FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010902','eligible',50,0) $$,$$ VALUES (true,true) $$,'eligible classification is backend-derived');
SELECT results_eq($$ SELECT event_type, created_by_me, eligible_for_my_approval FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010901','created_by_me',50,0) ORDER BY event_type $$,$$ VALUES ('CLIENT_PAYMENT'::text,true,false),('OPENING_BALANCE'::text,true,false),('PROJECT_EXPENSE'::text,true,false) $$,'creator sees another Owner required section');
SELECT is((SELECT count(*)::integer FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010901','eligible',50,0)),0,'creator self-approval isolation excludes own events');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_project_expense('00000000-0000-0000-0000-000000010901',(SELECT financial_event_id FROM app.project_expenses WHERE vendor_reference='PEX-109'),2) $$,'42501','Project expense requires different Owner approval.','self approval remains rejected');

SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000010902',(SELECT id FROM app.financial_events WHERE event_number='FE-000001'),2);
SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000010902',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='cp-109'),2);
SELECT * FROM public.server_owner_approve_project_expense('00000000-0000-0000-0000-000000010902',(SELECT financial_event_id FROM app.project_expenses WHERE vendor_reference='PEX-109'),2);
SELECT results_eq($$ SELECT event_type, event_status, transaction_status FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010901','recent',50,0) ORDER BY event_type $$,$$ VALUES ('CLIENT_PAYMENT'::text,'APPROVED'::text,'POSTED'::text),('OPENING_BALANCE'::text,'APPROVED'::text,'POSTED'::text),('PROJECT_EXPENSE'::text,'APPROVED'::text,'POSTED'::text) $$,'recent approved/posted includes all three');

SELECT * FROM public.server_owner_create_project_expense('00000000-0000-0000-0000-000000010901',(SELECT id FROM app.projects WHERE name='Project 109'),(SELECT id FROM app.expense_categories WHERE code='OTHER'),7,'USD',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'2026-08-16','Vendor','reject-109','reject expense','hidden');
SELECT * FROM public.server_owner_submit_project_expense('00000000-0000-0000-0000-000000010901',(SELECT financial_event_id FROM app.project_expenses WHERE vendor_reference='REJECT-109'),1);
SELECT * FROM public.server_owner_reject_project_expense('00000000-0000-0000-0000-000000010902',(SELECT financial_event_id FROM app.project_expenses WHERE vendor_reference='REJECT-109'),2,'not valid');
SELECT results_eq($$ SELECT event_type, event_status, transaction_status FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010901','rejected',50,0) WHERE event_type='PROJECT_EXPENSE' $$,$$ VALUES ('PROJECT_EXPENSE'::text,'REJECTED'::text,'REJECTED'::text) $$,'rejected section includes Project Expense');
SELECT throws_ok($$ SELECT * FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010903','eligible',50,0) $$,'42501','Privileged operation denied.','Client has no queue leakage');
SELECT is((SELECT count(*)::integer FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010902','eligible',50,0)),0,'no already-approved or rejected leakage into eligible section');
SELECT ok((SELECT bool_and(event_type IN ('OPENING_BALANCE','CLIENT_PAYMENT','PROJECT_EXPENSE') AND financial_event_id IS NOT NULL AND financial_transaction_id IS NOT NULL AND related_label IS NOT NULL) FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010901','recent',50,0)), 'safe event-type projection returns routable context only');
SELECT is_empty($$ SELECT * FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010901','recent',50,0) WHERE event_type NOT IN ('OPENING_BALANCE','CLIENT_PAYMENT','PROJECT_EXPENSE') $$,'unknown event types are not projected by expansion');

SELECT * FROM finish();
ROLLBACK;
