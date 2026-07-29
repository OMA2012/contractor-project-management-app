BEGIN;

CREATE OR REPLACE FUNCTION app.ensure_adjustment_control_ledger_account(p_currency_code char(3))
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  ledger_account_id uuid;
  previous_context text := current_setting('app.ledger_account_sync_context', true);
BEGIN
  IF p_currency_code IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = p_currency_code AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Valid adjustment currency is required.';
  END IF;
  PERFORM set_config('app.ledger_account_sync_context', 'financial_account_sync', true);
  INSERT INTO app.ledger_accounts (code, name, account_kind, financial_account_id, currency_code, normal_side, is_system, is_active)
  VALUES ('CTRL-ADJUSTMENT-' || p_currency_code::text, 'Adjustment Control - ' || p_currency_code::text, 'CONTROL', NULL, p_currency_code, 'CREDIT', true, true)
  ON CONFLICT (code) DO UPDATE
  SET name = EXCLUDED.name,
      currency_code = EXCLUDED.currency_code,
      is_system = true,
      is_active = true
  RETURNING id INTO ledger_account_id;
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RETURN ledger_account_id;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.financial_transaction_reporting_snapshot(
  p_amount numeric,
  p_source_currency_code char(3),
  p_reporting_currency_code char(3),
  p_transaction_date date
)
RETURNS TABLE (reporting_amount numeric, rounding_adjustment numeric, exchange_rate_id uuid, rate_base_currency_code char(3), rate_quote_currency_code char(3), rate_value numeric, rate_source varchar)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  chosen_rate app.exchange_rates%ROWTYPE;
  converted_amount numeric;
  reporting_digits integer;
