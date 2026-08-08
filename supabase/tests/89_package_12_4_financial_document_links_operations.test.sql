BEGIN;
SELECT plan(13);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000008901','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.89@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008902','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner-b.89@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008903','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.89@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008904','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other.89@example.test','',now(),'{}','{}',now(),now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000008901','owner.89@example.test','Owner 89',decode('8989898989898989898989898989898989898989898989898989898989898989','hex'),'req','corr');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008901',true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('P12.4 Ops Contractor','P12.4 Ops Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000008902','00000000-0000-0000-0000-000000008902','owner-b.89@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901')),
  ('10000000-0000-0000-0000-000000008903','00000000-0000-0000-0000-000000008903','client.89@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901')),
  ('10000000-0000-0000-0000-000000008904','00000000-0000-0000-0000-000000008904','other.89@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'), (SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901') FROM app.users WHERE id::text LIKE '10000000-0000-0000-0000-0000000089%';
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000008902','owner_admin',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'),true),
  ('10000000-0000-0000-0000-000000008903','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'),true),
  ('10000000-0000-0000-0000-000000008904','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008901'),true);
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008901','Client 89',NULL,'client.89@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008901','Other 89',NULL,'other.89@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.clients WHERE display_name='Client 89'),'10000000-0000-0000-0000-000000008903',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.clients WHERE display_name='Other 89'),'10000000-0000-0000-0000-000000008904',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.clients WHERE display_name='Client 89'),'Project 89','USD');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000008901','USD Bank 89','BANK','USD','Bank','****8901');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008903',true);
SELECT * FROM public.current_client_submit_payment((SELECT id FROM app.projects WHERE name='Project 89'),25,'USD',DATE '2026-07-30','client-89','payer');
SELECT * FROM public.current_client_reserve_transfer_evidence_upload('00000000-0000-0000-0000-000000008903','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','client-evidence.pdf','application/pdf',(SELECT id FROM app.client_payments WHERE payment_reference='client-89'),'req');
SELECT * FROM public.current_client_complete_transfer_evidence_upload('00000000-0000-0000-0000-000000008903',(SELECT id FROM app.document_uploads WHERE original_file_name='client-evidence.pdf'),'application/pdf',10,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008901',true);
SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.document_uploads WHERE original_file_name='client-evidence.pdf'),'req');
SELECT * FROM public.server_owner_record_document_scan_result('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.document_scans WHERE document_upload_id=(SELECT id FROM app.document_uploads WHERE original_file_name='client-evidence.pdf')),'CLEAN',decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),10,'ClamAV','db',NULL,NULL,'req');
SELECT * FROM public.server_owner_prepare_clean_document_finalization('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.document_uploads WHERE original_file_name='client-evidence.pdf'),'req');
SELECT * FROM public.server_owner_finalize_clean_document_upload('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.document_uploads WHERE original_file_name='client-evidence.pdf'),decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),10,'req');

SELECT results_eq($$ SELECT d.uploaded_by, d.client_visible, dl.created_by, dl.client_payment_id IS NOT NULL FROM app.documents d JOIN app.document_links dl ON dl.document_id=d.id WHERE d.original_file_name='client-evidence.pdf' $$, $$ VALUES ('10000000-0000-0000-0000-000000008903'::uuid,false,'10000000-0000-0000-0000-000000008903'::uuid,true) $$, 'finalization preserves Client uploader and link creator');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action='financial_document_linked'), 'financial link activity logged once');
SELECT lives_ok($$ SELECT * FROM public.server_owner_finalize_clean_document_upload('00000000-0000-0000-0000-000000008901',(SELECT id FROM app.document_uploads WHERE original_file_name='client-evidence.pdf'),decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),10,'req') $$, 'finalization retry is idempotent');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='financial_document_linked'), 1, 'financial link activity is not duplicated on retry');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008903',true);
SELECT lives_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008903',(SELECT id FROM app.documents WHERE original_file_name='client-evidence.pdf'),'download','req') $$, 'Client can access own finalized transfer evidence');
SELECT is((SELECT count(*)::integer FROM public.current_client_document_list(50,0) WHERE original_file_name='client-evidence.pdf'), 0, 'own private transfer evidence does not leak into generic Client list');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008904',true);
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008904',(SELECT id FROM app.documents WHERE original_file_name='client-evidence.pdf'),'download','req') $$, '42501', 'Document access denied.', 'another Client denied own-evidence access');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008901',true);
SELECT lives_ok($$ SELECT * FROM public.server_owner_verify_client_submitted_payment('00000000-0000-0000-0000-000000008901',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='client-89'),1,(SELECT id FROM app.financial_accounts LIMIT 1),'verified') $$, 'Owner verifies Client payment after evidence');
SELECT lives_ok($$ SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000008902',(SELECT financial_event_id FROM app.client_payments WHERE payment_reference='client-89'),2) $$, 'different Owner posts Client payment after evidence');
SELECT ok(EXISTS (SELECT 1 FROM app.document_links WHERE client_payment_id=(SELECT id FROM app.client_payments WHERE payment_reference='client-89')), 'evidence remains linked after posting');
SELECT throws_ok($$ SELECT * FROM public.current_client_reserve_transfer_evidence_upload('00000000-0000-0000-0000-000000008903','BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB','late.pdf','application/pdf',(SELECT id FROM app.client_payments WHERE payment_reference='client-89'),'req') $$, '42501', 'Client operation denied.', 'posted payment rejects new Client evidence');
SELECT throws_ok($$ DELETE FROM app.client_payments WHERE payment_reference='client-89' $$, '23514', 'Client payments cannot be deleted.', 'linked finance record cannot be hard-deleted');
SELECT is((SELECT count(*)::integer FROM app.ledger_entries), 2, 'document workflow did not add ledger entries beyond payment posting');

SELECT * FROM finish();
ROLLBACK;
