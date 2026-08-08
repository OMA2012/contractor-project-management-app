BEGIN;
SELECT plan(31);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000008601','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.86@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008602','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.86@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008603','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other.86@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008604','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pm.86@example.test','',now(),'{}','{}',now(),now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000008601','owner.86@example.test','Owner Eighty Six',decode('8686868686868686868686868686868686868686868686868686868686868686','hex'),'req-86','corr-86');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008601',true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Document Scan Contractor','Document Scan Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000008602','00000000-0000-0000-0000-000000008602','client.86@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601')),
  ('10000000-0000-0000-0000-000000008603','00000000-0000-0000-0000-000000008603','other.86@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601')),
  ('10000000-0000-0000-0000-000000008604','00000000-0000-0000-0000-000000008604','pm.86@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000008602','Client 86',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601')),
  ('10000000-0000-0000-0000-000000008603','Other 86',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601')),
  ('10000000-0000-0000-0000-000000008604','PM 86',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'));
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000008602','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),true),
  ('10000000-0000-0000-0000-000000008603','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),true),
  ('10000000-0000-0000-0000-000000008604','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008601'),true);
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008601','Client A 86',NULL,'client.a.86@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008601','Client B 86',NULL,'client.b.86@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.clients WHERE display_name='Client A 86'),'10000000-0000-0000-0000-000000008602',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.clients WHERE display_name='Client B 86'),'10000000-0000-0000-0000-000000008603',1);

SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008601','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','clean.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 86'),NULL,NULL,NULL,'req');
SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'application/pdf',10,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req');
SELECT lives_ok($$ SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'req') $$, 'AWAITING_SCAN can start scan');
SELECT results_eq($$ SELECT status::text FROM app.document_uploads WHERE original_file_name='clean.pdf' $$, $$ VALUES ('SCAN_IN_PROGRESS'::text) $$, 'scan start transitions to in progress');
SELECT throws_ok($$ SELECT * FROM public.server_owner_record_document_scan_result('00000000-0000-0000-0000-000000008602',(SELECT id FROM app.document_scans WHERE document_upload_id=(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf')),'CLEAN',decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),10,NULL,NULL,NULL,NULL,'req') $$, '42501', 'Privileged operation denied.', 'Client cannot forge CLEAN');
SELECT lives_ok($$ SELECT * FROM public.server_owner_record_document_scan_result('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_scans WHERE document_upload_id=(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf')),'CLEAN',decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),10,'ClamAV 1','db1',NULL,NULL,'req') $$, 'trusted clean scan recorded');
SELECT results_eq($$ SELECT status::text FROM app.document_uploads WHERE original_file_name='clean.pdf' $$, $$ VALUES ('SCAN_CLEAN'::text) $$, 'clean scan does not publish immediately');
SELECT throws_ok($$ UPDATE app.document_scans SET status='ERROR' WHERE document_upload_id=(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf') $$, '42501', 'Document scan history can only be updated by the trusted scan result path.', 'completed scan history cannot be rewritten directly');
SELECT is((SELECT count(*)::integer FROM app.documents), 0, 'no document exists before finalization');
SELECT lives_ok($$ SELECT * FROM public.server_owner_prepare_clean_document_finalization('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'req') $$, 'clean upload prepares finalization');
SELECT lives_ok($$ SELECT * FROM public.server_owner_prepare_clean_document_finalization('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'req') $$, 'finalizing upload can resume finalization preparation');
SELECT ok((SELECT final_storage_object_key ~ ('^objects/' || reserved_document_id::text || '/[0-9a-f]{43}$') FROM app.document_uploads WHERE original_file_name='clean.pdf'), 'final object key is opaque and document scoped');
SELECT lives_ok($$ SELECT * FROM public.server_owner_finalize_clean_document_upload('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf'),decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),10,'req') $$, 'clean upload finalizes after final object verification');
SELECT results_eq($$ SELECT du.status::text, du.finalized_document_id = du.reserved_document_id, d.id = du.reserved_document_id, d.sha256_hash = du.verified_sha256_hash, d.storage_object_key = du.final_storage_object_key FROM app.document_uploads du JOIN app.documents d ON d.id=du.finalized_document_id WHERE du.original_file_name='clean.pdf' $$, $$ VALUES ('FINALIZED'::text,true,true,true,true) $$, 'finalized document uses trusted upload facts');
SELECT is((SELECT count(*)::integer FROM app.document_links dl JOIN app.document_uploads du ON du.finalized_document_id=dl.document_id WHERE du.original_file_name='clean.pdf'), 1, 'exactly one document link created');
SELECT lives_ok($$ SELECT * FROM public.server_owner_finalize_clean_document_upload('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf'),decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),10,'req') $$, 'duplicate finalization idempotent');
SELECT is((SELECT count(*)::integer FROM app.documents), 1, 'duplicate finalization creates one document');
SELECT is((SELECT count(*)::integer FROM app.document_links), 1, 'duplicate finalization creates one link');
SELECT throws_ok($$ SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'req') $$, '23514', 'Document upload is already finalized.', 'finalized upload cannot be rescanned');
SELECT lives_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008602',(SELECT finalized_document_id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'preview','req') $$, 'Client can access after clean finalization');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008603',(SELECT finalized_document_id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'download','req') $$, '42501', 'Document access denied.', 'cross-Client denial remains');
SELECT * FROM public.server_owner_archive_document_metadata('00000000-0000-0000-0000-000000008601',(SELECT finalized_document_id FROM app.document_uploads WHERE original_file_name='clean.pdf'));
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008602',(SELECT finalized_document_id FROM app.document_uploads WHERE original_file_name='clean.pdf'),'download','req') $$, '42501', 'Document access denied.', 'archived Client denial remains');

SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008601','BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB','bad.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 86'),NULL,NULL,NULL,'req');
SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='bad.pdf'),'application/pdf',10,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'req');
SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='bad.pdf'),'req');
SELECT throws_ok($$ INSERT INTO app.document_scans (document_upload_id, attempt_number, status, scanner_engine, scanned_storage_bucket, scanned_storage_object_key, scanned_sha256_hash, scanned_file_size_bytes) SELECT id, 1, 'STARTED', 'clamav-compatible-https', storage_bucket, storage_object_key, verified_sha256_hash, verified_file_size_bytes FROM app.document_uploads WHERE original_file_name='bad.pdf' $$, '23505', NULL, 'duplicate upload scan attempt is rejected');
SELECT throws_ok($$ INSERT INTO app.document_scans (document_upload_id, attempt_number, status, scanner_engine, scanned_storage_bucket, scanned_storage_object_key, scanned_sha256_hash, scanned_file_size_bytes) SELECT id, 2, 'STARTED', 'clamav-compatible-https', storage_bucket, storage_object_key, verified_sha256_hash, verified_file_size_bytes FROM app.document_uploads WHERE original_file_name='bad.pdf' $$, '23505', NULL, 'second active started scan is rejected');
SELECT * FROM public.server_owner_record_document_scan_result('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_scans WHERE document_upload_id=(SELECT id FROM app.document_uploads WHERE original_file_name='bad.pdf')),'MALICIOUS',decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),10,'ClamAV','db','scanner_unavailable','Eicar-Test','req');
SELECT results_eq($$ SELECT status::text, quarantined_at IS NOT NULL FROM app.document_uploads WHERE original_file_name='bad.pdf' $$, $$ VALUES ('QUARANTINED'::text,true) $$, 'malicious upload is logically quarantined');
SELECT throws_ok($$ UPDATE app.document_uploads SET finalized_document_id = reserved_document_id WHERE original_file_name='bad.pdf' $$, '23514', NULL, 'quarantined upload cannot be linked to a finalized document id');
SELECT is((SELECT count(*)::integer FROM app.documents WHERE original_file_name='bad.pdf'), 0, 'malicious upload never publishes');
SELECT throws_ok($$ SELECT * FROM public.server_owner_prepare_clean_document_finalization('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='bad.pdf'),'req') $$, '23514', 'Document upload does not have a clean scan.', 'quarantine cannot publish');

SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008601','CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC','error.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 86'),NULL,NULL,NULL,'req');
SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='error.pdf'),'application/pdf',10,decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),'req');
SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='error.pdf'),'req');
SELECT * FROM public.server_owner_record_document_scan_result('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_scans WHERE document_upload_id=(SELECT id FROM app.document_uploads WHERE original_file_name='error.pdf')),'ERROR',decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),10,NULL,NULL,'timeout',NULL,'req');
SELECT results_eq($$ SELECT status::text, failure_code FROM app.document_uploads WHERE original_file_name='error.pdf' $$, $$ VALUES ('SCAN_FAILED'::text,'timeout'::character varying) $$, 'scanner error fails closed');
SELECT lives_ok($$ SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000008601',(SELECT id FROM app.document_uploads WHERE original_file_name='error.pdf'),'req') $$, 'scan failed upload can retry');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008604','DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD','pm.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 86'),NULL,NULL,NULL,'req') $$, '42501', 'Privileged operation denied.', 'reserved-role upload still denied');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action LIKE 'document_%' AND (metadata::text ILIKE '%objects/%' OR metadata::text ILIKE '%temporary/%' OR metadata::text ILIKE '%signed%' OR metadata::text ILIKE '%token%')), 'scan activity logs omit sensitive paths and tokens');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_finance_targets_disabled_ck'), 'finance links are forward-enabled by Package 12.4');

SELECT * FROM finish();
ROLLBACK;
