BEGIN;

-- Stage 12 - Storage Reconciliation Foundation is report-only and non-destructive.

CREATE TYPE app.storage_reconciliation_classification AS ENUM (
  'OK',
  'REVIEW',
  'INVALIDATION_CANDIDATE',
  'ORPHAN_TEMPORARY_CANDIDATE',
  'MISSING_OBJECT',
  'UNEXPECTED_OBJECT',
  'QUARANTINED',
  'PROCESSING_INCOMPLETE',
  'DERIVATIVE_MISMATCH'
);

CREATE TYPE app.storage_reconciliation_recommended_action AS ENUM (
  'NONE',
  'MANUAL_REVIEW',
  'INVALIDATE_RESERVATION',
  'RETRY_EXISTING_WORKFLOW',
  'POLICY_DECISION_REQUIRED'
);

CREATE OR REPLACE FUNCTION app.storage_reconciliation_report()
RETURNS TABLE (
  finding_source text,
  classification app.storage_reconciliation_classification,
  recommended_action app.storage_reconciliation_recommended_action,
  storage_bucket text,
  storage_object_key text,
  upload_id uuid,
  document_id uuid,
  derivative_document_id uuid,
  status text,
  detail_code text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH private_objects AS (
    SELECT so.bucket_id::text AS storage_bucket, so.name::text AS storage_object_key
    FROM storage.objects so
    WHERE so.bucket_id = 'documents-private'
  ),
  upload_findings AS (
    SELECT
      'temporary_upload'::text AS finding_source,
      CASE
        WHEN du.status::text = 'QUARANTINED' THEN 'QUARANTINED'::app.storage_reconciliation_classification
        WHEN du.status::text = 'SCAN_IN_PROGRESS' THEN 'PROCESSING_INCOMPLETE'::app.storage_reconciliation_classification
        WHEN du.status::text = 'SCAN_FAILED' THEN 'PROCESSING_INCOMPLETE'::app.storage_reconciliation_classification
        WHEN du.status::text IN ('FAILED','EXPIRED') AND po.storage_object_key IS NOT NULL THEN 'INVALIDATION_CANDIDATE'::app.storage_reconciliation_classification
        WHEN du.status::text IN ('AUTHORIZED','UPLOADED','VALIDATED') AND du.expires_at <= transaction_timestamp() AND po.storage_object_key IS NOT NULL THEN 'INVALIDATION_CANDIDATE'::app.storage_reconciliation_classification
        WHEN du.status::text IN ('AUTHORIZED','UPLOADED','VALIDATED') AND du.expires_at <= transaction_timestamp() THEN 'REVIEW'::app.storage_reconciliation_classification
        WHEN du.status::text <> 'FINALIZED' AND po.storage_object_key IS NULL THEN 'MISSING_OBJECT'::app.storage_reconciliation_classification
        WHEN du.status::text = 'FINALIZED' AND po.storage_object_key IS NOT NULL THEN 'REVIEW'::app.storage_reconciliation_classification
        ELSE 'OK'::app.storage_reconciliation_classification
      END AS classification,
      CASE
        WHEN du.status::text IN ('QUARANTINED','SCAN_IN_PROGRESS') THEN 'MANUAL_REVIEW'::app.storage_reconciliation_recommended_action
        WHEN du.status::text = 'SCAN_FAILED' THEN 'RETRY_EXISTING_WORKFLOW'::app.storage_reconciliation_recommended_action
        WHEN du.status::text IN ('FAILED','EXPIRED') AND po.storage_object_key IS NOT NULL THEN 'INVALIDATE_RESERVATION'::app.storage_reconciliation_recommended_action
        WHEN du.status::text IN ('AUTHORIZED','UPLOADED','VALIDATED') AND du.expires_at <= transaction_timestamp() AND po.storage_object_key IS NOT NULL THEN 'INVALIDATE_RESERVATION'::app.storage_reconciliation_recommended_action
        WHEN du.status::text IN ('AUTHORIZED','UPLOADED','VALIDATED') AND du.expires_at <= transaction_timestamp() THEN 'MANUAL_REVIEW'::app.storage_reconciliation_recommended_action
        WHEN du.status::text <> 'FINALIZED' AND po.storage_object_key IS NULL THEN 'MANUAL_REVIEW'::app.storage_reconciliation_recommended_action
        WHEN du.status::text = 'FINALIZED' AND po.storage_object_key IS NOT NULL THEN 'POLICY_DECISION_REQUIRED'::app.storage_reconciliation_recommended_action
        ELSE 'NONE'::app.storage_reconciliation_recommended_action
      END AS recommended_action,
      du.storage_bucket::text,
      du.storage_object_key,
      du.id AS upload_id,
      du.finalized_document_id AS document_id,
      NULL::uuid AS derivative_document_id,
      du.status::text AS status,
      CASE
        WHEN du.status::text = 'QUARANTINED' THEN 'quarantined_upload'
        WHEN du.status::text = 'SCAN_IN_PROGRESS' THEN 'scan_in_progress'
        WHEN du.status::text = 'SCAN_FAILED' THEN 'scan_failed'
        WHEN du.status::text IN ('FAILED','EXPIRED') AND po.storage_object_key IS NOT NULL THEN 'failed_or_expired_temporary_object_present'
        WHEN du.status::text IN ('AUTHORIZED','UPLOADED','VALIDATED') AND du.expires_at <= transaction_timestamp() AND po.storage_object_key IS NOT NULL THEN 'expired_reservation_object_present'
        WHEN du.status::text IN ('AUTHORIZED','UPLOADED','VALIDATED') AND du.expires_at <= transaction_timestamp() THEN 'expired_reservation'
        WHEN du.status::text <> 'FINALIZED' AND po.storage_object_key IS NULL THEN 'reservation_object_missing'
        WHEN du.status::text = 'FINALIZED' AND po.storage_object_key IS NOT NULL THEN 'finalized_upload_temporary_object_present'
        ELSE 'temporary_upload_expected_state'
      END AS detail_code
    FROM app.document_uploads du
    LEFT JOIN private_objects po ON po.storage_bucket = du.storage_bucket::text AND po.storage_object_key = du.storage_object_key
  ),
  orphan_temporary_objects AS (
    SELECT
      'temporary_upload'::text,
      'ORPHAN_TEMPORARY_CANDIDATE'::app.storage_reconciliation_classification,
      'POLICY_DECISION_REQUIRED'::app.storage_reconciliation_recommended_action,
      po.storage_bucket,
      po.storage_object_key,
      NULL::uuid,
      NULL::uuid,
      NULL::uuid,
      NULL::text,
      'temporary_object_without_valid_reservation'::text
    FROM private_objects po
    LEFT JOIN app.document_uploads du ON du.storage_bucket::text = po.storage_bucket AND du.storage_object_key = po.storage_object_key
    WHERE po.storage_object_key ~ '^temporary/'
      AND du.id IS NULL
  ),
  document_findings AS (
    SELECT
      'finalized_document'::text,
      CASE WHEN po.storage_object_key IS NULL THEN 'MISSING_OBJECT'::app.storage_reconciliation_classification ELSE 'OK'::app.storage_reconciliation_classification END,
      CASE WHEN po.storage_object_key IS NULL THEN 'MANUAL_REVIEW'::app.storage_reconciliation_recommended_action ELSE 'NONE'::app.storage_reconciliation_recommended_action END,
      d.storage_bucket::text,
      d.storage_object_key,
      NULL::uuid,
      d.id,
      NULL::uuid,
      d.status::text,
      CASE WHEN po.storage_object_key IS NULL THEN 'finalized_document_object_missing' ELSE 'finalized_document_expected_object_present' END
    FROM app.documents d
    LEFT JOIN private_objects po ON po.storage_bucket = d.storage_bucket::text AND po.storage_object_key = d.storage_object_key
  ),
  unexpected_final_objects AS (
    SELECT
      'finalized_document'::text,
      'UNEXPECTED_OBJECT'::app.storage_reconciliation_classification,
      'POLICY_DECISION_REQUIRED'::app.storage_reconciliation_recommended_action,
      po.storage_bucket,
      po.storage_object_key,
      NULL::uuid,
      NULL::uuid,
      NULL::uuid,
      NULL::text,
      'final_object_without_valid_document'::text
    FROM private_objects po
    LEFT JOIN app.documents d ON d.storage_bucket::text = po.storage_bucket AND d.storage_object_key = po.storage_object_key
    WHERE po.storage_object_key LIKE 'objects/%'
      AND d.id IS NULL
  ),
  derivative_findings AS (
    SELECT
      'photograph_derivative'::text,
      CASE
        WHEN did.processing_status IN ('PENDING','PROCESSING') THEN 'PROCESSING_INCOMPLETE'::app.storage_reconciliation_classification
        WHEN did.processing_status = 'FAILED' THEN 'PROCESSING_INCOMPLETE'::app.storage_reconciliation_classification
        WHEN did.processing_status = 'READY' AND (thumb.storage_object_key IS NULL OR preview.storage_object_key IS NULL) THEN 'MISSING_OBJECT'::app.storage_reconciliation_classification
        WHEN did.processing_status = 'READY' AND did.source_sha256_hash IS DISTINCT FROM d.sha256_hash THEN 'DERIVATIVE_MISMATCH'::app.storage_reconciliation_classification
        ELSE 'OK'::app.storage_reconciliation_classification
      END,
      CASE
        WHEN did.processing_status IN ('PENDING','PROCESSING','FAILED') THEN 'RETRY_EXISTING_WORKFLOW'::app.storage_reconciliation_recommended_action
        WHEN did.processing_status = 'READY' AND (thumb.storage_object_key IS NULL OR preview.storage_object_key IS NULL) THEN 'MANUAL_REVIEW'::app.storage_reconciliation_recommended_action
        WHEN did.processing_status = 'READY' AND did.source_sha256_hash IS DISTINCT FROM d.sha256_hash THEN 'MANUAL_REVIEW'::app.storage_reconciliation_recommended_action
        ELSE 'NONE'::app.storage_reconciliation_recommended_action
      END,
      'documents-private'::text,
      did.thumbnail_storage_object_key,
      NULL::uuid,
      d.id,
      did.document_id,
      did.processing_status::text,
      CASE
        WHEN did.processing_status IN ('PENDING','PROCESSING') THEN 'derivative_processing_incomplete'
        WHEN did.processing_status = 'FAILED' THEN 'derivative_failed'
        WHEN did.processing_status = 'READY' AND thumb.storage_object_key IS NULL AND preview.storage_object_key IS NULL THEN 'ready_derivatives_both_objects_missing'
        WHEN did.processing_status = 'READY' AND thumb.storage_object_key IS NULL THEN 'ready_derivative_thumbnail_missing'
        WHEN did.processing_status = 'READY' AND preview.storage_object_key IS NULL THEN 'ready_derivative_preview_missing'
        WHEN did.processing_status = 'READY' AND did.source_sha256_hash IS DISTINCT FROM d.sha256_hash THEN 'derivative_source_hash_mismatch'
        ELSE 'ready_derivatives_expected_objects_present'
      END
    FROM app.document_image_derivatives did
    LEFT JOIN app.documents d ON d.id = did.document_id
    LEFT JOIN private_objects thumb ON thumb.storage_bucket = 'documents-private' AND thumb.storage_object_key = did.thumbnail_storage_object_key
    LEFT JOIN private_objects preview ON preview.storage_bucket = 'documents-private' AND preview.storage_object_key = did.preview_storage_object_key
  ),
  unmatched_derivative_objects AS (
    SELECT
      'photograph_derivative'::text,
      'UNEXPECTED_OBJECT'::app.storage_reconciliation_classification,
      'POLICY_DECISION_REQUIRED'::app.storage_reconciliation_recommended_action,
      po.storage_bucket,
      po.storage_object_key,
      NULL::uuid,
      NULL::uuid,
      NULL::uuid,
      NULL::text,
      'derivative_object_without_expected_record'::text
    FROM private_objects po
    LEFT JOIN app.document_image_derivatives did
      ON po.storage_object_key IN (did.thumbnail_storage_object_key, did.preview_storage_object_key)
    WHERE po.storage_object_key ~ '^derivatives/'
      AND did.document_id IS NULL
  )
  SELECT * FROM upload_findings
  UNION ALL SELECT * FROM orphan_temporary_objects
  UNION ALL SELECT * FROM document_findings
  UNION ALL SELECT * FROM unexpected_final_objects
  UNION ALL SELECT * FROM derivative_findings
  UNION ALL SELECT * FROM unmatched_derivative_objects
  ORDER BY finding_source, storage_object_key NULLS LAST, upload_id NULLS LAST, document_id NULLS LAST, detail_code;
$function$;

CREATE OR REPLACE FUNCTION public.server_storage_reconciliation_report()
RETURNS TABLE (
  finding_source text,
  classification app.storage_reconciliation_classification,
  recommended_action app.storage_reconciliation_recommended_action,
  storage_bucket text,
  storage_object_key text,
  upload_id uuid,
  document_id uuid,
  derivative_document_id uuid,
  status text,
  detail_code text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.storage_reconciliation_report();
$function$;

REVOKE ALL ON FUNCTION app.storage_reconciliation_report() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_storage_reconciliation_report() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_storage_reconciliation_report() TO service_role;

COMMIT;
