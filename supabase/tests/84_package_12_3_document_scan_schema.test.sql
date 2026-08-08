BEGIN;
SELECT plan(35);

SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='document_upload_status' ORDER BY enumsortorder $$,
  $$ VALUES ('AUTHORIZED'::name),('UPLOADED'::name),('VALIDATED'::name),('AWAITING_SCAN'::name),('FAILED'::name),('EXPIRED'::name),('SCAN_IN_PROGRESS'::name),('SCAN_CLEAN'::name),('QUARANTINED'::name),('SCAN_FAILED'::name),('FINALIZING'::name),('FINALIZED'::name) $$,
  'document upload statuses include Package 12.3 operational states'
);
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='document_scan_status' ORDER BY enumsortorder $$,
  $$ VALUES ('STARTED'::name),('CLEAN'::name),('MALICIOUS'::name),('ERROR'::name) $$,
  'document scan status enum exact'
);
SELECT has_table('app','document_scans','document scan attempts table exists');
SELECT columns_are('app','document_scans',ARRAY['id','document_upload_id','attempt_number','status','scanner_engine','scanner_version','signature_database_version','started_at','completed_at','failure_category','malware_name','scanned_storage_bucket','scanned_storage_object_key','scanned_sha256_hash','scanned_file_size_bytes','created_at'], 'document scans exact columns');
SELECT col_type_is('app','document_scans','status','app.document_scan_status','scan status type exact');
SELECT col_type_is('app','document_scans','scanned_sha256_hash','bytea','scan hash type exact');
SELECT col_type_is('app','document_scans','scanned_file_size_bytes','bigint','scan size type exact');
SELECT fk_ok('app','document_scans','document_upload_id','app','document_uploads','id','scan upload FK exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_scans_bucket_ck'), 'scan bucket constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_scans_temp_key_ck'), 'scan temporary key constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_scans_sha256_ck'), 'scan SHA-256 constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_scans_completion_ck'), 'scan completion constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_scans_upload_attempt_uk'), 'scan attempt number unique per upload');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_final_key_ck'), 'final object key constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_finalized_state_ck'), 'finalized upload linkage constrained');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_no_finalized_before_scan_ck'), 'Package 12.2 no-finalize constraint replaced');
SELECT col_type_is('app','document_uploads','final_storage_object_key','text','final key stored in trusted upload state');
SELECT has_function('public','server_owner_start_document_scan',ARRAY['uuid','uuid','text'],'scan start gateway exists');
SELECT has_function('public','server_owner_record_document_scan_result',ARRAY['uuid','uuid','app.document_scan_status','bytea','bigint','text','text','text','text','text'],'scan result gateway exists');
SELECT has_function('public','server_owner_prepare_clean_document_finalization',ARRAY['uuid','uuid','text'],'finalization prepare gateway exists');
SELECT has_function('public','server_owner_finalize_clean_document_upload',ARRAY['uuid','uuid','bytea','bigint','text'],'finalization commit gateway exists');
SELECT columns_are('app','documents',ARRAY['id','document_number','storage_bucket','storage_object_key','original_file_name','mime_type','file_size_bytes','sha256_hash','document_type_code','status','client_visible','notes','uploaded_at','uploaded_by','archived_at','archived_by'], 'Package 12.1 documents schema still exact');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='document_status' ORDER BY enumsortorder $$, $$ VALUES ('ACTIVE'::name),('ARCHIVED'::name) $$, 'document status remains ACTIVE ARCHIVED only');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%document_scan%', 'current_account unchanged by scanner');
SELECT ok((SELECT pg_get_functiondef('app.document_generate_final_object_key(uuid)'::regprocedure)) ILIKE '%objects/%', 'final key uses objects namespace');
SELECT ok((SELECT pg_get_functiondef('app.document_generate_final_object_key(uuid)'::regprocedure)) ILIKE '%gen_random_uuid%', 'final key uses cryptographic randomness');
SELECT ok((SELECT pg_get_functiondef('app.owner_finalize_clean_document_upload(uuid,uuid,bytea,bigint,text)'::regprocedure)) ILIKE '%reserved_document_id%', 'finalization uses reserved document id');
SELECT ok((SELECT pg_get_functiondef('app.owner_finalize_clean_document_upload(uuid,uuid,bytea,bigint,text)'::regprocedure)) ILIKE '%verified_sha256_hash%', 'finalization preserves trusted SHA-256');
SELECT ok((SELECT pg_get_functiondef('app.owner_finalize_clean_document_upload(uuid,uuid,bytea,bigint,text)'::regprocedure)) ILIKE '%document_links%', 'finalization creates document link');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='app' AND tablename='document_scans' AND indexname='document_scans_clean_upload_idx'), 'clean scan index exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='app' AND tablename='document_scans' AND indexname='document_scans_one_started_attempt_idx'), 'one active scan attempt index exists');
SELECT ok((SELECT pg_get_indexdef(indexrelid) FROM pg_index WHERE indexrelid='app.document_scans_one_started_attempt_idx'::regclass) ILIKE '%WHERE (status = ''STARTED''%', 'one active scan attempt index is partial on STARTED');
SELECT has_function('app','document_scans_guard_history',ARRAY[]::name[],'scan history guard trigger function exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='document_scans_guard_history_trg'), 'scan history guard trigger exists');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_finance_targets_disabled_ck'), 'finance document links enabled by Package 12.4');

SELECT * FROM finish();
ROLLBACK;
