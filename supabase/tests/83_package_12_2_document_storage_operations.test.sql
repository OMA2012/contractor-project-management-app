BEGIN;
SELECT plan(36);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000008301','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.83@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008302','00000000-0000-0000-0000-000000000000','authenticated','authenticated','client.83@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008303','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other.83@example.test','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000008304','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pm.83@example.test','',now(),'{}','{}',now(),now());
SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000008301','owner.83@example.test','Owner Eighty Three',decode('8383838383838383838383838383838383838383838383838383838383838383','hex'),'req-83','corr-83');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008301',true);
SELECT public.activate_current_invited_owner();
INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Document Storage Contractor','Document Storage Contractor','USD','Asia/Singapore',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'));
INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000008302','00000000-0000-0000-0000-000000008302','client.83@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('10000000-0000-0000-0000-000000008303','00000000-0000-0000-0000-000000008303','other.83@example.test','CLIENT','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('10000000-0000-0000-0000-000000008304','00000000-0000-0000-0000-000000008304','pm.83@example.test','STAFF','ACTIVE',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'));
INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000008302','Client 83',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('10000000-0000-0000-0000-000000008303','Other 83',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('10000000-0000-0000-0000-000000008304','PM 83',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'));
INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000008302','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),true),
  ('10000000-0000-0000-0000-000000008303','client',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),true),
  ('10000000-0000-0000-0000-000000008304','project_manager',(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'),true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008301','Client A 83',NULL,'client.a.83@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000008301','Client B 83',NULL,'client.b.83@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.clients WHERE display_name='Client A 83'),'10000000-0000-0000-0000-000000008302',1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.clients WHERE display_name='Client B 83'),'10000000-0000-0000-0000-000000008303',1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.clients WHERE display_name='Client A 83'),'Project A 83','USD');

SELECT lives_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','a.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, 'Owner reserves PDF upload');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB','a.jpg','image/jpeg','GENERAL',false,NULL,(SELECT id FROM app.projects WHERE name='Project A 83'),NULL,NULL,'req') $$, 'Owner reserves JPEG upload');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC','a.png','image/png','GENERAL',false,NULL,(SELECT id FROM app.projects WHERE name='Project A 83'),NULL,NULL,'req') $$, 'Owner reserves PNG upload');
SELECT lives_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD','a.webp','image/webp','GENERAL',false,NULL,(SELECT id FROM app.projects WHERE name='Project A 83'),NULL,NULL,'req') $$, 'Owner reserves WebP upload');
SELECT ok((SELECT bool_and(storage_object_key ~ '^temporary/[0-9a-f-]{36}/[A-Za-z0-9_-]{43}$') FROM app.document_uploads), 'object keys are opaque temporary paths');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.document_uploads WHERE storage_object_key ILIKE '%a.pdf%' OR storage_object_key ILIKE '%client%' OR storage_object_key ILIKE '%project%' OR storage_object_key ILIKE '%@%'), 'object keys omit user-identifying values');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008302','EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE','client.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, '42501', 'Privileged operation denied.', 'Client upload denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008304','FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF','pm.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, '42501', 'Privileged operation denied.', 'reserved-role upload denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG','bad.exe','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, '23514', 'Document file type is not allowed.', 'executable extension denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH','bad.pdf.exe','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, '23514', 'Document file type is not allowed.', 'dangerous double extension denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII','bad.pdf','image/png','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, '23514', 'Document MIME type and extension do not match.', 'MIME extension mismatch denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ','../bad.pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, '23514', 'Invalid document filename.', 'path traversal denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000008301','KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK','file..pdf','application/pdf','GENERAL',true,(SELECT id FROM app.clients WHERE display_name='Client A 83'),NULL,NULL,NULL,'req') $$, '23514', 'Invalid document filename.', 'ambiguous consecutive-dot filename denied');

