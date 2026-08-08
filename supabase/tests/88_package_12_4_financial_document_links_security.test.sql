BEGIN;
SELECT plan(21);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000008801','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.88@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008802','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client-a.88@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008803','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client-b.88@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008804','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pm.88@example.test','',now(),'{}','{}',now(),now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000008801','owner.88@example.test','Owner 88',decode('8888888888888888888888888888888888888888888888888888888888888888','hex'),'req','corr');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008801',true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('P12.4 Contractor','P12.4 Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000008802','00000000-0000-0000-0000-000000008802','client-a.88@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801')),
  ('10000000-0000-0000-0000-000000008803','00000000-0000-0000-0000-000000008803','client-b.88@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801')),
  ('10000000-0000-0000-0000-000000008804','00000000-0000-0000-0000-000000008804','pm.88@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801') FROM app.users WHERE id::text LIKE '10000000-0000-0000-0000-0000000088%';
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000008802','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'),true),
  ('10000000-0000-0000-0000-000000008803','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'),true),
  ('10000000-0000-0000-0000-000000008804','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008801'),true);
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008801','Client A 88',NULL,'client-a.88@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008801','Client B 88',NULL,'client-b.88@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008801',(SELECT id FROM app.clients WHERE display_name='Client A 88'),'10000000-0000-0000-0000-000000008802',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008801',(SELECT id FROM app.clients WHERE display_name='Client B 88'),'10000000-0000-0000-0000-000000008803',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000008801',(SELECT id FROM app.clients WHERE display_name='Client A 88'),'Project A 88','USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000008801',(SELECT id FROM app.clients WHERE display_name='Client B 88'),'Project B 88','USD');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008802',true);
SELECT * FROM public.current_client_submit_payment((SELECT id FROM app.projects WHERE name='Project A 88'),10,'USD',DATE '2026-07-30','client-88-a','payer');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008803',true);
SELECT * FROM public.current_client_submit_payment((SELECT id FROM app.projects WHERE name='Project B 88'),10,'USD',DATE '2026-07-30','client-88-b','payer');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008801',true);
SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000008801',(SELECT id FROM app.projects WHERE name='Project A 88'),11,'USD',DATE '2026-07-30',NULL,'owner-88','payer');

SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008802',true);
SELECT lives_ok($$ SELECT * FROM public.current_client_reserve_transfer_evidence_upload('00000000-0000-0000-0000-000000008802','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','evidence.pdf','application/pdf',(SELECT id FROM app.client_payments WHERE payment_reference='client-88-a'),'req') $$, 'Client reserves evidence for own submitted payment');
SELECT results_eq($$ SELECT document_type_code, requested_client_visible, authorized_by, client_payment_id IS NOT NULL FROM app.document_uploads WHERE original_file_name='evidence.pdf' $$, $$ VALUES ('BANK_TRANSFER_EVIDENCE'::varchar,false,'10000000-0000-0000-0000-000000008802'::uuid,true) $$, 'Client reservation forces type, visibility, uploader, and target');
SELECT throws_ok($$ SELECT * FROM public.current_client_reserve_transfer_evidence_upload('00000000-0000-0000-0000-000000008802','BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB','cross.pdf','application/pdf',(SELECT id FROM app.client_payments WHERE payment_reference='client-88-b'),'req') $$, '42501', 'Client operation denied.', 'Client cannot reserve against another Client payment');
SELECT throws_ok($$ SELECT * FROM public.current_client_reserve_transfer_evidence_upload('00000000-0000-0000-0000-000000008802','CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC','owner.pdf','application/pdf',(SELECT id FROM app.client_payments WHERE payment_reference='owner-88'),'req') $$, '42501', 'Client operation denied.', 'Client cannot reserve against Owner-created payment');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008803',true);
SELECT throws_ok($$ SELECT * FROM public.current_client_complete_transfer_evidence_upload('00000000-0000-0000-0000-000000008803',(SELECT id FROM app.document_uploads WHERE original_file_name='evidence.pdf'),'application/pdf',10,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req') $$, '42501', 'Client operation denied.', 'another Client cannot complete own-evidence upload');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008802',true);
SELECT lives_ok($$ SELECT * FROM public.current_client_complete_transfer_evidence_upload('00000000-0000-0000-0000-000000008802',(SELECT id FROM app.document_uploads WHERE original_file_name='evidence.pdf'),'application/pdf',10,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req') $$, 'Client completes own evidence upload to scan queue');
SELECT results_eq($$ SELECT status::text FROM app.document_uploads WHERE original_file_name='evidence.pdf' $$, $$ VALUES ('AWAITING_SCAN'::text) $$, 'Client completion stops at AWAITING_SCAN');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action='client_transfer_evidence_submitted'), 'Client evidence submission activity logged');
SELECT ok(NOT has_function_privilege('authenticated', 'public.current_client_reserve_transfer_evidence_upload(uuid, text, text, text, uuid, text)', 'EXECUTE'), 'Client cannot directly execute storage-key reservation RPC');
SELECT ok(NOT has_function_privilege('authenticated', 'public.current_client_transfer_evidence_upload_storage_context(uuid, uuid)', 'EXECUTE'), 'Client cannot directly execute storage-key context RPC');
SELECT ok(NOT has_function_privilege('authenticated', 'public.current_client_complete_transfer_evidence_upload(uuid, uuid, text, bigint, bytea, text)', 'EXECUTE'), 'Client cannot directly execute trusted-hash completion RPC');
SELECT throws_ok($$ SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000008802',(SELECT id FROM app.document_uploads WHERE original_file_name='evidence.pdf'),'req') $$, '42501', 'Privileged operation denied.', 'Client cannot invoke generic scan');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008801',true);
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008804','DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD','pm.pdf','application/pdf','PAYMENT_RECEIPT',false,NULL,NULL,NULL,NULL,'req',(SELECT id FROM app.client_payments WHERE payment_reference='client-88-a'),NULL,NULL,NULL) $$, '42501', 'Privileged operation denied.', 'Project Manager remains denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008801','EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE','owner-pay.pdf','application/pdf','PAYMENT_RECEIPT',true,NULL,NULL,NULL,NULL,'req',(SELECT id FROM app.client_payments WHERE payment_reference='client-88-a'),NULL,NULL,NULL) $$, 'Owner can reserve Client Payment evidence');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008801','FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF','expense-visible.pdf','application/pdf','EXPENSE_RECEIPT',true,NULL,NULL,NULL,NULL,'req',NULL,NULL,gen_random_uuid(),NULL) $$, '23514', 'Document link target is not available.', 'invalid expense target denied without Client leakage');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.notifications WHERE notification_type::text ILIKE '%evidence%'), 'no transfer evidence notifications created');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE metadata::text ILIKE '%temporary/%' OR metadata::text ILIKE '%objects/%' OR metadata::text ILIKE '%signed%'), 'activity logs omit storage keys and URLs');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008802',true);
SELECT throws_ok($$ SELECT * FROM public.current_client_reserve_transfer_evidence_upload('00000000-0000-0000-0000-000000008802','GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG','bad.exe','application/pdf',(SELECT id FROM app.client_payments WHERE payment_reference='client-88-a'),'req') $$, '23514', 'Document file type is not allowed.', 'Client upload preserves filename validation');
SELECT throws_ok($$ SELECT * FROM public.current_client_reserve_transfer_evidence_upload('00000000-0000-0000-0000-000000008802','HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH','bad.pdf','image/png',(SELECT id FROM app.client_payments WHERE payment_reference='client-88-a'),'req') $$, '23514', 'Document MIME type and extension do not match.', 'Client upload preserves MIME validation');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries), 0, 'evidence workflow has no ledger effect');
SELECT is((SELECT status::text FROM app.financial_events fe JOIN app.client_payments cp ON cp.financial_event_id=fe.id WHERE cp.payment_reference='client-88-a'), 'SUBMITTED', 'evidence upload does not change payment status');

SELECT * FROM finish();
ROLLBACK;
