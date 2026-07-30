BEGIN;
SELECT plan(56);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_event_number_seq RESTART WITH 1;
ALTER SEQUENCE app.financial_transaction_number_seq RESTART WITH 1;
ALTER SEQUENCE app.payment_request_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000007101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.71@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000007102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.71@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000007103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-a.71@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000007104', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-b.71@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000007105', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.71@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000007106', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.71@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000007107', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'site.71@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000007101', 'owner-a.71@example.test', 'Owner A Seventy One', decode('7171717171717171717171717171717171717171717171717171717171717171', 'hex'), 'req-71', 'corr-71');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007101', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Payment Match Contractor', 'Payment Match Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000007102','00000000-0000-0000-0000-000000007102','owner-b.71@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101')),
  ('10000000-0000-0000-0000-000000007103','00000000-0000-0000-0000-000000007103','client-a.71@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101')),
  ('10000000-0000-0000-0000-000000007104','00000000-0000-0000-0000-000000007104','client-b.71@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101')),
  ('10000000-0000-0000-0000-000000007105','00000000-0000-0000-0000-000000007105','accountant.71@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101')),
  ('10000000-0000-0000-0000-000000007106','00000000-0000-0000-0000-000000007106','pm.71@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101')),
  ('10000000-0000-0000-0000-000000007107','00000000-0000-0000-0000-000000007107','site.71@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101')
FROM app.users WHERE id BETWEEN '10000000-0000-0000-0000-000000007102' AND '10000000-0000-0000-0000-000000007107';
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000007102','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),true),
  ('10000000-0000-0000-0000-000000007103','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),true),
  ('10000000-0000-0000-0000-000000007104','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),true),
  ('10000000-0000-0000-0000-000000007105','accountant',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),true),
  ('10000000-0000-0000-0000-000000007106','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),true),
  ('10000000-0000-0000-0000-000000007107','site_supervisor',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000007101'),true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000007101','Client A 71','Client A 71 LLC','client-a.71@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000007101','Client B 71','Client B 71 LLC','client-b.71@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.clients WHERE display_name='Client A 71'),'10000000-0000-0000-0000-000000007103',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.clients WHERE display_name='Client B 71'),'10000000-0000-0000-0000-000000007104',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.clients WHERE display_name='Client A 71'),'Project A 71','USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.clients WHERE display_name='Client B 71'),'Project B 71','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000007101','Match Bank','BANK','USD','Bank','****7100');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.projects WHERE name='Project A 71'),200,'USD',DATE '2026-07-30',(SELECT id FROM app.financial_accounts WHERE account_number='FA-000001'),'match-pay-1') $$, 'payment draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000007101',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='match-pay-1'),1) $$, 'payment submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000007102',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='match-pay-1'),2) $$, 'payment approved and posted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.projects WHERE name='Project A 71'),150,'USD',DATE '2026-07-30',DATE '2026-08-30','Request one') $$, 'request one draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_send_payment_request('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Request one'),1) $$, 'request one sent');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.projects WHERE name='Project A 71'),100,'USD',DATE '2026-06-30',DATE '2026-07-01','Request two') $$, 'request two draft created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_send_payment_request('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Request two'),1) $$, 'request two sent overdue candidate');