SELECT throws_ok($$ SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.pdf'),'application/pdf',0,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req') $$, '23514', 'Document upload validation failed.', 'zero-byte completion denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.pdf'),'application/pdf',26214401,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req') $$, '23514', 'Document upload validation failed.', 'oversized completion denied');
SELECT throws_ok($$ SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.pdf'),'image/png',10,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req') $$, '23514', 'Document upload validation failed.', 'magic MIME mismatch denied');
UPDATE app.document_uploads SET status='AUTHORIZED', failed_at=NULL, failure_code=NULL WHERE original_file_name='a.pdf';
SELECT lives_ok($$ SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.pdf'),'application/pdf',10,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req') $$, 'trusted completion succeeds');
SELECT results_eq($$ SELECT status::text, verified_mime_type::text, verified_file_size_bytes, octet_length(verified_sha256_hash), awaiting_scan_at IS NOT NULL FROM app.document_uploads WHERE original_file_name='a.pdf' $$, $$ VALUES ('AWAITING_SCAN'::text,'application/pdf'::text,10::bigint,32,true) $$, 'completion stops at AWAITING_SCAN with verified facts');
SELECT lives_ok($$ SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.pdf'),'application/pdf',10,decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','hex'),'req') $$, 'duplicate completion idempotent');
SELECT is((SELECT count(*)::integer FROM app.documents), 0, 'no ACTIVE app.documents row is created before scan');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action='document_upload_awaiting_scan'), 1, 'awaiting scan activity logged once');
UPDATE app.document_uploads SET expires_at=transaction_timestamp()-interval '1 minute' WHERE original_file_name='a.jpg';
SELECT throws_ok($$ SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.jpg'),'image/jpeg',10,decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','hex'),'req') $$, '23514', 'Document upload reservation expired.', 'completion after expiration denied');
SELECT lives_ok($$ SELECT * FROM public.server_owner_invalidate_expired_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.jpg'),'req') $$, 'expired orphan invalidation is idempotent');
SELECT ok((SELECT invalidated_at IS NOT NULL FROM app.document_uploads WHERE original_file_name='a.jpg'), 'orphan invalidated timestamp set');
SELECT throws_ok($$ SELECT * FROM public.server_owner_invalidate_expired_document_upload('00000000-0000-0000-0000-000000008301',(SELECT id FROM app.document_uploads WHERE original_file_name='a.pdf'),'req') $$, '42501', 'Document upload invalidation denied.', 'AWAITING_SCAN upload cannot be invalidated as orphan');

SELECT set_config('app.document_metadata_context','owner_metadata_mutation',true);
INSERT INTO app.documents (id, storage_bucket, storage_object_key, original_file_name, mime_type, file_size_bytes, sha256_hash, document_type_code, client_visible, uploaded_by)
VALUES
  ('20000000-0000-0000-0000-000000008301','documents-private','objects/20000000-0000-0000-0000-000000008301/opaque','visible.pdf','application/pdf',10,decode('cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('20000000-0000-0000-0000-000000008302','documents-private','objects/20000000-0000-0000-0000-000000008302/opaque','private.pdf','application/pdf',10,decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','hex'),'GENERAL',false,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('20000000-0000-0000-0000-000000008303','documents-private','objects/20000000-0000-0000-0000-000000008303/opaque','archived.pdf','application/pdf',10,decode('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','hex'),'GENERAL',true,(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'));
INSERT INTO app.document_links (document_id, client_id, created_by)
VALUES
  ('20000000-0000-0000-0000-000000008301',(SELECT id FROM app.clients WHERE display_name='Client A 83'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('20000000-0000-0000-0000-000000008302',(SELECT id FROM app.clients WHERE display_name='Client A 83'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301')),
  ('20000000-0000-0000-0000-000000008303',(SELECT id FROM app.clients WHERE display_name='Client A 83'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'));
SELECT * FROM public.server_owner_archive_document_metadata('00000000-0000-0000-0000-000000008301','20000000-0000-0000-0000-000000008303');
SELECT lives_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008301','20000000-0000-0000-0000-000000008301','download','req') $$, 'Owner can access active finalized document');
SELECT lives_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008301','20000000-0000-0000-0000-000000008303','download','req') $$, 'Owner can access archived finalized document');
SELECT lives_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008302','20000000-0000-0000-0000-000000008301','preview','req') $$, 'Client can preview own active client-visible finalized document');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008303','20000000-0000-0000-0000-000000008301','download','req') $$, '42501', 'Document access denied.', 'cross-Client access denied');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008302','20000000-0000-0000-0000-000000008302','download','req') $$, '42501', 'Document access denied.', 'contractor-private document denied to Client');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008302','20000000-0000-0000-0000-000000008303','download','req') $$, '42501', 'Document access denied.', 'archived document denied to Client');
INSERT INTO app.document_links (document_id, client_id, created_by)
VALUES ('20000000-0000-0000-0000-000000008301',(SELECT id FROM app.clients WHERE display_name='Client B 83'),(SELECT id FROM app.users WHERE auth_subject='00000000-0000-0000-0000-000000008301'));
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008302',true);
SELECT is_empty($$ SELECT * FROM public.current_client_document_list(50,0) WHERE id='20000000-0000-0000-0000-000000008301' $$, 'multi-Client-linked document is hidden from Client list');
SELECT throws_ok($$ SELECT * FROM public.server_authorize_document_access('00000000-0000-0000-0000-000000008302','20000000-0000-0000-0000-000000008301','download','req') $$, '42501', 'Document access denied.', 'multi-Client malicious link cannot broaden Client access');
SELECT throws_ok($$ UPDATE app.document_uploads SET storage_object_key='temporary/caller/path' $$, '23514', NULL, 'direct document_uploads mutation cannot create caller-selected path');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.activity_logs WHERE action LIKE 'document_%' AND (metadata::text ILIKE '%objects/%' OR metadata::text ILIKE '%temporary/%' OR metadata::text ILIKE '%signed%')), 'document activity logs omit object paths and signed URLs');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_finance_targets_disabled_ck'), 'finance document links remain disabled');

SELECT * FROM finish();
ROLLBACK;
