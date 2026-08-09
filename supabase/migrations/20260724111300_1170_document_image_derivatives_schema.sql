BEGIN;

INSERT INTO app.document_types (code, name, default_client_visible, is_active)
VALUES
  ('PROGRESS_PHOTOGRAPH', 'Progress Photograph', false, true),
  ('TASK_ATTACHMENT', 'Task Attachment', false, true)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    default_client_visible = false,
    is_active = true;

CREATE TYPE app.document_image_processing_status AS ENUM (
  'PENDING',
  'PROCESSING',
  'READY',
  'FAILED'
);

CREATE TABLE app.document_image_derivatives (
  document_id uuid PRIMARY KEY,
  processing_status app.document_image_processing_status NOT NULL DEFAULT 'PENDING',
  source_sha256_hash bytea,
  source_width integer,
  source_height integer,
  thumbnail_storage_object_key text,
  thumbnail_file_size_bytes bigint,
  thumbnail_sha256_hash bytea,
  thumbnail_width integer,
  thumbnail_height integer,
  preview_storage_object_key text,
  preview_file_size_bytes bigint,
  preview_sha256_hash bytea,
  preview_width integer,
  preview_height integer,
  processor_version varchar(80),
  failure_code varchar(80),
  processing_started_at timestamptz,
  processing_completed_at timestamptz,
  processing_failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CONSTRAINT document_image_derivatives_document_fk FOREIGN KEY (document_id) REFERENCES app.documents(id) ON DELETE RESTRICT,
  CONSTRAINT document_image_derivatives_source_hash_ck CHECK (source_sha256_hash IS NULL OR octet_length(source_sha256_hash) = 32),
  CONSTRAINT document_image_derivatives_thumb_hash_ck CHECK (thumbnail_sha256_hash IS NULL OR octet_length(thumbnail_sha256_hash) = 32),
  CONSTRAINT document_image_derivatives_preview_hash_ck CHECK (preview_sha256_hash IS NULL OR octet_length(preview_sha256_hash) = 32),
  CONSTRAINT document_image_derivatives_source_dimensions_ck CHECK (
    (source_width IS NULL AND source_height IS NULL)
    OR (source_width > 0 AND source_height > 0 AND source_width <= 6000 AND source_height <= 6000 AND (source_width::bigint * source_height::bigint) <= 12000000)
  ),
  CONSTRAINT document_image_derivatives_thumb_dimensions_ck CHECK (
    (thumbnail_width IS NULL AND thumbnail_height IS NULL)
    OR (thumbnail_width > 0 AND thumbnail_height > 0 AND thumbnail_width <= 320 AND thumbnail_height <= 320)
  ),
  CONSTRAINT document_image_derivatives_preview_dimensions_ck CHECK (
    (preview_width IS NULL AND preview_height IS NULL)
    OR (preview_width > 0 AND preview_height > 0 AND preview_width <= 1600 AND preview_height <= 1600)
  ),
  CONSTRAINT document_image_derivatives_thumb_size_ck CHECK (thumbnail_file_size_bytes IS NULL OR thumbnail_file_size_bytes > 0),
  CONSTRAINT document_image_derivatives_preview_size_ck CHECK (preview_file_size_bytes IS NULL OR preview_file_size_bytes > 0),
  CONSTRAINT document_image_derivatives_thumb_key_ck CHECK (
    thumbnail_storage_object_key IS NULL
    OR thumbnail_storage_object_key ~ ('^derivatives/' || document_id::text || '/[0-9a-f]{43}/thumbnail[.]webp$')
  ),
  CONSTRAINT document_image_derivatives_preview_key_ck CHECK (
    preview_storage_object_key IS NULL
    OR preview_storage_object_key ~ ('^derivatives/' || document_id::text || '/[0-9a-f]{43}/preview[.]webp$')
  ),
  CONSTRAINT document_image_derivatives_failure_code_ck CHECK (
    failure_code IS NULL OR failure_code IN (
      'unsupported_mime',
      'not_photograph_type',
      'original_unavailable',
      'original_hash_mismatch',
      'decode_failed',
      'dimensions_unavailable',
      'source_dimensions_exceeded',
      'decoded_pixels_exceeded',
      'animated_image_unsupported',
      'processor_timeout',
      'processor_error',
      'derivative_upload_failed',
      'derivative_verify_failed'
    )
  ),
  CONSTRAINT document_image_derivatives_state_ck CHECK (
    (
      processing_status = 'PENDING'
      AND processing_completed_at IS NULL
      AND processing_failed_at IS NULL
    )
    OR (
      processing_status = 'PROCESSING'
      AND processing_started_at IS NOT NULL
      AND processing_completed_at IS NULL
      AND processing_failed_at IS NULL
      AND thumbnail_storage_object_key IS NOT NULL
      AND preview_storage_object_key IS NOT NULL
    )
    OR (
      processing_status = 'READY'
      AND source_sha256_hash IS NOT NULL
      AND source_width IS NOT NULL
      AND source_height IS NOT NULL
      AND thumbnail_storage_object_key IS NOT NULL
      AND thumbnail_file_size_bytes IS NOT NULL
      AND thumbnail_sha256_hash IS NOT NULL
      AND thumbnail_width IS NOT NULL
      AND thumbnail_height IS NOT NULL
      AND preview_storage_object_key IS NOT NULL
      AND preview_file_size_bytes IS NOT NULL
      AND preview_sha256_hash IS NOT NULL
      AND preview_width IS NOT NULL
      AND preview_height IS NOT NULL
      AND processor_version IS NOT NULL
      AND processing_completed_at IS NOT NULL
      AND processing_failed_at IS NULL
      AND failure_code IS NULL
    )
    OR (
      processing_status = 'FAILED'
      AND failure_code IS NOT NULL
      AND processing_failed_at IS NOT NULL
      AND processing_completed_at IS NULL
      AND thumbnail_file_size_bytes IS NULL
      AND thumbnail_sha256_hash IS NULL
      AND thumbnail_width IS NULL
      AND thumbnail_height IS NULL
      AND preview_file_size_bytes IS NULL
      AND preview_sha256_hash IS NULL
      AND preview_width IS NULL
      AND preview_height IS NULL
    )
  )
);

CREATE UNIQUE INDEX document_image_derivatives_thumb_key_uk
  ON app.document_image_derivatives(thumbnail_storage_object_key)
  WHERE thumbnail_storage_object_key IS NOT NULL;

CREATE UNIQUE INDEX document_image_derivatives_preview_key_uk
  ON app.document_image_derivatives(preview_storage_object_key)
  WHERE preview_storage_object_key IS NOT NULL;

CREATE INDEX document_image_derivatives_status_idx
  ON app.document_image_derivatives(processing_status, updated_at DESC, document_id);

CREATE OR REPLACE FUNCTION app.document_image_derivatives_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  NEW.updated_at := transaction_timestamp();
  RETURN NEW;
END
$function$;

CREATE TRIGGER document_image_derivatives_touch_updated_at_trg
BEFORE UPDATE ON app.document_image_derivatives
FOR EACH ROW EXECUTE FUNCTION app.document_image_derivatives_touch_updated_at();

ALTER TABLE app.document_image_derivatives ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document_image_derivatives FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.document_image_derivatives FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_image_derivatives_touch_updated_at() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