SELECT results_eq($$ SELECT payment_amount, approved_active_matched_amount, unmatched_amount, economically_active, eligible_for_matching FROM public.server_owner_client_payment_availability('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1')) $$, $$ VALUES (200::numeric,0::numeric,200::numeric,true,true) $$, 'approved posted unreversed payment is fully available');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),100) $$, 'Owner creates match draft');
SELECT results_eq($$ SELECT status::text, matched_amount, currency_code, is_active FROM app.payment_matches $$, $$ VALUES ('DRAFT'::text,100::numeric,'USD'::char(3),true) $$, 'draft match has no approval fields and derived currency');
SELECT results_eq($$ SELECT paid_amount, remaining_amount, status::text FROM public.server_owner_payment_request_balance('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Request one')) $$, $$ VALUES (0::numeric,150::numeric,'SENT'::text) $$, 'draft match does not reserve request capacity');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_matches),(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),100,(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),120) $$, 'creator updates draft with compare-and-lock');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_payment_match('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.payment_matches),(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),120,(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),130) $$, '42501', 'Only the match creator can update the draft.', 'another Owner cannot update creator draft');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_matches)) $$, '42501', 'Payment match requires different Owner approval.', 'creator cannot approve own match');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_payment_match('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.payment_matches)) $$, 'different Owner approves match');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_payment_match('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.payment_matches)) $$, 'approval retry is idempotent');
SELECT results_eq($$ SELECT pm.status::text, pm.approved_at IS NOT NULL, pm.approved_by IS NOT NULL, pr.status::text FROM app.payment_matches pm JOIN app.payment_requests pr ON pr.id=pm.payment_request_id $$, $$ VALUES ('APPROVED'::text,true,true,'PARTIALLY_PAID'::text) $$, 'approval sets fields and synchronizes partial request');
SELECT results_eq($$ SELECT approved_active_matched_amount, unmatched_amount FROM public.server_owner_client_payment_availability('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1')) $$, $$ VALUES (120::numeric,80::numeric) $$, 'payment availability deducts approved active match');
SELECT results_eq($$ SELECT paid_amount, remaining_amount, effective_status::text FROM public.server_owner_payment_request_balance('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Request one')) $$, $$ VALUES (120::numeric,30::numeric,'PARTIALLY_PAID'::text) $$, 'request balance uses approved match aggregate');
SELECT is((SELECT count(*)::integer FROM app.financial_events), 1, 'matching creates no financial events');
SELECT is((SELECT count(*)::integer FROM app.financial_transactions), 1, 'matching creates no financial transactions');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries), 2, 'matching creates no ledger entries beyond payment posting');

SELECT throws_ok($$ SELECT * FROM public.server_owner_create_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),1) $$, '23505', 'Payment and request pair already matched.', 'voided/approved pair uniqueness prevents duplicate pair');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request two'),90) $$, 'same payment can draft-match another request in same Project');
SELECT throws_ok($$ SELECT * FROM public.server_owner_approve_payment_match('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.payment_matches WHERE payment_request_id=(SELECT id FROM app.payment_requests WHERE description='Request two'))) $$, '23514', 'Payment match exceeds available amount.', 'request or payment over-allocation is denied under locks');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_matches WHERE payment_request_id=(SELECT id FROM app.payment_requests WHERE description='Request two')),(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request two'),90,(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request two'),50) $$, 'creator lowers second draft after capacity failure');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_payment_match('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.payment_matches WHERE payment_request_id=(SELECT id FROM app.payment_requests WHERE description='Request two'))) $$, 'second request approved within remaining capacity');
SELECT results_eq($$ SELECT paid_amount, remaining_amount, effective_status::text FROM public.server_owner_payment_request_balance('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Request two')) $$, $$ VALUES (50::numeric,50::numeric,'OVERDUE'::text) $$, 'partial overdue precedence reports overdue with positive paid amount');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.projects WHERE name='Project B 71'),20,'USD',DATE '2026-07-30',NULL,'Cross project request') $$, 'cross project request draft created');

SELECT throws_ok($$ SELECT * FROM public.server_owner_create_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Cross project request'),10) $$, '23514', 'Payment request is not matchable.', 'draft request denied before cross-project allocation');
SELECT lives_ok($$ SELECT * FROM public.server_owner_send_payment_request('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Cross project request'),1) $$, 'cross project request sent');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Cross project request'),10) $$, '23514', 'Payment match requires same Project, Client and currency.', 'cross-Project and cross-Client matching denied');

