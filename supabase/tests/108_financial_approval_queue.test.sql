BEGIN;
SELECT plan(10);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010801', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.108@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010802', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.108@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010803', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.108@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010801', 'owner-a.108@example.test', 'Owner A One Zero Eight', decode('1081081081081081081081081081081081081081081081081081081081081081', 'hex'), 'req-108', 'corr-108');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010801', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Queue Contractor', 'Queue Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010801'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010801'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010802','00000000-0000-0000-0000-000000010802','owner-b.108@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801')),
  ('10000000-0000-0000-0000-000000010803','00000000-0000-0000-0000-000000010803','client.108@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801')
FROM app.users WHERE id IN ('10000000-0000-0000-0000-000000010802','10000000-0000-0000-0000-000000010803');
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000010802','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801'),true),
  ('10000000-0000-0000-0000-000000010803','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000010801'),true);

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010801','Queue Cash','CASH','USD');

SELECT has_function('public','server_owner_financial_approval_queue',ARRAY['uuid','text','integer','integer'],'server financial approval queue exists');
SELECT ok(has_function_privilege('service_role','public.server_owner_financial_approval_queue(uuid,text,integer,integer)','EXECUTE'), 'service role can execute queue');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_financial_approval_queue(uuid,text,integer,integer)','EXECUTE'), 'authenticated cannot execute service queue');

SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000010801', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 10, DATE '2026-08-15', 'USD', 'queue submitted', NULL, 'queue-submitted-108');
SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000010801', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 1);

SELECT results_eq($$ SELECT event_number, event_type, amount, currency_code, event_status, transaction_status, created_by_me, eligible_for_my_approval FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010802','eligible',50,0) $$, $$ VALUES ('FE-000001'::text,'OPENING_BALANCE'::text,10::numeric,'USD'::char(3),'SUBMITTED'::text,'SUBMITTED'::text,false,true) $$, 'different Owner sees submitted opening balance as eligible');
SELECT results_eq($$ SELECT event_number, created_by_me, eligible_for_my_approval FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010801','created_by_me',50,0) $$, $$ VALUES ('FE-000001'::text,true,false) $$, 'creator sees another Owner required section');
SELECT is((SELECT count(*)::integer FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010801','eligible',50,0)), 0, 'creator is not eligible for own submitted event');

SELECT * FROM public.server_owner_approve_opening_balance('00000000-0000-0000-0000-000000010802', (SELECT id FROM app.financial_events WHERE event_number='FE-000001'), 2);
SELECT results_eq($$ SELECT event_number, event_status, transaction_status, eligible_for_my_approval FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010801','recent',50,0) WHERE event_number='FE-000001' $$, $$ VALUES ('FE-000001'::text,'APPROVED'::text,'POSTED'::text,false) $$, 'posted opening balance appears in recent section');

SELECT * FROM public.server_owner_create_opening_balance('00000000-0000-0000-0000-000000010801', (SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'), 20, DATE '2026-08-16', 'USD', 'queue rejected', NULL, 'queue-rejected-108');
SELECT * FROM public.server_owner_submit_opening_balance('00000000-0000-0000-0000-000000010801', (SELECT id FROM app.financial_events WHERE event_number='FE-000002'), 1);
SELECT * FROM public.server_owner_reject_opening_balance('00000000-0000-0000-0000-000000010802', (SELECT id FROM app.financial_events WHERE event_number='FE-000002'), 2, 'not valid');
SELECT results_eq($$ SELECT event_number, event_status, transaction_status, rejection_reason FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010801','rejected',50,0) WHERE event_number='FE-000002' $$, $$ VALUES ('FE-000002'::text,'REJECTED'::text,'REJECTED'::text,'not valid'::text) $$, 'rejected opening balance appears in rejected section');
SELECT throws_ok($$ SELECT * FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010803','eligible',50,0) $$, '42501', 'Privileged operation denied.', 'Client denied approval queue');
SELECT throws_ok($$ SELECT * FROM public.server_owner_financial_approval_queue('00000000-0000-0000-0000-000000010801','transfers',50,0) $$, '23514', 'Financial approval queue section is invalid.', 'invalid queue section denied');

SELECT * FROM finish();
ROLLBACK;
