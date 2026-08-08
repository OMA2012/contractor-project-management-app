BEGIN;

DROP FUNCTION public.server_owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text);
DROP FUNCTION app.owner_reserve_document_upload(uuid, text, text, text, varchar(50), boolean, uuid, uuid, uuid, uuid, text);

CREATE OR REPLACE FUNCTION app.document_finance_target_scope(
  p_client_payment_id uuid DEFAULT NULL,
  p_payment_request_id uuid DEFAULT NULL,
  p_project_expense_id uuid DEFAULT NULL,
  p_currency_exchange_id uuid DEFAULT NULL
)
RETURNS TABLE (
  target_kind text,
  target_exists boolean,
  project_id uuid,
  client_id uuid,
  financial_event_id uuid,
  event_status text,
  transaction_status text,
  is_client_submitted boolean,
  submitted_by_client_user_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF num_nonnulls(p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id) <> 1 THEN
    RETURN QUERY SELECT NULL::text, false, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::boolean, NULL::uuid;
    RETURN;
  END IF;

  IF p_client_payment_id IS NOT NULL THEN
    RETURN QUERY
    SELECT 'client_payment', true, cp.project_id, cp.client_id, cp.financial_event_id, fe.status::text, ft.status::text, cp.is_client_submitted, cp.submitted_by_client_user_id
    FROM app.client_payments cp
    JOIN app.projects p ON p.id = cp.project_id
    JOIN app.financial_events fe ON fe.id = cp.financial_event_id
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    WHERE cp.id = p_client_payment_id
      AND p.client_id = cp.client_id
      AND p.archived_at IS NULL;
    IF FOUND THEN RETURN; END IF;
  ELSIF p_payment_request_id IS NOT NULL THEN
    RETURN QUERY
    SELECT 'payment_request', true, pr.project_id, pr.client_id, NULL::uuid, pr.status::text, NULL::text, NULL::boolean, NULL::uuid
    FROM app.payment_requests pr
    JOIN app.projects p ON p.id = pr.project_id
    WHERE pr.id = p_payment_request_id
      AND p.client_id = pr.client_id
      AND p.archived_at IS NULL;
    IF FOUND THEN RETURN; END IF;
  ELSIF p_project_expense_id IS NOT NULL THEN
    RETURN QUERY
    SELECT 'project_expense', true, pe.project_id, p.client_id, pe.financial_event_id, fe.status::text, ft.status::text, NULL::boolean, NULL::uuid
    FROM app.project_expenses pe
    JOIN app.projects p ON p.id = pe.project_id
    JOIN app.financial_events fe ON fe.id = pe.financial_event_id
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    WHERE pe.id = p_project_expense_id
      AND fe.project_id = pe.project_id
      AND fe.client_id = p.client_id
      AND p.archived_at IS NULL;
    IF FOUND THEN RETURN; END IF;
  ELSE
    RETURN QUERY
    SELECT 'currency_exchange', true, fe.project_id, fe.client_id, ce.financial_event_id, fe.status::text, ft.status::text, NULL::boolean, NULL::uuid
    FROM app.currency_exchanges ce
    JOIN app.financial_events fe ON fe.id = ce.financial_event_id
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    LEFT JOIN app.projects p ON p.id = fe.project_id
    WHERE ce.id = p_currency_exchange_id
      AND fe.event_type = 'CURRENCY_EXCHANGE'
      AND (
        (fe.project_id IS NULL AND fe.client_id IS NULL)
        OR (p.id IS NOT NULL AND p.client_id = fe.client_id AND p.archived_at IS NULL)
      );
    IF FOUND THEN RETURN; END IF;
  END IF;

  RETURN QUERY SELECT NULL::text, false, NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::boolean, NULL::uuid;
END
$function$;

CREATE OR REPLACE FUNCTION app.document_finance_type_allowed(
  p_document_type_code varchar(50),
  p_requested_client_visible boolean,
  p_client_payment_id uuid DEFAULT NULL,
  p_payment_request_id uuid DEFAULT NULL,
  p_project_expense_id uuid DEFAULT NULL,
  p_currency_exchange_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  scope_row record;
BEGIN
  SELECT * INTO scope_row
  FROM app.document_finance_target_scope(p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id);
  IF NOT coalesce(scope_row.target_exists, false) THEN
    RETURN false;
  END IF;
  IF scope_row.target_kind = 'client_payment' THEN
    RETURN p_document_type_code IN ('GENERAL','PAYMENT_RECEIPT','BANK_TRANSFER_EVIDENCE');
  ELSIF scope_row.target_kind = 'payment_request' THEN
    RETURN p_document_type_code IN ('GENERAL','PAYMENT_RECEIPT','BANK_TRANSFER_EVIDENCE');
  ELSIF scope_row.target_kind = 'project_expense' THEN
    RETURN NOT coalesce(p_requested_client_visible, false)
      AND p_document_type_code IN ('GENERAL','SUPPLIER_INVOICE','EXPENSE_RECEIPT');
  ELSIF scope_row.target_kind = 'currency_exchange' THEN
    RETURN NOT coalesce(p_requested_client_visible, false)
      AND p_document_type_code IN ('GENERAL','PAYMENT_RECEIPT','BANK_TRANSFER_EVIDENCE');
  END IF;
  RETURN false;
END
$function$;

CREATE OR REPLACE FUNCTION app.document_target_exists(
  p_client_id uuid,
  p_project_id uuid,
  p_task_id uuid,
  p_progress_update_id uuid,
  p_client_payment_id uuid DEFAULT NULL,
  p_payment_request_id uuid DEFAULT NULL,
  p_project_expense_id uuid DEFAULT NULL,
  p_currency_exchange_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN num_nonnulls(p_client_id, p_project_id, p_task_id, p_progress_update_id, p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id) <> 1 THEN false
    WHEN p_client_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.clients c WHERE c.id = p_client_id AND c.is_active AND c.archived_at IS NULL)
    WHEN p_project_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.projects p WHERE p.id = p_project_id AND p.archived_at IS NULL)
    WHEN p_task_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.tasks t JOIN app.projects p ON p.id = t.project_id WHERE t.id = p_task_id AND t.is_active AND p.archived_at IS NULL)
    WHEN p_progress_update_id IS NOT NULL THEN EXISTS (SELECT 1 FROM app.progress_updates pu JOIN app.projects p ON p.id = pu.project_id WHERE pu.id = p_progress_update_id AND pu.archived_at IS NULL AND p.archived_at IS NULL)
    ELSE EXISTS (
      SELECT 1
      FROM app.document_finance_target_scope(p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id) s
      WHERE s.target_exists
    )
  END;
