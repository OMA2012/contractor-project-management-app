BEGIN;
SELECT plan(57);
-- Coverage marker: payment_request_status

ALTER SEQUENCE app.payment_request_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000006801', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.68@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006802', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.68@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006803', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-a.68@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006804', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-b.68@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006805', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'accountant.68@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006806', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm.68@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000006807', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'site.68@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000006801', 'owner-a.68@example.test', 'Owner A Sixty Eight', decode('6868686868686868686868686868686868686868686868686868686868686868', 'hex'), 'req-68', 'corr-68');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006801', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Payment Request Contractor', 'Payment Request Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000006802','00000000-0000-0000-0000-000000006802','owner-b.68@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801')),
  ('10000000-0000-0000-0000-000000006803','00000000-0000-0000-0000-000000006803','client-a.68@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801')),
  ('10000000-0000-0000-0000-000000006804','00000000-0000-0000-0000-000000006804','client-b.68@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801')),
  ('10000000-0000-0000-0000-000000006805','00000000-0000-0000-0000-000000006805','accountant.68@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801')),
  ('10000000-0000-0000-0000-000000006806','00000000-0000-0000-0000-000000006806','pm.68@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801')),
  ('10000000-0000-0000-0000-000000006807','00000000-0000-0000-0000-000000006807','site.68@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801')
FROM app.users WHERE id BETWEEN '10000000-0000-0000-0000-000000006802' AND '10000000-0000-0000-0000-000000006807';

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000006802','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),true),
  ('10000000-0000-0000-0000-000000006803','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),true),
  ('10000000-0000-0000-0000-000000006804','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),true),
  ('10000000-0000-0000-0000-000000006805','accountant',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),true),
  ('10000000-0000-0000-0000-000000006806','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),true),
  ('10000000-0000-0000-0000-000000006807','site_supervisor',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000006801'),true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000006801','Client A 68','Client A 68 LLC','client-a.68@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000006801','Client B 68','Client B 68 LLC','client-b.68@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.clients WHERE display_name='Client A 68'),'10000000-0000-0000-0000-000000006803',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.clients WHERE display_name='Client B 68'),'10000000-0000-0000-0000-000000006804',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.clients WHERE display_name='Client A 68'),'Project A 68','USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.clients WHERE display_name='Client B 68'),'Project B 68','USD');

SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.projects WHERE name='Project A 68'),100,'USD',DATE '2026-07-30',DATE '2026-08-15',' First invoice ') $$, 'Owner creates payment request draft');
SELECT results_eq($$ SELECT request_number::text, status::text, requested_amount, description, version_number FROM app.payment_requests WHERE description='First invoice' $$, $$ VALUES ('PREQ-000001'::text,'DRAFT'::text,100::numeric,'First invoice'::text,1) $$, 'draft has PREQ number and normalized description');
SELECT is((SELECT count(*)::integer FROM app.financial_events), 0, 'create produces no financial events');
SELECT is((SELECT count(*)::integer FROM app.financial_transactions), 0, 'create produces no financial transactions');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries), 0, 'create produces no ledger entries');
SELECT is((SELECT count(*)::integer FROM app.notifications WHERE notification_type ILIKE '%payment%'), 0, 'create produces no payment notification');

SELECT throws_ok($$ SELECT * FROM public.server_owner_update_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='First invoice'),0,(SELECT id FROM app.projects WHERE name='Project A 68'),120,'USD',DATE '2026-07-30',DATE '2026-08-15','Changed') $$, '40001', 'Payment request version conflict.', 'stale update rejected');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='First invoice'),1,(SELECT id FROM app.projects WHERE name='Project A 68'),120,'USD',DATE '2026-07-30',DATE '2026-08-20','Changed invoice') $$, 'Owner updates draft');
SELECT results_eq($$ SELECT requested_amount, due_date, description, version_number FROM app.payment_requests WHERE description='Changed invoice' $$, $$ VALUES (120::numeric, DATE '2026-08-20', 'Changed invoice'::text, 2) $$, 'draft update changes allowed facts and increments version once');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Changed invoice'),2,(SELECT id FROM app.projects WHERE name='Project A 68'),120,'USD',DATE '2026-08-21',DATE '2026-08-20','Bad dates') $$, '23514', 'Invalid payment request.', 'due date cannot precede request date');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.projects WHERE name='Project A 68'),0,'USD',DATE '2026-07-30',NULL,'Bad amount') $$, '23514', 'Invalid payment request.', 'positive amount required');
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.projects WHERE name='Project A 68'),1,'USD',DATE '2026-07-30',NULL,'   ') $$, '23514', 'Invalid payment request.', 'nonblank description required');

