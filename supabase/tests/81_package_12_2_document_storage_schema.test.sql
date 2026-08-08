BEGIN;
SELECT plan(34);

SELECT has_type('app', 'document_upload_status', 'document upload status enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='document_upload_status' ORDER BY enumsortorder $$,
  $$ VALUES ('AUTHORIZED'::name),('UPLOADED'::name),('VALIDATED'::name),('AWAITING_SCAN'::name),('FAILED'::name),('EXPIRED'::name),('SCAN_IN_PROGRESS'::name),('SCAN_CLEAN'::name),('QUARANTINED'::name),('SCAN_FAILED'::name),('FINALIZING'::name),('FINALIZED'::name) $$,
  'document upload statuses include Package 12.2 states and Package 12.3 forward states'
);
SELECT has_table('app', 'document_uploads', 'document upload reservation table exists');
SELECT columns_are('app', 'document_uploads', ARRAY[
  'id','reserved_document_id','storage_bucket','storage_object_key','original_file_name','declared_mime_type','verified_mime_type','verified_file_size_bytes','verified_sha256_hash',
  'document_type_code','requested_client_visible','client_id','project_id','task_id','progress_update_id','status','authorized_at','authorized_by','expires_at','uploaded_at','validated_at',
  'client_payment_id','payment_request_id','project_expense_id','currency_exchange_id',
  'awaiting_scan_at','failed_at','expired_at','invalidated_at','failure_code','finalized_document_id','final_storage_object_key','scan_started_at','scan_completed_at','quarantined_at','finalizing_at','finalized_at'
], 'document uploads preserve Package 12.2 columns and add Package 12.3/12.4 operational columns');
SELECT col_type_is('app','document_uploads','storage_bucket','character varying(100)','bucket type exact');
SELECT col_type_is('app','document_uploads','storage_object_key','text','object key type exact');
SELECT col_type_is('app','document_uploads','verified_file_size_bytes','bigint','verified size type exact');
SELECT col_type_is('app','document_uploads','verified_sha256_hash','bytea','verified hash type exact');
SELECT col_type_is('app','document_uploads','status','app.document_upload_status','status type exact');
SELECT col_default_is('app','document_uploads','storage_bucket','documents-private','private bucket default exact');
SELECT col_default_is('app','document_uploads','requested_client_visible','false','requested client visibility defaults false');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_reserved_document_uk'), 'reserved document id unique');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_storage_object_key_uk'), 'temporary object key unique');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_bucket_ck'), 'bucket constrained to documents-private');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_temp_key_ck'), 'temporary opaque key format constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_declared_mime_type_ck'), 'declared MIME allowlist constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_verified_mime_type_ck'), 'verified MIME allowlist constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_size_ck'), '25 MiB and nonzero size constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_sha256_ck'), 'trusted SHA-256 length constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_one_target_ck'), 'exactly one enabled target constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_finalized_state_ck'), 'Package 12.3 permits only proper finalized upload linkage');
SELECT fk_ok('app','document_uploads','document_type_code','app','document_types','code','document type FK exists');
SELECT fk_ok('app','document_uploads','authorized_by','app','users','id','uploader FK exists');
SELECT fk_ok('app','document_uploads','finalized_document_id','app','documents','id','future finalized document FK exists');
SELECT results_eq($$ SELECT id::text, name, public, file_size_limit FROM storage.buckets WHERE id='documents-private' $$, $$ VALUES ('documents-private'::text,'documents-private'::text,false,26214400::bigint) $$, 'documents-private bucket is private with 25 MiB limit');
SELECT results_eq($$ SELECT unnest(allowed_mime_types) FROM storage.buckets WHERE id='documents-private' ORDER BY 1 $$, $$ VALUES ('application/pdf'::text),('image/jpeg'::text),('image/png'::text),('image/webp'::text) $$, 'bucket MIME allowlist exact');
SELECT has_function('public','server_owner_reserve_document_upload',ARRAY['uuid','text','text','text','character varying','boolean','uuid','uuid','uuid','uuid','text','uuid','uuid','uuid','uuid'],'reserve upload RPC exists with Package 12.4 finance targets');
SELECT has_function('public','server_owner_complete_document_upload',ARRAY['uuid','uuid','text','bigint','bytea','text'],'complete upload RPC exists');
SELECT has_function('public','server_authorize_document_access',ARRAY['uuid','uuid','text','text'],'document access authorization RPC exists');
SELECT has_function('public','server_owner_invalidate_expired_document_upload',ARRAY['uuid','uuid','text'],'orphan invalidation RPC exists');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%document_upload%', 'current_account unchanged for document storage');
SELECT columns_are('app','documents',ARRAY['id','document_number','storage_bucket','storage_object_key','original_file_name','mime_type','file_size_bytes','sha256_hash','document_type_code','status','client_visible','notes','uploaded_at','uploaded_by','archived_at','archived_by'], 'Package 12.1 documents schema preserved exactly');
SELECT ok(EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name='document_scans') AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name='document_thumbnails'), 'Package 12.3 scanner table exists while thumbnails remain absent');
SELECT ok(EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name='current_client_reserve_transfer_evidence_upload'), 'Package 12.4 narrow Client upload gateway present');

SELECT * FROM finish();
ROLLBACK;
