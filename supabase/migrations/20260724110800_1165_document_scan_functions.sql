BEGIN;

CREATE OR REPLACE FUNCTION app.document_generate_final_object_key(p_document_id uuid)
RETURNS text
LANGUAGE sql
VOLATILE
SET search_path = ''
AS $function$
  SELECT 'objects/' || p_document_id::text || '/' ||
         substring(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') from 1 for 43);
$function$;

CREATE OR REPLACE FUNCTION app.owner_start_document_scan(
  p_actor_auth_subject uuid,
  p_upload_id uuid,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  scan_id uuid,
  upload_id uuid,
  attempt_number integer,
  storage_bucket text,
  storage_object_key text,
  verified_file_size_bytes bigint,
  verified_sha256_hash bytea
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  upload_row app.document_uploads%ROWTYPE;
  next_attempt integer;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF upload_row.id IS NULL OR upload_row.authorized_by <> actor_row.actor_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document scan is not authorized.';
  END IF;
  IF upload_row.status = 'FINALIZED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload is already finalized.';
  END IF;
  IF upload_row.status NOT IN ('AWAITING_SCAN','SCAN_FAILED') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload is not eligible for scanning.';
  END IF;
  IF upload_row.storage_bucket <> 'documents-private'
     OR upload_row.storage_object_key !~ '^temporary/'
     OR upload_row.verified_file_size_bytes IS NULL
     OR upload_row.verified_sha256_hash IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload scan facts are invalid.';
  END IF;

  SELECT count(*)::integer + 1
  INTO next_attempt
  FROM app.document_scans ds
  WHERE ds.document_upload_id = upload_row.id;

  UPDATE app.document_uploads
  SET status = 'SCAN_IN_PROGRESS',
      scan_started_at = transaction_timestamp(),
      scan_completed_at = NULL
  WHERE id = upload_row.id;

  INSERT INTO app.document_scans (
    document_upload_id, attempt_number, status, scanner_engine,
    scanned_storage_bucket, scanned_storage_object_key, scanned_sha256_hash, scanned_file_size_bytes
  )
  VALUES (
    upload_row.id, next_attempt, 'STARTED', 'clamav-compatible-https',
    upload_row.storage_bucket, upload_row.storage_object_key, upload_row.verified_sha256_hash, upload_row.verified_file_size_bytes
  )
  RETURNING id INTO scan_id;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_scan_started', 'document_upload', upload_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('attempt_number', next_attempt));

  upload_id := upload_row.id;
  attempt_number := next_attempt;
  storage_bucket := upload_row.storage_bucket::text;
  storage_object_key := upload_row.storage_object_key;
  verified_file_size_bytes := upload_row.verified_file_size_bytes;
  verified_sha256_hash := upload_row.verified_sha256_hash;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_record_document_scan_result(
  p_actor_auth_subject uuid,
  p_scan_id uuid,
  p_result app.document_scan_status,
  p_scanned_sha256_hash bytea,
  p_scanned_file_size_bytes bigint,
  p_scanner_version text DEFAULT NULL,
  p_signature_database_version text DEFAULT NULL,
  p_failure_category text DEFAULT NULL,
  p_malware_name text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (upload_id uuid, status app.document_upload_status)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  scan_row app.document_scans%ROWTYPE;
  upload_row app.document_uploads%ROWTYPE;
  safe_malware text;
  next_status app.document_upload_status;
  action_name text;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_result NOT IN ('CLEAN','MALICIOUS','ERROR') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document scan result is invalid.';
  END IF;

  SELECT * INTO scan_row FROM app.document_scans WHERE id = p_scan_id FOR UPDATE;
  IF scan_row.id IS NULL OR scan_row.status <> 'STARTED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document scan attempt is not open.';
  END IF;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = scan_row.document_upload_id FOR UPDATE;
  IF upload_row.id IS NULL OR upload_row.authorized_by <> actor_row.actor_user_id OR upload_row.status <> 'SCAN_IN_PROGRESS' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document scan is not authorized.';
  END IF;
  IF scan_row.scanned_storage_bucket <> upload_row.storage_bucket
     OR scan_row.scanned_storage_object_key <> upload_row.storage_object_key
     OR scan_row.scanned_sha256_hash <> upload_row.verified_sha256_hash
     OR scan_row.scanned_file_size_bytes <> upload_row.verified_file_size_bytes
     OR p_scanned_sha256_hash <> upload_row.verified_sha256_hash
     OR p_scanned_file_size_bytes <> upload_row.verified_file_size_bytes THEN
    p_result := 'ERROR';
    p_failure_category := 'hash_mismatch';
  END IF;

  safe_malware := NULLIF(left(regexp_replace(coalesce(p_malware_name, ''), '[\r\n\t"]+', ' ', 'g'), 200), '');
  next_status := CASE p_result WHEN 'CLEAN' THEN 'SCAN_CLEAN' WHEN 'MALICIOUS' THEN 'QUARANTINED' ELSE 'SCAN_FAILED' END;
  action_name := CASE p_result WHEN 'CLEAN' THEN 'document_scan_clean' WHEN 'MALICIOUS' THEN 'document_scan_malicious' ELSE 'document_scan_failed' END;

  PERFORM set_config('app.document_scan_context', 'trusted_scan_result', true);
  UPDATE app.document_scans
  SET status = p_result,
      completed_at = transaction_timestamp(),
      scanner_version = NULLIF(left(coalesce(p_scanner_version, ''), 120), ''),
      signature_database_version = NULLIF(left(coalesce(p_signature_database_version, ''), 120), ''),
      failure_category = CASE WHEN p_result = 'ERROR' THEN coalesce(p_failure_category, 'scanner_unavailable') ELSE NULL END,
      malware_name = CASE WHEN p_result = 'MALICIOUS' THEN safe_malware ELSE NULL END
  WHERE id = scan_row.id;
  PERFORM set_config('app.document_scan_context', '', true);

  UPDATE app.document_uploads
  SET status = next_status,
      scan_completed_at = transaction_timestamp(),
      quarantined_at = CASE WHEN next_status = 'QUARANTINED' THEN transaction_timestamp() ELSE quarantined_at END,
      failure_code = CASE WHEN next_status = 'SCAN_FAILED' THEN coalesce(p_failure_category, 'scanner_unavailable') ELSE failure_code END
  WHERE id = upload_row.id
  RETURNING id, document_uploads.status INTO upload_id, status;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', action_name, 'document_upload', upload_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('attempt_number', scan_row.attempt_number));
  IF p_result = 'MALICIOUS' THEN
    PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_quarantined', 'document_upload', upload_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, '{}'::jsonb);
  END IF;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_prepare_clean_document_finalization(
  p_actor_auth_subject uuid,
  p_upload_id uuid,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  reserved_document_id uuid,
  storage_bucket text,
  temporary_storage_object_key text,
  final_storage_object_key text,
  verified_file_size_bytes bigint,
  verified_sha256_hash bytea,
  verified_mime_type text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  upload_row app.document_uploads%ROWTYPE;
  final_key text;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF upload_row.id IS NULL OR upload_row.authorized_by <> actor_row.actor_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document finalization is not authorized.';
  END IF;
  IF upload_row.status = 'FINALIZED' THEN
    RETURN QUERY SELECT upload_row.id, upload_row.reserved_document_id, upload_row.storage_bucket::text, upload_row.storage_object_key, upload_row.final_storage_object_key, upload_row.verified_file_size_bytes, upload_row.verified_sha256_hash, upload_row.verified_mime_type::text;
    RETURN;
  END IF;
  IF upload_row.status = 'FINALIZING' THEN
    RETURN QUERY SELECT upload_row.id, upload_row.reserved_document_id, upload_row.storage_bucket::text, upload_row.storage_object_key, upload_row.final_storage_object_key, upload_row.verified_file_size_bytes, upload_row.verified_sha256_hash, upload_row.verified_mime_type::text;
    RETURN;
  END IF;
  IF upload_row.status <> 'SCAN_CLEAN' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload does not have a clean scan.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM app.document_scans ds
    WHERE ds.document_upload_id = upload_row.id
      AND ds.status = 'CLEAN'
      AND ds.scanned_storage_bucket = upload_row.storage_bucket
      AND ds.scanned_storage_object_key = upload_row.storage_object_key
      AND ds.scanned_sha256_hash = upload_row.verified_sha256_hash
      AND ds.scanned_file_size_bytes = upload_row.verified_file_size_bytes
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean scan is not bound to this upload.';
  END IF;

  final_key := coalesce(upload_row.final_storage_object_key, app.document_generate_final_object_key(upload_row.reserved_document_id));
  UPDATE app.document_uploads
  SET status = 'FINALIZING',
      finalizing_at = coalesce(finalizing_at, transaction_timestamp()),
      final_storage_object_key = final_key
  WHERE id = upload_row.id
  RETURNING document_uploads.id, document_uploads.reserved_document_id, document_uploads.storage_bucket::text, document_uploads.storage_object_key, document_uploads.final_storage_object_key, document_uploads.verified_file_size_bytes, document_uploads.verified_sha256_hash, document_uploads.verified_mime_type::text
  INTO upload_id, reserved_document_id, storage_bucket, temporary_storage_object_key, final_storage_object_key, verified_file_size_bytes, verified_sha256_hash, verified_mime_type;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_finalize_clean_document_upload(
  p_actor_auth_subject uuid,
  p_upload_id uuid,
  p_verified_final_sha256_hash bytea,
  p_verified_final_file_size_bytes bigint,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (document_id uuid, document_number text, storage_object_key text, status app.document_upload_status)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  upload_row app.document_uploads%ROWTYPE;
  inserted_number text;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF upload_row.id IS NULL OR upload_row.authorized_by <> actor_row.actor_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document finalization is not authorized.';
  END IF;
  IF upload_row.status = 'FINALIZED' THEN
    SELECT d.document_number::text INTO inserted_number FROM app.documents d WHERE d.id = upload_row.finalized_document_id;
    RETURN QUERY SELECT upload_row.finalized_document_id, inserted_number, upload_row.final_storage_object_key, upload_row.status;
    RETURN;
  END IF;
  IF upload_row.status <> 'FINALIZING' OR upload_row.final_storage_object_key IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload is not finalizing.';
  END IF;
  IF p_verified_final_sha256_hash <> upload_row.verified_sha256_hash OR p_verified_final_file_size_bytes <> upload_row.verified_file_size_bytes THEN
    UPDATE app.document_uploads SET status = 'SCAN_FAILED', scan_completed_at = transaction_timestamp(), failure_code = 'storage_write_failed' WHERE id = upload_row.id;
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Final object verification failed.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM app.document_scans ds
    WHERE ds.document_upload_id = upload_row.id
      AND ds.status = 'CLEAN'
      AND ds.scanned_storage_bucket = upload_row.storage_bucket
      AND ds.scanned_storage_object_key = upload_row.storage_object_key
      AND ds.scanned_sha256_hash = upload_row.verified_sha256_hash
      AND ds.scanned_file_size_bytes = upload_row.verified_file_size_bytes
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean scan is not bound to this upload.';
  END IF;
  IF NOT app.document_target_exists(upload_row.client_id, upload_row.project_id, upload_row.task_id, upload_row.progress_update_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document link target is not available.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM app.document_types dt
    WHERE dt.code = upload_row.document_type_code AND dt.is_active
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document type is not active.';
  END IF;

  PERFORM set_config('app.document_metadata_context', 'owner_metadata_mutation', true);
  INSERT INTO app.documents (
    id, storage_bucket, storage_object_key, original_file_name, mime_type,
    file_size_bytes, sha256_hash, document_type_code, status, client_visible, uploaded_by
  )
  VALUES (
    upload_row.reserved_document_id, upload_row.storage_bucket, upload_row.final_storage_object_key,
    upload_row.original_file_name, upload_row.verified_mime_type, upload_row.verified_file_size_bytes,
    upload_row.verified_sha256_hash, upload_row.document_type_code, 'ACTIVE', upload_row.requested_client_visible,
    upload_row.authorized_by
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO app.document_links (document_id, client_id, project_id, task_id, progress_update_id, created_by)
  SELECT upload_row.reserved_document_id, upload_row.client_id, upload_row.project_id, upload_row.task_id, upload_row.progress_update_id, upload_row.authorized_by
  WHERE NOT EXISTS (SELECT 1 FROM app.document_links dl WHERE dl.document_id = upload_row.reserved_document_id);

  IF (SELECT count(*) FROM app.document_links dl WHERE dl.document_id = upload_row.reserved_document_id) <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document link finalization failed.';
  END IF;

  UPDATE app.document_uploads
  SET status = 'FINALIZED',
      finalized_at = coalesce(finalized_at, transaction_timestamp()),
      finalized_document_id = reserved_document_id
  WHERE id = upload_row.id
  RETURNING finalized_document_id, document_uploads.final_storage_object_key, document_uploads.status
  INTO document_id, storage_object_key, status;

  SELECT d.document_number::text INTO document_number FROM app.documents d WHERE d.id = document_id;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_finalized', 'document', document_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_start_document_scan(p_verified_owner_auth_subject uuid, p_upload_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (scan_id uuid, upload_id uuid, attempt_number integer, storage_bucket text, storage_object_key text, verified_file_size_bytes bigint, verified_sha256_hash bytea)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_start_document_scan(p_verified_owner_auth_subject, p_upload_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_record_document_scan_result(p_verified_owner_auth_subject uuid, p_scan_id uuid, p_result app.document_scan_status, p_scanned_sha256_hash bytea, p_scanned_file_size_bytes bigint, p_scanner_version text DEFAULT NULL, p_signature_database_version text DEFAULT NULL, p_failure_category text DEFAULT NULL, p_malware_name text DEFAULT NULL, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (upload_id uuid, status app.document_upload_status)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_record_document_scan_result(p_verified_owner_auth_subject, p_scan_id, p_result, p_scanned_sha256_hash, p_scanned_file_size_bytes, p_scanner_version, p_signature_database_version, p_failure_category, p_malware_name, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_prepare_clean_document_finalization(p_verified_owner_auth_subject uuid, p_upload_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (upload_id uuid, reserved_document_id uuid, storage_bucket text, temporary_storage_object_key text, final_storage_object_key text, verified_file_size_bytes bigint, verified_sha256_hash bytea, verified_mime_type text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_prepare_clean_document_finalization(p_verified_owner_auth_subject, p_upload_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_finalize_clean_document_upload(p_verified_owner_auth_subject uuid, p_upload_id uuid, p_verified_final_sha256_hash bytea, p_verified_final_file_size_bytes bigint, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (document_id uuid, document_number text, storage_object_key text, status app.document_upload_status)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_finalize_clean_document_upload(p_verified_owner_auth_subject, p_upload_id, p_verified_final_sha256_hash, p_verified_final_file_size_bytes, p_request_identifier);
$function$;

COMMIT;
