BEGIN;

CREATE TYPE app.document_upload_status AS ENUM (
  'AUTHORIZED',
  'UPLOADED',
  'VALIDATED',
  'AWAITING_SCAN',
  'FAILED',
  'EXPIRED'
);

CREATE TABLE app.document_uploads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reserved_document_id uuid NOT NULL DEFAULT gen_random_uuid(),
  storage_bucket varchar(100) NOT NULL DEFAULT 'documents-private',
  storage_object_key text NOT NULL,
  original_file_name varchar(255) NOT NULL,
  declared_mime_type varchar(150) NOT NULL,
  verified_mime_type varchar(150),
  verified_file_size_bytes bigint,
  verified_sha256_hash bytea,
  document_type_code varchar(50) NOT NULL,
  requested_client_visible boolean NOT NULL DEFAULT false,
  client_id uuid,
  project_id uuid,
  task_id uuid,
  progress_update_id uuid,
  status app.document_upload_status NOT NULL DEFAULT 'AUTHORIZED',
  authorized_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  authorized_by uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  uploaded_at timestamptz,
  validated_at timestamptz,
  awaiting_scan_at timestamptz,
  failed_at timestamptz,
  expired_at timestamptz,
  invalidated_at timestamptz,
  failure_code varchar(80),
  finalized_document_id uuid,
  CONSTRAINT document_uploads_reserved_document_uk UNIQUE (reserved_document_id),
  CONSTRAINT document_uploads_storage_object_key_uk UNIQUE (storage_object_key),
  CONSTRAINT document_uploads_bucket_ck CHECK (storage_bucket = 'documents-private'),
  CONSTRAINT document_uploads_temp_key_ck CHECK (storage_object_key ~ '^temporary/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[A-Za-z0-9_-]{43}$'),
  CONSTRAINT document_uploads_original_file_name_ck CHECK (btrim(original_file_name) <> '' AND original_file_name !~ '[/\\]'),
  CONSTRAINT document_uploads_declared_mime_type_ck CHECK (declared_mime_type IN ('application/pdf','image/jpeg','image/png','image/webp')),
  CONSTRAINT document_uploads_verified_mime_type_ck CHECK (verified_mime_type IS NULL OR verified_mime_type IN ('application/pdf','image/jpeg','image/png','image/webp')),
  CONSTRAINT document_uploads_size_ck CHECK (verified_file_size_bytes IS NULL OR (verified_file_size_bytes > 0 AND verified_file_size_bytes <= 26214400)),
  CONSTRAINT document_uploads_sha256_ck CHECK (verified_sha256_hash IS NULL OR octet_length(verified_sha256_hash) = 32),
  CONSTRAINT document_uploads_type_fk FOREIGN KEY (document_type_code) REFERENCES app.document_types(code) ON DELETE RESTRICT,
  CONSTRAINT document_uploads_client_fk FOREIGN KEY (client_id) REFERENCES app.clients(id) ON DELETE RESTRICT,
  CONSTRAINT document_uploads_project_fk FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT document_uploads_task_fk FOREIGN KEY (task_id) REFERENCES app.tasks(id) ON DELETE RESTRICT,
  CONSTRAINT document_uploads_progress_update_fk FOREIGN KEY (progress_update_id) REFERENCES app.progress_updates(id) ON DELETE RESTRICT,
  CONSTRAINT document_uploads_authorized_by_fk FOREIGN KEY (authorized_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT document_uploads_finalized_document_fk FOREIGN KEY (finalized_document_id) REFERENCES app.documents(id) ON DELETE RESTRICT,
  CONSTRAINT document_uploads_one_target_ck CHECK (num_nonnulls(client_id, project_id, task_id, progress_update_id) = 1),
  CONSTRAINT document_uploads_terminal_timestamps_ck CHECK (
    (status <> 'FAILED' OR failed_at IS NOT NULL)
    AND (status <> 'EXPIRED' OR expired_at IS NOT NULL)
    AND (status <> 'AWAITING_SCAN' OR awaiting_scan_at IS NOT NULL)
  ),
  CONSTRAINT document_uploads_no_finalized_before_scan_ck CHECK (finalized_document_id IS NULL)
);

CREATE INDEX document_uploads_authorized_by_status_idx
  ON app.document_uploads(authorized_by, status, expires_at, id);

CREATE INDEX document_uploads_expiry_idx
  ON app.document_uploads(expires_at, status, id)
  WHERE status IN ('AUTHORIZED','UPLOADED','VALIDATED');

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents-private',
  'documents-private',
  false,
  26214400,
  ARRAY['application/pdf','image/jpeg','image/png','image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = false,
    file_size_limit = 26214400,
    allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png','image/webp']::text[];

ALTER TABLE app.document_uploads ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document_uploads FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.document_uploads FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