SELECT lives_ok($$ SELECT * FROM public.server_owner_void_payment_match('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.payment_matches WHERE payment_request_id=(SELECT id FROM app.payment_requests WHERE description='Request one')),'wrong allocation') $$, 'approved match can be voided by approving Owner');
SELECT lives_ok($$ SELECT * FROM public.server_owner_void_payment_match('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.payment_matches WHERE payment_request_id=(SELECT id FROM app.payment_requests WHERE description='Request one')),'ignored retry reason') $$, 'void retry is idempotent');
SELECT results_eq($$ SELECT status::text, is_active, approved_at IS NOT NULL, approved_by IS NOT NULL, voided_at IS NOT NULL, voided_by IS NOT NULL, btrim(void_reason) <> '' FROM app.payment_matches WHERE payment_request_id=(SELECT id FROM app.payment_requests WHERE description='Request one') $$, $$ VALUES ('VOIDED'::text,false,true,true,true,true,true) $$, 'void preserves approval history and records void fields');
SELECT results_eq($$ SELECT paid_amount, remaining_amount, status::text FROM public.server_owner_payment_request_balance('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Request one')) $$, $$ VALUES (0::numeric,150::numeric,'SENT'::text) $$, 'void recalculates request balance and restores sent status');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_payment_match('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),10) $$, '23505', 'Payment and request pair already matched.', 'voided pair cannot be recreated');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007103', true);
SELECT results_eq($$ SELECT request_number::text, paid_amount, remaining_amount FROM public.current_client_payment_request_list(50,0) WHERE request_number=(SELECT request_number FROM app.payment_requests WHERE description='Request two') $$, $$ VALUES ('PREQ-000002'::text,50::numeric,50::numeric) $$, 'Client sees only aggregate paid and remaining values');
SELECT ok((SELECT pg_get_function_result('public.current_client_payment_request_list(integer,integer)'::regprocedure)) NOT ILIKE '%approved_by%' AND (SELECT pg_get_function_result('public.current_client_payment_request_list(integer,integer)'::regprocedure)) NOT ILIKE '%void_reason%', 'raw match rows and actors excluded from Client output');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007104', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_payment_request_list(50,0)), 1, 'cross-Client sees only own sent history');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007101', true);
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000007101', app.client_payment_transaction_id((SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1')), DATE '2026-07-30', 'reverse payment', 'reverse payment', 'rev-match') $$, 'full reversal of payment created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_reversal('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.financial_events WHERE description='reverse payment'),1) $$, 'payment reversal submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.financial_events WHERE description='reverse payment'),2) $$, 'payment reversal approved');
SELECT results_eq($$ SELECT economically_active, unmatched_amount, eligible_for_matching FROM public.server_owner_client_payment_availability('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1')) $$, $$ VALUES (false,0::numeric,false) $$, 'one full reversal makes payment inactive with zero availability');
SELECT lives_ok($$ SELECT * FROM public.server_owner_refresh_payment_request_overdue('00000000-0000-0000-0000-000000007101') $$, 'explicit refresh repairs statuses after reversal');
SELECT results_eq($$ SELECT paid_amount, remaining_amount, status::text FROM public.server_owner_payment_request_balance('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.payment_requests WHERE description='Request two')) $$, $$ VALUES (0::numeric,100::numeric,'OVERDUE'::text) $$, 'reversed payment stops contributing to request balance');
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_reversal('00000000-0000-0000-0000-000000007101', (SELECT ft.id FROM app.financial_transactions ft JOIN app.financial_events fe ON fe.id=ft.financial_event_id WHERE fe.description='reverse payment'), DATE '2026-07-30', 'reverse reversal', 'reverse reversal', 'rev-rev-match') $$, 'reversal of reversal created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_submit_reversal('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.financial_events WHERE description='reverse reversal'),1) $$, 'reversal of reversal submitted');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_reversal('00000000-0000-0000-0000-000000007102',(SELECT id FROM app.financial_events WHERE description='reverse reversal'),2) $$, 'reversal of reversal approved');
SELECT results_eq($$ SELECT economically_active, approved_active_matched_amount FROM public.server_owner_client_payment_availability('00000000-0000-0000-0000-000000007101',(SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1')) $$, $$ VALUES (true,50::numeric) $$, 'reversal-of-reversal restores economic match contribution');

SELECT throws_ok($$ DELETE FROM app.payment_matches $$, '23514', 'Payment matches cannot be deleted.', 'payment match delete denied');
SELECT set_config('app.payment_match_context','',true);
SELECT throws_ok($$ INSERT INTO app.payment_matches (client_payment_id,payment_request_id,matched_amount,currency_code,matched_by) VALUES ((SELECT id FROM app.client_payments WHERE payment_reference='match-pay-1'),(SELECT id FROM app.payment_requests WHERE description='Request one'),1,'USD','10000000-0000-0000-0000-000000007101') $$, '23514', 'Payment matches require trusted functions.', 'direct payment match insert denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_payment_match_list('00000000-0000-0000-0000-000000007105',50,0) $$, '42501', 'Privileged operation denied.', 'Accountant denied match list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_payment_match_list('00000000-0000-0000-0000-000000007106',50,0) $$, '42501', 'Privileged operation denied.', 'Project Manager denied match list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_payment_match_list('00000000-0000-0000-0000-000000007107',50,0) $$, '42501', 'Privileged operation denied.', 'Site Supervisor denied match list');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action='payment_match_voided' AND (previous_values::text ILIKE '%wrong allocation%' OR new_values::text ILIKE '%ignored retry%' OR metadata::text ILIKE '%wrong allocation%')), 'void reasons are not logged');

SELECT * FROM finish();
ROLLBACK;