$function$;

CREATE OR REPLACE FUNCTION app.owner_reserve_document_upload(
  p_actor_auth_subject uuid,
  p_storage_object_token text,
  p_original_file_name text,
  p_declared_mime_type text,
  p_document_type_code varchar(50),
  p_requested_client_visible boolean DEFAULT false,
  p_client_id uuid DEFAULT NULL,
  p_project_id uuid DEFAULT NULL,
  p_task_id uuid DEFAULT NULL,
  p_progress_update_id uuid DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_client_payment_id uuid DEFAULT NULL,
  p_payment_request_id uuid DEFAULT NULL,
  p_project_expense_id uuid DEFAULT NULL,
  p_currency_exchange_id uuid DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  reserved_document_id uuid,
  storage_bucket text,
  storage_object_key text,
  expires_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  new_upload_id uuid := gen_random_uuid();
  new_document_id uuid := gen_random_uuid();
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF p_storage_object_token IS NULL OR p_storage_object_token !~ '^[A-Za-z0-9_-]{43}$' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid document upload token.';
  END IF;
  IF p_document_type_code !~ '^[A-Z][A-Z0-9_]{0,49}$' OR NOT EXISTS (SELECT 1 FROM app.document_types dt WHERE dt.code = p_document_type_code AND dt.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document type is not available.';
  END IF;
  IF NOT app.document_target_exists(p_client_id, p_project_id, p_task_id, p_progress_update_id, p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document link target is not available.';
  END IF;
  IF num_nonnulls(p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id) = 1
     AND NOT app.document_finance_type_allowed(p_document_type_code, p_requested_client_visible, p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document type is not allowed for this financial target.';
  END IF;
  PERFORM app.document_validate_upload_request(p_original_file_name, p_declared_mime_type);

  INSERT INTO app.document_uploads (
    id, reserved_document_id, storage_object_key, original_file_name, declared_mime_type,
    document_type_code, requested_client_visible, client_id, project_id, task_id,
    progress_update_id, client_payment_id, payment_request_id, project_expense_id,
    currency_exchange_id, authorized_by, expires_at
  )
  VALUES (
    new_upload_id, new_document_id, 'temporary/' || new_upload_id::text || '/' || p_storage_object_token,
    btrim(p_original_file_name), p_declared_mime_type, p_document_type_code, coalesce(p_requested_client_visible, false),
    p_client_id, p_project_id, p_task_id, p_progress_update_id, p_client_payment_id, p_payment_request_id,
    p_project_expense_id, p_currency_exchange_id, actor_row.actor_user_id,
    transaction_timestamp() + interval '5 minutes'
  )
  RETURNING id, document_uploads.reserved_document_id, document_uploads.storage_bucket::text, document_uploads.storage_object_key, document_uploads.expires_at
  INTO upload_id, reserved_document_id, storage_bucket, storage_object_key, expires_at;

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_upload_authorized', 'document_upload', upload_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('document_type_code', p_document_type_code));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_reserve_transfer_evidence_upload(
  p_verified_client_auth_subject uuid,
  p_storage_object_token text,
  p_original_file_name text,
  p_declared_mime_type text,
  p_client_payment_id uuid,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  reserved_document_id uuid,
  storage_bucket text,
  storage_object_key text,
  expires_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  client_ctx record;
  scope_row record;
  new_upload_id uuid := gen_random_uuid();
  new_document_id uuid := gen_random_uuid();
BEGIN
  SELECT c.id AS client_id, c.portal_user_id AS user_id, u.auth_subject AS auth_subject
  INTO client_ctx
  FROM app.users u
  JOIN app.clients c ON c.portal_user_id = u.id
  WHERE u.auth_subject = p_verified_client_auth_subject
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND EXISTS (SELECT 1 FROM app.user_roles ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
  LIMIT 1;
  IF client_ctx.client_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Client operation denied.';
  END IF;
  IF p_storage_object_token IS NULL OR p_storage_object_token !~ '^[A-Za-z0-9_-]{43}$' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid document upload token.';
  END IF;
  PERFORM app.document_validate_upload_request(p_original_file_name, p_declared_mime_type);
  SELECT * INTO scope_row
  FROM app.document_finance_target_scope(p_client_payment_id, NULL, NULL, NULL);
  IF NOT coalesce(scope_row.target_exists, false)
     OR scope_row.target_kind <> 'client_payment'
     OR scope_row.client_id IS DISTINCT FROM client_ctx.client_id
     OR NOT scope_row.is_client_submitted
     OR scope_row.submitted_by_client_user_id IS DISTINCT FROM client_ctx.user_id
     OR scope_row.event_status <> 'SUBMITTED'
     OR scope_row.transaction_status <> 'SUBMITTED' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Client operation denied.';
  END IF;

  INSERT INTO app.document_uploads (
    id, reserved_document_id, storage_object_key, original_file_name, declared_mime_type,
    document_type_code, requested_client_visible, client_payment_id, authorized_by, expires_at
  )
  VALUES (
    new_upload_id, new_document_id, 'temporary/' || new_upload_id::text || '/' || p_storage_object_token,
    btrim(p_original_file_name), p_declared_mime_type, 'BANK_TRANSFER_EVIDENCE', false,
    p_client_payment_id, client_ctx.user_id, transaction_timestamp() + interval '5 minutes'
  )
  RETURNING id, document_uploads.reserved_document_id, document_uploads.storage_bucket::text, document_uploads.storage_object_key, document_uploads.expires_at
  INTO upload_id, reserved_document_id, storage_bucket, storage_object_key, expires_at;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_document_upload_storage_context(
  p_actor_auth_subject uuid,
  p_upload_id uuid
)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  RETURN QUERY
  SELECT du.id, du.status, du.storage_bucket::text, du.storage_object_key, du.expires_at
  FROM app.document_uploads du
  WHERE du.id = p_upload_id
    AND du.authorized_by = actor_row.actor_user_id
    AND du.finalized_document_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload is not authorized.';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_transfer_evidence_upload_storage_context(
  p_verified_client_auth_subject uuid,
  p_upload_id uuid
)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  client_ctx record;
  upload_row app.document_uploads%ROWTYPE;
  scope_row record;
BEGIN
  SELECT c.id AS client_id, c.portal_user_id AS user_id
  INTO client_ctx
  FROM app.users u
  JOIN app.clients c ON c.portal_user_id = u.id
  WHERE u.auth_subject = p_verified_client_auth_subject
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND EXISTS (SELECT 1 FROM app.user_roles ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
  LIMIT 1;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id;
  IF client_ctx.client_id IS NULL
     OR upload_row.id IS NULL
     OR upload_row.authorized_by IS DISTINCT FROM client_ctx.user_id
     OR upload_row.document_type_code <> 'BANK_TRANSFER_EVIDENCE'
     OR upload_row.requested_client_visible
     OR upload_row.client_payment_id IS NULL
     OR num_nonnulls(upload_row.client_id, upload_row.project_id, upload_row.task_id, upload_row.progress_update_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id) <> 0
     OR upload_row.finalized_document_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload is not authorized.';
  END IF;
  SELECT * INTO scope_row FROM app.document_finance_target_scope(upload_row.client_payment_id, NULL, NULL, NULL);
  IF NOT coalesce(scope_row.target_exists, false)
     OR scope_row.client_id IS DISTINCT FROM client_ctx.client_id
     OR NOT scope_row.is_client_submitted
     OR scope_row.submitted_by_client_user_id IS DISTINCT FROM client_ctx.user_id
     OR scope_row.event_status <> 'SUBMITTED'
     OR scope_row.transaction_status <> 'SUBMITTED' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload is not authorized.';
  END IF;
  RETURN QUERY SELECT upload_row.id, upload_row.status, upload_row.storage_bucket::text, upload_row.storage_object_key, upload_row.expires_at;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_complete_document_upload(
  p_actor_auth_subject uuid,
  p_upload_id uuid,
  p_verified_mime_type text,
  p_verified_file_size_bytes bigint,
  p_verified_sha256_hash bytea,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  status app.document_upload_status,
  reserved_document_id uuid,
  verified_mime_type text,
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
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF upload_row.id IS NULL OR upload_row.authorized_by <> actor_row.actor_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document upload is not authorized.';
  END IF;
  RETURN QUERY SELECT * FROM app.complete_document_upload_trusted(upload_row, p_verified_mime_type, p_verified_file_size_bytes, p_verified_sha256_hash, actor_row.actor_user_id, actor_row.actor_auth_subject, 'owner_admin', 'document_upload_awaiting_scan', p_request_identifier);
END
$function$;

CREATE OR REPLACE FUNCTION app.complete_document_upload_trusted(
  upload_row app.document_uploads,
  p_verified_mime_type text,
  p_verified_file_size_bytes bigint,
  p_verified_sha256_hash bytea,
  p_actor_user_id uuid,
  p_actor_auth_subject uuid,
  p_role_code text,
  p_activity_action text,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  status app.document_upload_status,
  reserved_document_id uuid,
  verified_mime_type text,
  verified_file_size_bytes bigint,
  verified_sha256_hash bytea
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF upload_row.status = 'AWAITING_SCAN' THEN
    RETURN QUERY SELECT upload_row.id, upload_row.status, upload_row.reserved_document_id, upload_row.verified_mime_type::text, upload_row.verified_file_size_bytes, upload_row.verified_sha256_hash;
    RETURN;
  END IF;
  IF upload_row.status IN ('FAILED','EXPIRED') OR upload_row.expires_at <= transaction_timestamp() THEN
    UPDATE app.document_uploads SET status = 'EXPIRED', expired_at = coalesce(expired_at, transaction_timestamp()), failure_code = coalesce(failure_code, 'reservation_expired') WHERE id = upload_row.id;
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload reservation expired.';
  END IF;
  IF p_verified_mime_type NOT IN ('application/pdf','image/jpeg','image/png','image/webp')
     OR NOT app.document_allowed_extension(upload_row.original_file_name, p_verified_mime_type)
     OR p_verified_mime_type <> upload_row.declared_mime_type THEN
    UPDATE app.document_uploads SET status = 'FAILED', failed_at = transaction_timestamp(), failure_code = 'mime_or_extension_mismatch' WHERE id = upload_row.id;
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload validation failed.';
  END IF;
  IF p_verified_file_size_bytes IS NULL OR p_verified_file_size_bytes <= 0 OR p_verified_file_size_bytes > 26214400 OR octet_length(p_verified_sha256_hash) <> 32 THEN
    UPDATE app.document_uploads SET status = 'FAILED', failed_at = transaction_timestamp(), failure_code = 'size_or_hash_invalid' WHERE id = upload_row.id;
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document upload validation failed.';
  END IF;

  UPDATE app.document_uploads
  SET status = 'AWAITING_SCAN',
      uploaded_at = coalesce(uploaded_at, transaction_timestamp()),
      validated_at = coalesce(validated_at, transaction_timestamp()),
      awaiting_scan_at = coalesce(awaiting_scan_at, transaction_timestamp()),
      verified_mime_type = p_verified_mime_type,
      verified_file_size_bytes = p_verified_file_size_bytes,
      verified_sha256_hash = p_verified_sha256_hash
  WHERE id = upload_row.id
  RETURNING id, document_uploads.status, document_uploads.reserved_document_id, document_uploads.verified_mime_type::text, document_uploads.verified_file_size_bytes, document_uploads.verified_sha256_hash
  INTO upload_id, status, reserved_document_id, verified_mime_type, verified_file_size_bytes, verified_sha256_hash;

  PERFORM app.write_activity_log(p_actor_user_id, p_actor_auth_subject, p_role_code, p_activity_action, 'document_upload', upload_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('verified_mime_type', p_verified_mime_type, 'verified_file_size_bytes', p_verified_file_size_bytes));
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_complete_transfer_evidence_upload(
  p_verified_client_auth_subject uuid,
  p_upload_id uuid,
  p_verified_mime_type text,
  p_verified_file_size_bytes bigint,
  p_verified_sha256_hash bytea,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  upload_id uuid,
  status app.document_upload_status,
  reserved_document_id uuid,
  verified_mime_type text,
  verified_file_size_bytes bigint,
  verified_sha256_hash bytea
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  client_ctx record;
  upload_row app.document_uploads%ROWTYPE;
  scope_row record;
BEGIN
  SELECT c.id AS client_id, c.portal_user_id AS user_id, u.auth_subject AS auth_subject
  INTO client_ctx
  FROM app.users u
  JOIN app.clients c ON c.portal_user_id = u.id
  WHERE u.auth_subject = p_verified_client_auth_subject
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND EXISTS (SELECT 1 FROM app.user_roles ur WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active)
  LIMIT 1;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF client_ctx.client_id IS NULL
     OR upload_row.id IS NULL
     OR upload_row.authorized_by IS DISTINCT FROM client_ctx.user_id
     OR upload_row.document_type_code <> 'BANK_TRANSFER_EVIDENCE'
     OR upload_row.requested_client_visible
     OR upload_row.client_payment_id IS NULL
     OR num_nonnulls(upload_row.client_id, upload_row.project_id, upload_row.task_id, upload_row.progress_update_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id) <> 0 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Client operation denied.';
  END IF;
  SELECT * INTO scope_row FROM app.document_finance_target_scope(upload_row.client_payment_id, NULL, NULL, NULL);
  IF NOT coalesce(scope_row.target_exists, false)
     OR scope_row.client_id IS DISTINCT FROM client_ctx.client_id
     OR NOT scope_row.is_client_submitted
     OR scope_row.submitted_by_client_user_id IS DISTINCT FROM client_ctx.user_id
     OR scope_row.event_status <> 'SUBMITTED'
     OR scope_row.transaction_status <> 'SUBMITTED' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Client operation denied.';
  END IF;
  RETURN QUERY SELECT * FROM app.complete_document_upload_trusted(upload_row, p_verified_mime_type, p_verified_file_size_bytes, p_verified_sha256_hash, client_ctx.user_id, client_ctx.auth_subject, 'client', 'client_transfer_evidence_submitted', p_request_identifier);
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
  scope_row record;
  before_count integer;
  after_count integer;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO upload_row FROM app.document_uploads WHERE id = p_upload_id FOR UPDATE;
  IF upload_row.id IS NULL THEN
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
  IF NOT app.document_target_exists(upload_row.client_id, upload_row.project_id, upload_row.task_id, upload_row.progress_update_id, upload_row.client_payment_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document link target is not available.';
  END IF;
  IF num_nonnulls(upload_row.client_payment_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id) = 1 THEN
    SELECT * INTO scope_row FROM app.document_finance_target_scope(upload_row.client_payment_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id);
    IF NOT app.document_finance_type_allowed(upload_row.document_type_code, upload_row.requested_client_visible, upload_row.client_payment_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document type is not allowed for this financial target.';
    END IF;
    IF upload_row.document_type_code = 'BANK_TRANSFER_EVIDENCE' AND upload_row.authorized_by = scope_row.submitted_by_client_user_id THEN
      IF upload_row.requested_client_visible
         OR upload_row.payment_request_id IS NOT NULL
         OR upload_row.project_expense_id IS NOT NULL
         OR upload_row.currency_exchange_id IS NOT NULL
         OR NOT scope_row.is_client_submitted
         OR scope_row.event_status <> 'SUBMITTED'
         OR scope_row.transaction_status <> 'SUBMITTED' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document finalization is not authorized.';
      END IF;
    END IF;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app.document_types dt WHERE dt.code = upload_row.document_type_code AND dt.is_active) THEN
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

  SELECT count(*)::integer INTO before_count FROM app.document_links dl WHERE dl.document_id = upload_row.reserved_document_id;
  INSERT INTO app.document_links (
    document_id, client_id, project_id, task_id, progress_update_id,
    client_payment_id, payment_request_id, project_expense_id, currency_exchange_id, created_by
  )
  SELECT upload_row.reserved_document_id, upload_row.client_id, upload_row.project_id, upload_row.task_id, upload_row.progress_update_id,
         upload_row.client_payment_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id, upload_row.authorized_by
  WHERE NOT EXISTS (SELECT 1 FROM app.document_links dl WHERE dl.document_id = upload_row.reserved_document_id);

  SELECT count(*)::integer INTO after_count FROM app.document_links dl WHERE dl.document_id = upload_row.reserved_document_id;
  IF after_count <> 1 THEN
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
  IF before_count = 0 AND after_count = 1 AND num_nonnulls(upload_row.client_payment_id, upload_row.payment_request_id, upload_row.project_expense_id, upload_row.currency_exchange_id) = 1 THEN
    PERFORM app.write_activity_log(upload_row.authorized_by, NULL, CASE WHEN upload_row.authorized_by = actor_row.actor_user_id THEN 'owner_admin' ELSE 'client' END, 'financial_document_linked', 'document', document_id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('document_type_code', upload_row.document_type_code));
  END IF;
  RETURN NEXT;
END
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
  IF upload_row.id IS NULL THEN
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
  SELECT count(*)::integer + 1 INTO next_attempt FROM app.document_scans ds WHERE ds.document_upload_id = upload_row.id;
  UPDATE app.document_uploads SET status = 'SCAN_IN_PROGRESS', scan_started_at = transaction_timestamp(), scan_completed_at = NULL WHERE id = upload_row.id;
  INSERT INTO app.document_scans (document_upload_id, attempt_number, status, scanner_engine, scanned_storage_bucket, scanned_storage_object_key, scanned_sha256_hash, scanned_file_size_bytes)
  VALUES (upload_row.id, next_attempt, 'STARTED', 'clamav-compatible-https', upload_row.storage_bucket, upload_row.storage_object_key, upload_row.verified_sha256_hash, upload_row.verified_file_size_bytes)
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
  IF upload_row.id IS NULL OR upload_row.status <> 'SCAN_IN_PROGRESS' THEN
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
  IF upload_row.id IS NULL THEN
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

CREATE OR REPLACE FUNCTION app.authorize_document_access(
  p_actor_auth_subject uuid,
  p_document_id uuid,
  p_purpose text,
  p_request_identifier text DEFAULT NULL
)
RETURNS TABLE (
  document_id uuid,
  document_number text,
  storage_bucket text,
  storage_object_key text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  status app.document_status,
  content_disposition text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_role record;
  client_row app.clients%ROWTYPE;
  doc_row app.documents%ROWTYPE;
  safe_name text;
  client_allowed boolean := false;
BEGIN
  IF p_purpose NOT IN ('preview','download') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document access purpose is invalid.';
  END IF;
  SELECT * INTO doc_row FROM app.documents WHERE id = p_document_id;
  IF doc_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
  END IF;

  SELECT * INTO actor_role FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_role.actor_user_id IS NOT NULL THEN
    IF doc_row.status NOT IN ('ACTIVE','ARCHIVED') THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
  ELSE
    SELECT c.* INTO client_row
    FROM app.clients c
    JOIN app.users u ON u.id = c.portal_user_id
    WHERE u.auth_subject = p_actor_auth_subject
      AND u.status = 'ACTIVE'
      AND u.is_active
      AND c.status = 'ACTIVE'
      AND c.is_active
      AND c.archived_at IS NULL;
    IF client_row.id IS NULL OR doc_row.status <> 'ACTIVE' THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;

    client_allowed := EXISTS (
      SELECT 1
      FROM app.document_links dl
      JOIN app.client_payments cp ON cp.id = dl.client_payment_id
      JOIN app.projects p ON p.id = cp.project_id
      WHERE dl.document_id = doc_row.id
        AND doc_row.document_type_code = 'BANK_TRANSFER_EVIDENCE'
        AND NOT doc_row.client_visible
        AND cp.is_client_submitted
        AND cp.submitted_by_client_user_id = client_row.portal_user_id
        AND cp.client_id = client_row.id
        AND p.client_id = client_row.id
        AND doc_row.uploaded_by = client_row.portal_user_id
    );

    IF NOT client_allowed AND doc_row.client_visible THEN
      client_allowed := EXISTS (
        SELECT 1
        FROM app.document_links dl
        LEFT JOIN app.projects p ON p.id = dl.project_id
        LEFT JOIN app.tasks t ON t.id = dl.task_id
        LEFT JOIN app.progress_updates pu ON pu.id = dl.progress_update_id
        LEFT JOIN app.projects tp ON tp.id = t.project_id
        LEFT JOIN app.projects pp ON pp.id = pu.project_id
        LEFT JOIN app.client_payments cp ON cp.id = dl.client_payment_id
        LEFT JOIN app.payment_requests pr ON pr.id = dl.payment_request_id
        WHERE dl.document_id = doc_row.id
          AND dl.project_expense_id IS NULL
          AND dl.currency_exchange_id IS NULL
          AND (
            dl.client_id = client_row.id
            OR p.client_id = client_row.id
            OR tp.client_id = client_row.id
            OR pp.client_id = client_row.id
            OR (cp.client_id = client_row.id AND EXISTS (SELECT 1 FROM app.projects cpp WHERE cpp.id = cp.project_id AND cpp.client_id = client_row.id))
            OR (pr.client_id = client_row.id AND EXISTS (SELECT 1 FROM app.projects prp WHERE prp.id = pr.project_id AND prp.client_id = client_row.id))
          )
      ) AND NOT EXISTS (
        SELECT 1
        FROM app.document_links other_dl
        LEFT JOIN app.projects other_p ON other_p.id = other_dl.project_id
        LEFT JOIN app.tasks other_t ON other_t.id = other_dl.task_id
        LEFT JOIN app.progress_updates other_pu ON other_pu.id = other_dl.progress_update_id
        LEFT JOIN app.projects other_tp ON other_tp.id = other_t.project_id
        LEFT JOIN app.projects other_pp ON other_pp.id = other_pu.project_id
        LEFT JOIN app.client_payments other_cp ON other_cp.id = other_dl.client_payment_id
        LEFT JOIN app.payment_requests other_pr ON other_pr.id = other_dl.payment_request_id
        WHERE other_dl.document_id = doc_row.id
          AND coalesce(other_dl.client_id, other_p.client_id, other_tp.client_id, other_pp.client_id, other_cp.client_id, other_pr.client_id) IS DISTINCT FROM client_row.id
      );
    END IF;

    IF NOT client_allowed THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document access denied.';
    END IF;
    actor_role.actor_user_id := client_row.portal_user_id;
    actor_role.actor_auth_subject := p_actor_auth_subject;
    actor_role.effective_role_code := 'client';
  END IF;

  safe_name := regexp_replace(doc_row.original_file_name, '[\r\n"\\/]+', '_', 'g');
  PERFORM app.write_activity_log(actor_role.actor_user_id, actor_role.actor_auth_subject, actor_role.effective_role_code, CASE p_purpose WHEN 'preview' THEN 'document_preview_authorized' ELSE 'document_download_authorized' END, 'document', doc_row.id, NULL, 'success', '{}'::jsonb, '{}'::jsonb, NULL, NULL, NULL, p_request_identifier, NULL, jsonb_build_object('purpose', p_purpose));
  RETURN QUERY SELECT doc_row.id, doc_row.document_number::text, doc_row.storage_bucket::text, doc_row.storage_object_key, doc_row.original_file_name::text, doc_row.mime_type::text, doc_row.file_size_bytes, doc_row.status, (CASE WHEN p_purpose = 'preview' THEN 'inline' ELSE 'attachment' END) || '; filename="' || safe_name || '"';
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_document_list_for_authenticated_user(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (
  id uuid,
  document_number text,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_type_code text,
  uploaded_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  client_row app.clients%ROWTYPE;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;
  SELECT c.* INTO client_row
  FROM app.clients AS c
  INNER JOIN app.users AS u ON u.id = c.portal_user_id
  WHERE u.auth_subject = auth.uid()
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL;
  IF client_row.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT d.id, d.document_number::text, d.original_file_name::text, d.mime_type::text, d.file_size_bytes, d.document_type_code::text, d.uploaded_at
  FROM app.documents AS d
  INNER JOIN app.document_links AS dl ON dl.document_id = d.id
  LEFT JOIN app.projects AS p ON p.id = dl.project_id
  LEFT JOIN app.tasks AS t ON t.id = dl.task_id
  LEFT JOIN app.progress_updates AS pu ON pu.id = dl.progress_update_id
  LEFT JOIN app.projects AS tp ON tp.id = t.project_id
  LEFT JOIN app.projects AS pp ON pp.id = pu.project_id
  LEFT JOIN app.client_payments cp ON cp.id = dl.client_payment_id
  LEFT JOIN app.payment_requests pr ON pr.id = dl.payment_request_id
  WHERE d.status = 'ACTIVE'
    AND d.client_visible
    AND dl.project_expense_id IS NULL
    AND dl.currency_exchange_id IS NULL
    AND (
      dl.client_id = client_row.id
      OR p.client_id = client_row.id
      OR tp.client_id = client_row.id
      OR pp.client_id = client_row.id
      OR cp.client_id = client_row.id
      OR pr.client_id = client_row.id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM app.document_links other_dl
      LEFT JOIN app.projects other_p ON other_p.id = other_dl.project_id
      LEFT JOIN app.tasks other_t ON other_t.id = other_dl.task_id
      LEFT JOIN app.progress_updates other_pu ON other_pu.id = other_dl.progress_update_id
      LEFT JOIN app.projects other_tp ON other_tp.id = other_t.project_id
      LEFT JOIN app.projects other_pp ON other_pp.id = other_pu.project_id
      LEFT JOIN app.client_payments other_cp ON other_cp.id = other_dl.client_payment_id
      LEFT JOIN app.payment_requests other_pr ON other_pr.id = other_dl.payment_request_id
      WHERE other_dl.document_id = d.id
        AND coalesce(other_dl.client_id, other_p.client_id, other_tp.client_id, other_pp.client_id, other_cp.client_id, other_pr.client_id) IS DISTINCT FROM client_row.id
    )
  ORDER BY d.uploaded_at DESC, d.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_reserve_document_upload(p_verified_owner_auth_subject uuid, p_storage_object_token text, p_original_file_name text, p_declared_mime_type text, p_document_type_code varchar(50), p_requested_client_visible boolean DEFAULT false, p_client_id uuid DEFAULT NULL, p_project_id uuid DEFAULT NULL, p_task_id uuid DEFAULT NULL, p_progress_update_id uuid DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_client_payment_id uuid DEFAULT NULL, p_payment_request_id uuid DEFAULT NULL, p_project_expense_id uuid DEFAULT NULL, p_currency_exchange_id uuid DEFAULT NULL)
RETURNS TABLE (upload_id uuid, reserved_document_id uuid, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.owner_reserve_document_upload(p_verified_owner_auth_subject, p_storage_object_token, p_original_file_name, p_declared_mime_type, p_document_type_code, p_requested_client_visible, p_client_id, p_project_id, p_task_id, p_progress_update_id, p_request_identifier, p_client_payment_id, p_payment_request_id, p_project_expense_id, p_currency_exchange_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_reserve_transfer_evidence_upload(p_verified_client_auth_subject uuid, p_storage_object_token text, p_original_file_name text, p_declared_mime_type text, p_client_payment_id uuid, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (upload_id uuid, reserved_document_id uuid, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_reserve_transfer_evidence_upload(p_verified_client_auth_subject, p_storage_object_token, p_original_file_name, p_declared_mime_type, p_client_payment_id, p_request_identifier);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_transfer_evidence_upload_storage_context(p_verified_client_auth_subject uuid, p_upload_id uuid)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, storage_bucket text, storage_object_key text, expires_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_transfer_evidence_upload_storage_context(p_verified_client_auth_subject, p_upload_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_complete_transfer_evidence_upload(p_verified_client_auth_subject uuid, p_upload_id uuid, p_verified_mime_type text, p_verified_file_size_bytes bigint, p_verified_sha256_hash bytea, p_request_identifier text DEFAULT NULL)
RETURNS TABLE (upload_id uuid, status app.document_upload_status, reserved_document_id uuid, verified_mime_type text, verified_file_size_bytes bigint, verified_sha256_hash bytea)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_complete_transfer_evidence_upload(p_verified_client_auth_subject, p_upload_id, p_verified_mime_type, p_verified_file_size_bytes, p_verified_sha256_hash, p_request_identifier);
$function$;

COMMIT;