SELECT lives_ok($$ SELECT * FROM public.server_owner_send_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Changed invoice'),2) $$, 'Owner sends draft');
SELECT results_eq($$ SELECT status::text, sent_at IS NOT NULL, version_number FROM app.payment_requests WHERE description='Changed invoice' $$, $$ VALUES ('SENT'::text,true,3) $$, 'send sets sent status and increments version');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Changed invoice'),3,(SELECT id FROM app.projects WHERE name='Project A 68'),121,'USD',DATE '2026-07-30',DATE '2026-08-20','Sent mutate') $$, '23514', 'Payment request cannot be updated.', 'sent facts cannot be draft-updated');
SELECT throws_ok($$ UPDATE app.payment_requests SET request_number='PREQ-999998' WHERE description='Changed invoice' $$, '23514', 'Payment requests require trusted functions.', 'direct update denied');
SELECT throws_ok($$ DELETE FROM app.payment_requests WHERE description='Changed invoice' $$, '23514', 'Payment requests cannot be deleted.', 'delete denied');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006803', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_payment_request_list(50,0)), 1, 'Client sees own sent request');
SELECT is((SELECT count(*)::integer FROM public.current_client_payment_request_list(50,0) WHERE status='DRAFT'), 0, 'Client cannot see drafts');
SELECT results_eq($$ SELECT status::text, effective_status::text, paid_amount, remaining_amount FROM public.current_client_view_payment_request_detail((SELECT id FROM app.payment_requests WHERE description='Changed invoice')) $$, $$ VALUES ('VIEWED'::text,'VIEWED'::text,0::numeric,120::numeric) $$, 'explicit Client detail records first view and derived balances with no matches');
SELECT results_eq($$ SELECT status::text, viewed_at IS NOT NULL, version_number FROM app.payment_requests WHERE description='Changed invoice' $$, $$ VALUES ('VIEWED'::text,true,4) $$, 'first view mutates viewed fields once');
SELECT results_eq($$ SELECT status::text, effective_status::text FROM public.current_client_view_payment_request_detail((SELECT id FROM app.payment_requests WHERE description='Changed invoice')) $$, $$ VALUES ('VIEWED'::text,'VIEWED'::text) $$, 'repeated Client detail view is idempotent');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='payment_request_viewed' AND entity_id=(SELECT id FROM app.payment_requests WHERE description='Changed invoice')), 1, 'view activity logged once');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006804', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_payment_request_list(50,0)), 0, 'cross-Client list denied safely');
SELECT throws_ok($$ SELECT * FROM public.current_client_view_payment_request_detail((SELECT id FROM app.payment_requests WHERE description='Changed invoice')) $$, '42501', 'Client operation denied.', 'cross-Client detail denied');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006801', true);
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.projects WHERE name='Project A 68'),30,'USD',DATE '2026-07-01',DATE '2026-07-02','Old request') $$, 'Owner creates old draft');
SELECT lives_ok($$ SELECT * FROM public.server_owner_send_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Old request'),1) $$, 'Owner sends old request');
SELECT results_eq($$ SELECT status::text, effective_status::text FROM public.server_owner_payment_request_detail('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Old request')) $$, $$ VALUES ('SENT'::text,'OVERDUE'::text) $$, 'detail returns effective overdue without read mutation');
SELECT results_eq($$ SELECT status::text, version_number FROM app.payment_requests WHERE description='Old request' $$, $$ VALUES ('SENT'::text,2) $$, 'effective overdue read does not mutate stored row');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006803', true);
SELECT results_eq($$ SELECT status::text, effective_status::text FROM public.current_client_view_payment_request_detail((SELECT id FROM app.payment_requests WHERE description='Old request')) $$, $$ VALUES ('SENT'::text,'OVERDUE'::text) $$, 'overdue Client view preserves stored sent and returns effective overdue');
SELECT results_eq($$ SELECT status::text, viewed_at IS NOT NULL, version_number FROM app.payment_requests WHERE description='Old request' $$, $$ VALUES ('SENT'::text,true,3) $$, 'overdue Client view records first view only');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006801', true);
SELECT lives_ok($$ SELECT * FROM public.server_owner_refresh_payment_request_overdue('00000000-0000-0000-0000-000000006801') $$, 'Owner refreshes overdue requests');
SELECT results_eq($$ SELECT status::text, viewed_at IS NOT NULL, version_number FROM app.payment_requests WHERE description='Old request' $$, $$ VALUES ('OVERDUE'::text,true,4) $$, 'overdue refresh preserves first-view timestamp');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='payment_request_marked_overdue' AND entity_id=(SELECT id FROM app.payment_requests WHERE description='Old request')), 1, 'overdue activity logged once');
SELECT lives_ok($$ SELECT * FROM public.server_owner_refresh_payment_request_overdue('00000000-0000-0000-0000-000000006801') $$, 'overdue refresh retry is idempotent');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='payment_request_marked_overdue' AND entity_id=(SELECT id FROM app.payment_requests WHERE description='Old request')), 1, 'overdue retry does not duplicate log');

