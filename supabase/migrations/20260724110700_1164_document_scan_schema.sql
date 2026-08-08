ALTER TYPE app.document_upload_status ADD VALUE IF NOT EXISTS 'SCAN_IN_PROGRESS';
ALTER TYPE app.document_upload_status ADD VALUE IF NOT EXISTS 'SCAN_CLEAN';
ALTER TYPE app.document_upload_status ADD VALUE IF NOT EXISTS 'QUARANTINED';
ALTER TYPE app.document_upload_status ADD VALUE IF NOT EXISTS 'SCAN_FAILED';
ALTER TYPE app.document_upload_status ADD VALUE IF NOT EXISTS 'FINALIZING';
ALTER TYPE app.document_upload_status ADD VALUE IF NOT EXISTS 'FINALIZED';

BEGIN;

CREATE TYPE app.document_scan_status AS ENUM (
  'STARTED',
  'CLEAN',
  'MALICIOUS',
  'ERROR'
);

ALTER TABLE app.document_uploads
  ADD COLUMN final_storage_object_key text,
  ADD COLUMN scan_started_at timestamptz,
  ADD COLUMN scan_completed_at timestamptz,
  ADD COLUMN quarantined_at timestamptz,
  ADD COLUMN finalizing_at timestamptz,
  ADD COLUMN finalized_at timestamptz;

ALTER TABLE app.document_uploads
  DROP CONSTRAINT document_uploads_no_finalized_before_scan_ck;

ALTER TABLE app.document_uploads
  ADD CONSTRAINT document_uploads_final_key_ck CHECK (
    final_storage_object_key IS NULL
    OR final_storage_object_key ~ ('^objects/' || reserved_document_id::text || '/[0-9a-f]{43}$')
  ),
  ADD CONSTRAINT document_uploads_finalized_state_ck CHECK (
    (finalized_document_id IS NULL AND status::text <> 'FINALIZED')
    OR (finalized_document_id = reserved_document_id AND status::text = 'FINALIZED' AND finalized_at IS NOT NULL AND final_storage_object_key IS NOT NULL)
  ),
  ADD CONSTRAINT document_uploads_scan_state_timestamps_ck CHECK (
    (status::text <> 'SCAN_IN_PROGRESS' OR scan_started_at IS NOT NULL)
    AND (status::text <> 'SCAN_CLEAN' OR scan_completed_at IS NOT NULL)
    AND (status::text <> 'SCAN_FAILED' OR scan_completed_at IS NOT NULL)
    AND (status::text <> 'QUARANTINED' OR quarantined_at IS NOT NULL)
    AND (status::text <> 'FINALIZING' OR finalizing_at IS NOT NULL)
  );

CREATE TABLE app.document_scans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_upload_id uuid NOT NULL,
  attempt_number integer NOT NULL,
  status app.document_scan_status NOT NULL,
  scanner_engine varchar(80) NOT NULL,
  scanner_version varchar(120),
  signature_database_version varchar(120),
  started_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  completed_at timestamptz,
  failure_category varchar(80),
  malware_name varchar(200),
  scanned_storage_bucket varchar(100) NOT NULL,
  scanned_storage_object_key text NOT NULL,
  scanned_sha256_hash bytea NOT NULL,
  scanned_file_size_bytes bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CONSTRAINT document_scans_upload_fk FOREIGN KEY (document_upload_id) REFERENCES app.document_uploads(id) ON DELETE RESTRICT,
  CONSTRAINT document_scans_bucket_ck CHECK (scanned_storage_bucket = 'documents-private'),
  CONSTRAINT document_scans_temp_key_ck CHECK (scanned_storage_object_key ~ '^temporary/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[A-Za-z0-9_-]{43}$'),
  CONSTRAINT document_scans_sha256_ck CHECK (octet_length(scanned_sha256_hash) = 32),
  CONSTRAINT document_scans_size_ck CHECK (scanned_file_size_bytes > 0 AND scanned_file_size_bytes <= 26214400),
  CONSTRAINT document_scans_attempt_ck CHECK (attempt_number > 0),
  CONSTRAINT document_scans_upload_attempt_uk UNIQUE (document_upload_id, attempt_number),
  CONSTRAINT document_scans_completion_ck CHECK (
    (status = 'STARTED' AND completed_at IS NULL)
    OR (status IN ('CLEAN','MALICIOUS','ERROR') AND completed_at IS NOT NULL)
  ),
  CONSTRAINT document_scans_malware_name_ck CHECK (malware_name IS NULL OR btrim(malware_name) <> ''),
  CONSTRAINT document_scans_failure_category_ck CHECK (failure_category IS NULL OR failure_category IN ('scanner_unavailable','timeout','network_error','malformed_response','unknown_result','hash_mismatch','object_unavailable','storage_write_failed','database_finalization_failed'))
);

CREATE INDEX document_scans_upload_attempt_idx
  ON app.document_scans(document_upload_id, attempt_number, created_at, id);

CREATE UNIQUE INDEX document_scans_one_started_attempt_idx
  ON app.document_scans(document_upload_id)
  WHERE status = 'STARTED';

CREATE INDEX document_scans_clean_upload_idx
  ON app.document_scans(document_upload_id, completed_at DESC, id DESC)
  WHERE status = 'CLEAN';

CREATE OR REPLACE FUNCTION app.document_scans_guard_history()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document scan history cannot be deleted.';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF current_setting('app.document_scan_context', true) IS DISTINCT FROM 'trusted_scan_result' THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document scan history can only be updated by the trusted scan result path.';
    END IF;
    IF OLD.status <> 'STARTED' OR NEW.status = 'STARTED' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Completed document scan history is immutable.';
    END IF;
    IF OLD.document_upload_id IS DISTINCT FROM NEW.document_upload_id
       OR OLD.attempt_number IS DISTINCT FROM NEW.attempt_number
       OR OLD.scanner_engine IS DISTINCT FROM NEW.scanner_engine
       OR OLD.started_at IS DISTINCT FROM NEW.started_at
       OR OLD.scanned_storage_bucket IS DISTINCT FROM NEW.scanned_storage_bucket
       OR OLD.scanned_storage_object_key IS DISTINCT FROM NEW.scanned_storage_object_key
       OR OLD.scanned_sha256_hash IS DISTINCT FROM NEW.scanned_sha256_hash
       OR OLD.scanned_file_size_bytes IS DISTINCT FROM NEW.scanned_file_size_bytes
       OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document scan identity and scanned object facts are immutable.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER document_scans_guard_history_trg
BEFORE UPDATE OR DELETE ON app.document_scans
FOR EACH ROW EXECUTE FUNCTION app.document_scans_guard_history();

ALTER TABLE app.document_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document_scans FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.document_scans FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