BEGIN
  SELECT decimal_digits INTO reporting_digits FROM app.currencies WHERE code = p_reporting_currency_code;
  IF reporting_digits IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid reporting currency.';
  END IF;

  IF p_source_currency_code = p_reporting_currency_code THEN
    reporting_amount := round(p_amount, reporting_digits);
    rounding_adjustment := abs(p_amount - reporting_amount);
    exchange_rate_id := NULL;
    rate_base_currency_code := NULL;
    rate_quote_currency_code := NULL;
    rate_value := NULL;
    rate_source := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO chosen_rate
  FROM app.exchange_rates er
  WHERE er.rate_date = p_transaction_date
    AND (
      (er.base_currency_code = p_source_currency_code AND er.quote_currency_code = p_reporting_currency_code)
      OR
      (er.quote_currency_code = p_source_currency_code AND er.base_currency_code = p_reporting_currency_code)
    )
  ORDER BY er.created_at DESC, er.id DESC
  LIMIT 1;
  IF chosen_rate.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Transaction-date exchange rate is required.';
  END IF;

  converted_amount := app.convert_amount_with_exchange_rate(p_amount, p_source_currency_code, p_reporting_currency_code, chosen_rate.base_currency_code, chosen_rate.quote_currency_code, chosen_rate.rate_value);
  reporting_amount := round(converted_amount, reporting_digits);
  rounding_adjustment := abs(converted_amount - reporting_amount);
  exchange_rate_id := chosen_rate.id;
  rate_base_currency_code := chosen_rate.base_currency_code;
  rate_quote_currency_code := chosen_rate.quote_currency_code;
  rate_value := chosen_rate.rate_value;
  rate_source := chosen_rate.source;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_reversal(
  p_actor_auth_subject uuid,
  p_original_transaction_id uuid,
  p_reversal_date date,
  p_reason text,
  p_description text DEFAULT NULL,
  p_duplicate_fingerprint text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  original_row app.financial_transactions%ROWTYPE;
  reason_text text := btrim(coalesce(p_reason, ''));
  previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO original_row FROM app.financial_transactions WHERE id = p_original_transaction_id FOR UPDATE;
  IF original_row.id IS NULL OR original_row.status <> 'POSTED' OR p_reversal_date IS NULL OR reason_text = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial reversal.';
  END IF;

  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  INSERT INTO app.financial_events (event_type, event_date, status, description, duplicate_fingerprint, created_by, updated_by)
  VALUES ('REVERSAL', p_reversal_date, 'DRAFT', app.normalize_financial_optional_text(p_description), app.normalize_financial_optional_text(p_duplicate_fingerprint), actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id, app.financial_events.event_number, app.financial_events.version_number INTO financial_event_id, event_number, version_number;
  INSERT INTO app.financial_transactions (financial_event_id, transaction_date, status, reporting_currency_code, description, created_by)
  VALUES (financial_event_id, p_reversal_date, 'DRAFT', original_row.reporting_currency_code, app.normalize_financial_optional_text(p_description), actor_row.actor_user_id)
  RETURNING id, app.financial_transactions.transaction_number INTO financial_transaction_id, transaction_number;
  INSERT INTO app.financial_reversals (financial_event_id, original_transaction_id, reason, full_reversal, reversal_date)
  VALUES (financial_event_id, original_row.id, reason_text, true, p_reversal_date);
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'reversal_created', 'financial_event', financial_event_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('event_number', event_number, 'transaction_number', transaction_number, 'original_transaction_id', original_row.id, 'status', 'DRAFT'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided', true));
  RETURN NEXT;
EXCEPTION
  WHEN unique_violation THEN
    PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Duplicate financial reversal.';
  WHEN OTHERS THEN
    PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
    RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_submit_reversal(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; reversal_row app.financial_reversals%ROWTYPE; original_row app.financial_transactions%ROWTYPE; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id = p_financial_event_id FOR UPDATE;
  SELECT * INTO reversal_row FROM app.financial_reversals fr WHERE fr.financial_event_id = p_financial_event_id FOR UPDATE;
  SELECT * INTO original_row FROM app.financial_transactions WHERE id = reversal_row.original_transaction_id FOR UPDATE;
  IF event_row.id IS NULL OR reversal_row.id IS NULL OR event_row.event_type <> 'REVERSAL' OR event_row.status <> 'DRAFT' OR original_row.status <> 'POSTED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversal cannot be submitted.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Financial reversal version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_events SET status='SUBMITTED', submitted_at=now(), submitted_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='SUBMITTED' WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'reversal_submitted', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','DRAFT','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number,'original_transaction_id',original_row.id), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_reject_reversal(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; reason_text text := btrim(coalesce(p_rejection_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Rejection reason is required.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id = p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.event_type <> 'REVERSAL' OR event_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversal cannot be rejected.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Financial reversal version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_events SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'reversal_rejected', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided', true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_approve_reversal(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; reversal_row app.financial_reversals%ROWTYPE; original_row app.financial_transactions%ROWTYPE;
  previous_financial_context text := current_setting('app.financial_transaction_context', true); previous_posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id = p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id = p_financial_event_id FOR UPDATE;
  SELECT * INTO reversal_row FROM app.financial_reversals fr WHERE fr.financial_event_id = p_financial_event_id FOR UPDATE;
  SELECT * INTO original_row FROM app.financial_transactions WHERE id = reversal_row.original_transaction_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR reversal_row.id IS NULL OR original_row.id IS NULL OR event_row.event_type <> 'REVERSAL' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversal cannot be approved.'; END IF;
  IF event_row.status = 'APPROVED' AND transaction_row.status = 'POSTED' THEN
    financial_event_id := event_row.id; financial_transaction_id := transaction_row.id; event_status := event_row.status::text; transaction_status := transaction_row.status::text; ledger_entry_count := (SELECT count(*)::integer FROM app.ledger_entries WHERE app.ledger_entries.financial_transaction_id = transaction_row.id); version_number := event_row.version_number; RETURN NEXT; RETURN;
  END IF;
  IF event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' OR original_row.status <> 'POSTED' OR NOT reversal_row.full_reversal THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversal cannot be approved.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Financial reversal version conflict.'; END IF;
  IF event_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Financial reversal requires different Owner approval.'; END IF;
  IF original_row.id = transaction_row.id OR reversal_row.reversal_date IS DISTINCT FROM event_row.event_date OR event_row.event_date IS DISTINCT FROM transaction_row.transaction_date THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial reversal.'; END IF;
  IF EXISTS (
    SELECT 1 FROM app.financial_reversals fr
    JOIN app.financial_events fe ON fe.id = fr.financial_event_id
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    WHERE fr.original_transaction_id = original_row.id AND fr.financial_event_id <> event_row.id AND fr.full_reversal AND fe.status = 'APPROVED' AND ft.status = 'POSTED'
  ) THEN RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Original transaction already has a full reversal.'; END IF;

  PERFORM set_config('app.ledger_posting_context', 'financial_reversal_posting', true);
  INSERT INTO app.ledger_entries (financial_transaction_id, line_no, ledger_account_id, project_id, client_id, currency_code, debit_amount, credit_amount, reporting_currency_code, reporting_debit_amount, reporting_credit_amount, exchange_rate_id, rate_base_currency_code, rate_quote_currency_code, rate_value, rate_source, rounding_adjustment, memo, created_by)
  SELECT transaction_row.id, le.line_no, le.ledger_account_id, le.project_id, le.client_id, le.currency_code, le.credit_amount, le.debit_amount, le.reporting_currency_code, le.reporting_credit_amount, le.reporting_debit_amount, le.exchange_rate_id, le.rate_base_currency_code, le.rate_quote_currency_code, le.rate_value, le.rate_source, le.rounding_adjustment, 'Full reversal line ' || le.line_no::text, actor_row.actor_user_id
  FROM app.ledger_entries le
  WHERE le.financial_transaction_id = original_row.id
  ORDER BY le.line_no;
  PERFORM set_config('app.ledger_posting_context', coalesce(previous_posting_context, ''), true);

  IF EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id = transaction_row.id GROUP BY currency_code HAVING sum(debit_amount) <> sum(credit_amount))
     OR EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id = transaction_row.id GROUP BY reporting_currency_code HAVING sum(reporting_debit_amount) <> sum(reporting_credit_amount)) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries do not balance.';
  END IF;

  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_transactions SET reverses_transaction_id=original_row.id, status='POSTED', approved_at=now(), approved_by=actor_row.actor_user_id, posted_at=now(), posted_by=actor_row.actor_user_id WHERE id=transaction_row.id RETURNING id, app.financial_transactions.status::text INTO financial_transaction_id, transaction_status;
  UPDATE app.financial_events SET status='APPROVED', approved_at=now(), approved_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=event_row.id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, event_status, version_number;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_financial_context, ''), true);

  ledger_entry_count := (SELECT count(*)::integer FROM app.ledger_entries le WHERE le.financial_transaction_id = transaction_row.id);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'reversal_approved', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',event_status,'version_number',version_number,'original_transaction_id',original_row.id), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'reversal_transaction_posted', 'financial_transaction', financial_transaction_id, NULL, 'success', jsonb_build_object('status','SUBMITTED'), jsonb_build_object('status',transaction_status,'ledger_entry_count',ledger_entry_count,'original_transaction_id',original_row.id), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.ledger_posting_context', coalesce(previous_posting_context, ''), true); PERFORM set_config('app.financial_transaction_context', coalesce(previous_financial_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_reversal_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, original_transaction_id uuid, reversal_date date, event_status text, transaction_status text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY SELECT fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, fr.original_transaction_id, fr.reversal_date, fe.status::text, ft.status::text, fe.version_number
  FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id JOIN app.financial_reversals fr ON fr.financial_event_id=fe.id
  WHERE fe.event_type='REVERSAL' ORDER BY fe.created_at DESC, fe.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_reversal_detail(p_actor_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, original_transaction_id uuid, reason text, full_reversal boolean, reversal_date date, reporting_currency_code char(3), event_status text, transaction_status text, description text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY SELECT fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, fr.original_transaction_id, fr.reason, fr.full_reversal, fr.reversal_date, ft.reporting_currency_code, fe.status::text, ft.status::text, fe.description, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
  FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id JOIN app.financial_reversals fr ON fr.financial_event_id=fe.id
  WHERE fe.id=p_financial_event_id AND fe.event_type='REVERSAL';
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_adjustment(p_actor_auth_subject uuid, p_financial_account_id uuid, p_direction app.adjustment_direction, p_amount numeric, p_adjustment_date date, p_reporting_currency_code char(3), p_reason text, p_adjusted_transaction_id uuid DEFAULT NULL, p_description text DEFAULT NULL, p_duplicate_fingerprint text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; account_row app.financial_accounts%ROWTYPE; adjusted_row app.financial_transactions%ROWTYPE; reason_text text := btrim(coalesce(p_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=p_financial_account_id FOR UPDATE;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR p_direction IS NULL OR p_amount IS NULL OR p_amount <= 0 OR p_adjustment_date IS NULL OR p_reporting_currency_code IS NULL OR reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial adjustment.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=p_reporting_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial adjustment.'; END IF;
  IF p_adjusted_transaction_id IS NOT NULL THEN
    SELECT * INTO adjusted_row FROM app.financial_transactions WHERE id=p_adjusted_transaction_id FOR UPDATE;
    IF adjusted_row.id IS NULL OR adjusted_row.status <> 'POSTED' OR adjusted_row.transaction_date > p_adjustment_date THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Adjusted transaction must be posted.'; END IF;
  END IF;
  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  INSERT INTO app.financial_events (event_type,event_date,status,description,duplicate_fingerprint,created_by,updated_by) VALUES ('ADJUSTMENT',p_adjustment_date,'DRAFT',app.normalize_financial_optional_text(p_description),app.normalize_financial_optional_text(p_duplicate_fingerprint),actor_row.actor_user_id,actor_row.actor_user_id) RETURNING id, app.financial_events.event_number, app.financial_events.version_number INTO financial_event_id, event_number, version_number;
  INSERT INTO app.financial_transactions (financial_event_id,transaction_date,status,reporting_currency_code,description,created_by) VALUES (financial_event_id,p_adjustment_date,'DRAFT',p_reporting_currency_code,app.normalize_financial_optional_text(p_description),actor_row.actor_user_id) RETURNING id, app.financial_transactions.transaction_number INTO financial_transaction_id, transaction_number;
  INSERT INTO app.financial_adjustments (financial_event_id, adjusted_transaction_id, financial_account_id, direction, amount, currency_code, adjustment_date, reason) VALUES (financial_event_id, p_adjusted_transaction_id, account_row.id, p_direction, p_amount::numeric(20,6), account_row.currency_code, p_adjustment_date, reason_text);
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'adjustment_created', 'financial_event', financial_event_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('event_number',event_number,'transaction_number',transaction_number,'financial_account_id',account_row.id,'adjusted_transaction_id',p_adjusted_transaction_id,'direction',p_direction::text,'currency_code',account_row.currency_code,'status','DRAFT'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided', true));
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate financial adjustment.'; WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_adjustment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_financial_account_id uuid, p_direction app.adjustment_direction, p_amount numeric, p_adjustment_date date, p_reporting_currency_code char(3), p_reason text, p_adjusted_transaction_id uuid DEFAULT NULL, p_description text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; account_row app.financial_accounts%ROWTYPE; adjusted_row app.financial_transactions%ROWTYPE; reason_text text := btrim(coalesce(p_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=p_financial_account_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR event_row.event_type <> 'ADJUSTMENT' OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' OR event_row.version_number <> p_expected_version_number THEN
    IF event_row.id IS NOT NULL AND event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Financial adjustment version conflict.'; END IF;
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Financial adjustment cannot be updated.';
  END IF;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR p_direction IS NULL OR p_amount IS NULL OR p_amount <= 0 OR p_adjustment_date IS NULL OR p_reporting_currency_code IS NULL OR reason_text='' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid financial adjustment.'; END IF;
  IF p_adjusted_transaction_id IS NOT NULL THEN SELECT * INTO adjusted_row FROM app.financial_transactions WHERE id=p_adjusted_transaction_id FOR UPDATE; IF adjusted_row.id IS NULL OR adjusted_row.status <> 'POSTED' OR adjusted_row.transaction_date > p_adjustment_date THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Adjusted transaction must be posted.'; END IF; END IF;
  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_events SET event_date=p_adjustment_date, description=app.normalize_financial_optional_text(p_description), updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.version_number INTO financial_event_id, version_number;
  UPDATE app.financial_transactions SET transaction_date=p_adjustment_date, reporting_currency_code=p_reporting_currency_code, description=app.normalize_financial_optional_text(p_description) WHERE id=transaction_row.id RETURNING id INTO financial_transaction_id;
  UPDATE app.financial_adjustments SET adjusted_transaction_id=p_adjusted_transaction_id, financial_account_id=account_row.id, direction=p_direction, amount=p_amount::numeric(20,6), currency_code=account_row.currency_code, adjustment_date=p_adjustment_date, reason=reason_text WHERE app.financial_adjustments.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'adjustment_updated', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('version_number',event_row.version_number), jsonb_build_object('version_number',version_number,'financial_account_id',account_row.id,'direction',p_direction::text,'currency_code',account_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided', true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_submit_adjustment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.event_type <> 'ADJUSTMENT' OR event_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Financial adjustment cannot be submitted.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Financial adjustment version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='SUBMITTED', submitted_at=now(), submitted_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='SUBMITTED' WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'adjustment_submitted', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','DRAFT','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_reject_adjustment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; reason_text text := btrim(coalesce(p_rejection_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  IF reason_text='' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Rejection reason is required.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.event_type <> 'ADJUSTMENT' OR event_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Financial adjustment cannot be rejected.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Financial adjustment version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'adjustment_rejected', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided', true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_approve_adjustment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; adjustment_row app.financial_adjustments%ROWTYPE; account_row app.financial_accounts%ROWTYPE; asset_row app.ledger_accounts%ROWTYPE; control_id uuid; control_row app.ledger_accounts%ROWTYPE; snap record;
  previous_financial_context text := current_setting('app.financial_transaction_context', true); previous_posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO adjustment_row FROM app.financial_adjustments fa WHERE fa.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR adjustment_row.id IS NULL OR event_row.event_type <> 'ADJUSTMENT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Financial adjustment cannot be approved.'; END IF;
  IF event_row.status='APPROVED' AND transaction_row.status='POSTED' THEN financial_event_id:=event_row.id; financial_transaction_id:=transaction_row.id; event_status:=event_row.status::text; transaction_status:=transaction_row.status::text; ledger_entry_count:=(SELECT count(*)::integer FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id); version_number:=event_row.version_number; RETURN NEXT; RETURN; END IF;
  IF event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Financial adjustment cannot be approved.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Financial adjustment version conflict.'; END IF;
  IF event_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Financial adjustment requires different Owner approval.'; END IF;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=adjustment_row.financial_account_id FOR UPDATE;
  SELECT * INTO asset_row FROM app.ledger_accounts WHERE financial_account_id=account_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR asset_row.id IS NULL OR NOT asset_row.is_active OR adjustment_row.amount <= 0 THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid financial adjustment.'; END IF;
  IF adjustment_row.currency_code IS DISTINCT FROM account_row.currency_code OR adjustment_row.currency_code IS DISTINCT FROM asset_row.currency_code OR adjustment_row.adjustment_date IS DISTINCT FROM event_row.event_date OR event_row.event_date IS DISTINCT FROM transaction_row.transaction_date THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid financial adjustment.'; END IF;
  IF adjustment_row.adjusted_transaction_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM app.financial_transactions WHERE id=adjustment_row.adjusted_transaction_id AND status='POSTED' AND transaction_date <= adjustment_row.adjustment_date FOR UPDATE) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Adjusted transaction must be posted.'; END IF;
  SELECT * INTO snap FROM app.financial_transaction_reporting_snapshot(adjustment_row.amount, adjustment_row.currency_code, transaction_row.reporting_currency_code, transaction_row.transaction_date);
  control_id := app.ensure_adjustment_control_ledger_account(adjustment_row.currency_code);
  SELECT * INTO control_row FROM app.ledger_accounts WHERE id=control_id FOR UPDATE;
  PERFORM set_config('app.ledger_posting_context','financial_adjustment_posting',true);
  IF adjustment_row.direction = 'INCREASE' THEN
    INSERT INTO app.ledger_entries (financial_transaction_id,line_no,ledger_account_id,project_id,client_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,exchange_rate_id,rate_base_currency_code,rate_quote_currency_code,rate_value,rate_source,rounding_adjustment,memo,created_by)
    VALUES (transaction_row.id,1,asset_row.id,NULL,NULL,adjustment_row.currency_code,adjustment_row.amount,0,transaction_row.reporting_currency_code,snap.reporting_amount,0,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Adjustment increase debit',actor_row.actor_user_id),
           (transaction_row.id,2,control_row.id,NULL,NULL,adjustment_row.currency_code,0,adjustment_row.amount,transaction_row.reporting_currency_code,0,snap.reporting_amount,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Adjustment increase credit',actor_row.actor_user_id);
  ELSE
    INSERT INTO app.ledger_entries (financial_transaction_id,line_no,ledger_account_id,project_id,client_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,exchange_rate_id,rate_base_currency_code,rate_quote_currency_code,rate_value,rate_source,rounding_adjustment,memo,created_by)
    VALUES (transaction_row.id,1,control_row.id,NULL,NULL,adjustment_row.currency_code,adjustment_row.amount,0,transaction_row.reporting_currency_code,snap.reporting_amount,0,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Adjustment decrease debit',actor_row.actor_user_id),
           (transaction_row.id,2,asset_row.id,NULL,NULL,adjustment_row.currency_code,0,adjustment_row.amount,transaction_row.reporting_currency_code,0,snap.reporting_amount,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Adjustment decrease credit',actor_row.actor_user_id);
  END IF;
  PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true);
  IF EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY currency_code HAVING sum(debit_amount)<>sum(credit_amount)) OR EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY reporting_currency_code HAVING sum(reporting_debit_amount)<>sum(reporting_credit_amount)) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Ledger entries do not balance.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_transactions SET status='POSTED', approved_at=now(), approved_by=actor_row.actor_user_id, posted_at=now(), posted_by=actor_row.actor_user_id WHERE id=transaction_row.id RETURNING id, app.financial_transactions.status::text INTO financial_transaction_id, transaction_status;
  UPDATE app.financial_events SET status='APPROVED', approved_at=now(), approved_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=event_row.id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, event_status, version_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true);
  ledger_entry_count := 2;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'adjustment_approved', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',event_status,'version_number',version_number,'financial_account_id',account_row.id,'direction',adjustment_row.direction::text,'currency_code',adjustment_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'adjustment_transaction_posted', 'financial_transaction', financial_transaction_id, NULL, 'success', jsonb_build_object('status','SUBMITTED'), jsonb_build_object('status',transaction_status,'ledger_entry_count',2,'financial_account_id',account_row.id,'direction',adjustment_row.direction::text,'currency_code',adjustment_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true); PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_adjustment_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, adjusted_transaction_id uuid, financial_account_id uuid, direction text, amount numeric, currency_code char(3), adjustment_date date, event_status text, transaction_status text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, fa.adjusted_transaction_id, fa.financial_account_id, fa.direction::text, fa.amount, fa.currency_code, fa.adjustment_date, fe.status::text, ft.status::text, fe.version_number
  FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id JOIN app.financial_adjustments fa ON fa.financial_event_id=fe.id WHERE fe.event_type='ADJUSTMENT' ORDER BY fe.created_at DESC, fe.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_adjustment_detail(p_actor_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, adjusted_transaction_id uuid, financial_account_id uuid, direction text, amount numeric, currency_code char(3), adjustment_date date, reason text, reporting_currency_code char(3), event_status text, transaction_status text, description text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, fa.adjusted_transaction_id, fa.financial_account_id, fa.direction::text, fa.amount, fa.currency_code, fa.adjustment_date, fa.reason, ft.reporting_currency_code, fe.status::text, ft.status::text, fe.description, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
  FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id JOIN app.financial_adjustments fa ON fa.financial_event_id=fe.id WHERE fe.id=p_financial_event_id AND fe.event_type='ADJUSTMENT';
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_reversal(p_verified_owner_auth_subject uuid, p_original_transaction_id uuid, p_reversal_date date, p_reason text, p_description text DEFAULT NULL, p_duplicate_fingerprint text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_reversal(p_verified_owner_auth_subject,p_original_transaction_id,p_reversal_date,p_reason,p_description,p_duplicate_fingerprint,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_submit_reversal(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_reversal(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_reversal(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_reversal(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_reversal(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_reversal(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reversal_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, original_transaction_id uuid, reversal_date date, event_status text, transaction_status text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reversal_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reversal_detail(p_verified_owner_auth_subject uuid, p_financial_event_id uuid) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, original_transaction_id uuid, reason text, full_reversal boolean, reversal_date date, reporting_currency_code char(3), event_status text, transaction_status text, description text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reversal_detail(p_verified_owner_auth_subject,p_financial_event_id); $function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_adjustment(p_verified_owner_auth_subject uuid, p_financial_account_id uuid, p_direction app.adjustment_direction, p_amount numeric, p_adjustment_date date, p_reporting_currency_code char(3), p_reason text, p_adjusted_transaction_id uuid DEFAULT NULL, p_description text DEFAULT NULL, p_duplicate_fingerprint text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_adjustment(p_verified_owner_auth_subject,p_financial_account_id,p_direction,p_amount,p_adjustment_date,p_reporting_currency_code,p_reason,p_adjusted_transaction_id,p_description,p_duplicate_fingerprint,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_adjustment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_financial_account_id uuid, p_direction app.adjustment_direction, p_amount numeric, p_adjustment_date date, p_reporting_currency_code char(3), p_reason text, p_adjusted_transaction_id uuid DEFAULT NULL, p_description text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_adjustment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_financial_account_id,p_direction,p_amount,p_adjustment_date,p_reporting_currency_code,p_reason,p_adjusted_transaction_id,p_description,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_submit_adjustment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_adjustment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_adjustment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_adjustment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_adjustment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_adjustment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_adjustment_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, adjusted_transaction_id uuid, financial_account_id uuid, direction text, amount numeric, currency_code char(3), adjustment_date date, event_status text, transaction_status text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_adjustment_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_adjustment_detail(p_verified_owner_auth_subject uuid, p_financial_event_id uuid) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, adjusted_transaction_id uuid, financial_account_id uuid, direction text, amount numeric, currency_code char(3), adjustment_date date, reason text, reporting_currency_code char(3), event_status text, transaction_status text, description text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_adjustment_detail(p_verified_owner_auth_subject,p_financial_event_id); $function$;

COMMIT;