SELECT lives_ok($$ SELECT * FROM public.server_owner_cancel_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Changed invoice'),4,'client asked to pause') $$, 'Owner cancels viewed request');
SELECT results_eq($$ SELECT status::text, cancelled_at IS NOT NULL, cancelled_by IS NOT NULL, cancellation_reason IS NOT NULL, version_number FROM app.payment_requests WHERE description='Changed invoice' $$, $$ VALUES ('CANCELLED'::text,true,true,true,5) $$, 'cancel sets required fields and version');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006803', true);
SELECT ok((SELECT pg_get_function_result('public.current_client_payment_request_list(integer,integer)'::regprocedure)) NOT ILIKE '%cancellation_reason%', 'Client list excludes cancellation reason');
SELECT results_eq($$ SELECT status::text, effective_status::text FROM public.current_client_view_payment_request_detail((SELECT id FROM app.payment_requests WHERE description='Changed invoice')) $$, $$ VALUES ('CANCELLED'::text,'CANCELLED'::text) $$, 'sent then cancelled request remains Client-visible safely');
SELECT ok((SELECT pg_get_function_result('public.current_client_view_payment_request_detail(uuid,text,text)'::regprocedure)) NOT ILIKE '%cancelled_by%', 'Client result shape excludes cancelled_by');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006801', true);
SELECT throws_ok($$ SELECT * FROM public.server_owner_cancel_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Changed invoice'),5,'again') $$, '23514', 'Payment request cannot be cancelled.', 'cancelled is terminal');
SELECT throws_ok($$ SELECT * FROM public.server_owner_cancel_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.payment_requests WHERE description='Old request'),4,'') $$, '23514', 'Cancellation reason is required.', 'blank cancellation rejected');

SELECT throws_ok($$ SELECT * FROM public.server_owner_payment_request_list('00000000-0000-0000-0000-000000006803',50,0) $$, '42501', 'Privileged operation denied.', 'Client denied Owner list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_payment_request_list('00000000-0000-0000-0000-000000006805',50,0) $$, '42501', 'Privileged operation denied.', 'Accountant denied Owner list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_payment_request_list('00000000-0000-0000-0000-000000006806',50,0) $$, '42501', 'Privileged operation denied.', 'Project Manager denied Owner list');
SELECT throws_ok($$ SELECT * FROM public.server_owner_payment_request_list('00000000-0000-0000-0000-000000006807',50,0) $$, '42501', 'Privileged operation denied.', 'Site Supervisor denied Owner list');

UPDATE app.contractor_profiles SET time_zone='Invalid/Zone' WHERE singleton_key=1;
SELECT throws_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.projects WHERE name='Project A 68'),5,'USD',NULL,NULL,'Needs date') $$, '23514', 'Contractor time zone is invalid.', 'invalid contractor time zone fails safely');
UPDATE app.contractor_profiles SET time_zone='Asia/Singapore' WHERE singleton_key=1;
SELECT lives_ok($$ SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.projects WHERE name='Project A 68'),5,'USD',NULL,NULL,'Local date default') $$, 'local contractor date default works after valid time zone');
SELECT is((SELECT request_date FROM app.payment_requests WHERE description='Local date default'), app.contractor_local_date(), 'request date uses contractor-local helper');

SELECT throws_ok($$ SELECT setval('app.payment_request_number_seq', 999999, true); SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000006801',(SELECT id FROM app.projects WHERE name='Project A 68'),6,'USD',DATE '2026-07-30',NULL,'Overflow request') $$, '2200H', 'nextval: reached maximum value of sequence "payment_request_number_seq" (999999)', 'request numbering stops before seven digits');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='app' AND table_name='payment_requests' AND column_name IN ('paid_amount','remaining_amount')), 'paid and remaining are not stored');
SELECT throws_ok($$ SELECT set_config('app.payment_request_context','payment_request_owner_mutation',true); UPDATE app.payment_requests SET status='PARTIALLY_PAID' WHERE description='Old request' $$, '23514', 'Invalid payment request transition.', 'manual partial paid transition denied');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payment_uploads','payment_evidence')), 'payment uploads remain absent');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.notifications WHERE notification_type ILIKE '%payment_request%'), 'payment request notifications remain absent');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.document_links WHERE payment_request_id IS NOT NULL), 'payment request document links remain inactive');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action LIKE 'payment_request_%' AND (previous_values::text ILIKE '%client asked to pause%' OR new_values::text ILIKE '%client asked to pause%' OR metadata::text ILIKE '%client asked to pause%' OR previous_values::text ILIKE '%First invoice%' OR new_values::text ILIKE '%First invoice%')), 'sensitive request text omitted from activity logs');

SELECT * FROM finish();
ROLLBACK;
