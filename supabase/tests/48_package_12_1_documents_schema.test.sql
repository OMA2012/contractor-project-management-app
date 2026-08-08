BEGIN;
SELECT plan(47);

SELECT has_type('app', 'document_status', 'document status enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'app' AND t.typname = 'document_status' ORDER BY enumsortorder $$,
  $$ VALUES ('ACTIVE'::name), ('ARCHIVED'::name) $$,
  'document status enum values are exact'
);
SELECT has_table('app', 'document_types', 'document types table exists');
SELECT columns_are('app', 'document_types', ARRAY['code','name','default_client_visible','is_active'], 'document types have exact columns');
SELECT col_is_pk('app', 'document_types', 'code', 'document type code primary key');
SELECT col_type_is('app', 'document_types', 'code', 'character varying(50)', 'document type code length exact');
SELECT col_type_is('app', 'document_types', 'name', 'character varying(120)', 'document type name length exact');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_types_name_uk'), 'document type name unique');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_types_name_ck'), 'document type name nonblank');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_types_code_ck'), 'document type code uppercase stable');
SELECT col_default_is('app', 'document_types', 'default_client_visible', 'false', 'document type client visibility defaults false');
SELECT col_default_is('app', 'document_types', 'is_active', 'true', 'document type active defaults true');

SELECT has_table('app', 'documents', 'documents table exists');
SELECT columns_are('app', 'documents', ARRAY[
  'id','document_number','storage_bucket','storage_object_key','original_file_name','mime_type','file_size_bytes','sha256_hash',
  'document_type_code','status','client_visible','notes','uploaded_at','uploaded_by','archived_at','archived_by'
], 'documents have exact columns');
SELECT col_type_is('app', 'documents', 'document_number', 'character varying(60)', 'document number length exact');
SELECT col_type_is('app', 'documents', 'storage_bucket', 'character varying(100)', 'storage bucket length exact');
SELECT col_type_is('app', 'documents', 'storage_object_key', 'text', 'storage object key type exact');
SELECT col_type_is('app', 'documents', 'mime_type', 'character varying(150)', 'mime type length exact');
SELECT col_type_is('app', 'documents', 'file_size_bytes', 'bigint', 'file size type exact');
SELECT col_type_is('app', 'documents', 'sha256_hash', 'bytea', 'sha hash type exact');
SELECT col_type_is('app', 'documents', 'status', 'app.document_status', 'document status type exact');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_document_number_uk'), 'document number unique');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_storage_object_key_uk'), 'storage object key unique');
SELECT fk_ok('app', 'documents', 'document_type_code', 'app', 'document_types', 'code', 'document type foreign key exists');
SELECT fk_ok('app', 'documents', 'uploaded_by', 'app', 'users', 'id', 'uploaded by foreign key exists');
SELECT fk_ok('app', 'documents', 'archived_by', 'app', 'users', 'id', 'archived by foreign key exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_document_number_ck'), 'document number format constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_mime_type_ck'), 'mime type nonblank constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_file_size_bytes_ck'), 'positive file size constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_sha256_hash_ck'), 'sha256 hash length constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_archive_pair_ck'), 'archive fields paired');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_status_archive_ck'), 'archive status paired');
SELECT is((SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum WHERE a.attrelid = 'app.documents'::regclass AND a.attname = 'status'), '''ACTIVE''::app.document_status', 'document status defaults active');
SELECT col_default_is('app', 'documents', 'client_visible', 'false', 'document client visibility defaults false');
SELECT ok((SELECT pg_get_expr(d.adbin, d.adrelid) LIKE '%transaction_timestamp%' FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum WHERE a.attrelid = 'app.documents'::regclass AND a.attname = 'uploaded_at'), 'uploaded_at defaults to database time');

SELECT has_table('app', 'document_links', 'document links table exists');
SELECT columns_are('app', 'document_links', ARRAY[
  'id','document_id','client_id','project_id','task_id','progress_update_id','client_payment_id','payment_request_id','project_expense_id','currency_exchange_id','created_at','created_by'
], 'document links have exact columns');
SELECT fk_ok('app', 'document_links', 'document_id', 'app', 'documents', 'id', 'document link document foreign key exists');
SELECT fk_ok('app', 'document_links', 'client_id', 'app', 'clients', 'id', 'document link client foreign key exists');
SELECT fk_ok('app', 'document_links', 'project_id', 'app', 'projects', 'id', 'document link project foreign key exists');
SELECT fk_ok('app', 'document_links', 'task_id', 'app', 'tasks', 'id', 'document link task foreign key exists');
SELECT fk_ok('app', 'document_links', 'progress_update_id', 'app', 'progress_updates', 'id', 'document link progress update foreign key exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_links_client_payment_fk'), 'finance foreign keys active after Package 12.4');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_links_exactly_one_target_ck'), 'exactly one of eight targets constrained');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_links_finance_targets_disabled_ck'), 'finance targets no longer constrained null after Package 12.4');
SELECT ok(EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'document_uploads'), 'Package 12.2 upload reservation table exists after metadata-only boundary');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name ~ '(thumbnail|current_project_manager_document|current_accountant_document|current_site_supervisor_document)'), 'thumbnail and reserved-role document functions absent');

SELECT * FROM finish();
ROLLBACK;
