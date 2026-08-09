BEGIN;
SELECT plan(34);

SELECT results_eq($$ SELECT code, name, default_client_visible, is_active FROM app.document_types WHERE code IN ('PROGRESS_PHOTOGRAPH','TASK_ATTACHMENT') ORDER BY code $$, $$ VALUES ('PROGRESS_PHOTOGRAPH'::varchar,'Progress Photograph'::varchar,false,true),('TASK_ATTACHMENT'::varchar,'Task Attachment'::varchar,false,true) $$, 'photograph document types seeded private by default');
SELECT ok(NOT EXISTS (SELECT 1 FROM app.document_types WHERE code='SITE_PHOTOGRAPH'), 'SITE_PHOTOGRAPH not added');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='document_image_processing_status' ORDER BY enumsortorder $$, $$ VALUES ('PENDING'::name),('PROCESSING'::name),('READY'::name),('FAILED'::name) $$, 'processing status enum exact');
SELECT has_table('app','document_image_derivatives','image derivative table exists');
SELECT columns_are('app','document_image_derivatives',ARRAY[
  'document_id','processing_status','source_sha256_hash','source_width','source_height',
  'thumbnail_storage_object_key','thumbnail_file_size_bytes','thumbnail_sha256_hash','thumbnail_width','thumbnail_height',
  'preview_storage_object_key','preview_file_size_bytes','preview_sha256_hash','preview_width','preview_height',
  'processor_version','failure_code','processing_started_at','processing_completed_at','processing_failed_at','created_at','updated_at'
], 'image derivative columns exact');
SELECT col_is_pk('app','document_image_derivatives','document_id','document id is primary key');
SELECT fk_ok('app','document_image_derivatives','document_id','app','documents','id','document FK exists');
SELECT col_type_is('app','document_image_derivatives','processing_status','app.document_image_processing_status','status type exact');
SELECT col_type_is('app','document_image_derivatives','source_sha256_hash','bytea','source hash bytea');
SELECT col_type_is('app','document_image_derivatives','thumbnail_sha256_hash','bytea','thumbnail hash bytea');
SELECT col_type_is('app','document_image_derivatives','preview_sha256_hash','bytea','preview hash bytea');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_source_hash_ck'), 'source SHA-256 constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_thumb_hash_ck'), 'thumbnail SHA-256 constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_preview_hash_ck'), 'preview SHA-256 constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_source_dimensions_ck'), 'source dimensions constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_thumb_dimensions_ck'), 'thumbnail dimensions constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_preview_dimensions_ck'), 'preview dimensions constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_thumb_key_ck'), 'thumbnail key namespace constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_preview_key_ck'), 'preview key namespace constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_failure_code_ck'), 'controlled failure codes constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_image_derivatives_state_ck'), 'processing state constrained');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='app' AND indexname='document_image_derivatives_thumb_key_uk'), 'thumbnail key unique when present');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='app' AND indexname='document_image_derivatives_preview_key_uk'), 'preview key unique when present');
SELECT ok((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='document_image_derivatives_source_dimensions_ck') ILIKE '%6000%' AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='document_image_derivatives_source_dimensions_ck') ILIKE '%12000000%', '6000 dimension and 12MP limits present');
SELECT ok((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='document_image_derivatives_thumb_dimensions_ck') ILIKE '%320%', '320 thumbnail bound present');
SELECT ok((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='document_image_derivatives_preview_dimensions_ck') ILIKE '%1600%', '1600 preview bound present');
SELECT ok((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='document_image_derivatives_failure_code_ck') ILIKE '%animated_image_unsupported%', 'animated WebP failure code present');
SELECT columns_are('app','documents',ARRAY['id','document_number','storage_bucket','storage_object_key','original_file_name','mime_type','file_size_bytes','sha256_hash','document_type_code','status','client_visible','notes','uploaded_at','uploaded_by','archived_at','archived_by'], 'Package 12.1 documents schema preserved');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%document_image%', 'current_account unchanged');
SELECT has_function('public','server_owner_prepare_document_image_processing',ARRAY['uuid','uuid','text'],'prepare gateway exists');
SELECT has_function('public','server_owner_complete_document_image_processing',ARRAY['uuid','uuid','bytea','integer','integer','bigint','bytea','integer','integer','bigint','bytea','integer','integer','text','text'],'complete gateway exists');
SELECT has_function('public','server_owner_fail_document_image_processing',ARRAY['uuid','uuid','text','text'],'failure gateway exists');
SELECT has_function('public','server_authorize_document_image_access',ARRAY['uuid','uuid','text','text'],'derivative authorization gateway exists');
SELECT ok((SELECT pg_get_functiondef('app.document_image_generate_derivative_token()'::regprocedure)) ILIKE '%gen_random_uuid%', 'derivative keys are server-generated opaque values');

SELECT * FROM finish();
ROLLBACK;
