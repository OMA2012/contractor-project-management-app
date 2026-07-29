BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_financial_optional_text(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT NULLIF(btrim(p_value), '');
$function$;

CREATE OR REPLACE FUNCTION app.ensure_opening_balance_control_ledger_account(p_currency_code char(3))
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
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Valid opening balance currency is required.';
  END IF;

  PERFORM set_config('app.ledger_account_sync_context', 'financial_account_sync', true);
  INSERT INTO app.ledger_accounts (
    code, name, account_kind, financial_account_id, currency_code, normal_side, is_system, is_active
  )
  VALUES (
    'CTRL-OPENING-' || p_currency_code::text,
    'Opening Balance Control ' || p_currency_code::text,
    'CONTROL',
    NULL,
    p_currency_code,
    'CREDIT',
    true,
    true
  )
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

CREATE OR REPLACE FUNCTION app.owner_create_opening_balance(
  p_actor_auth_subject uuid,
  p_financial_account_id uuid,
  p_amount numeric,
  p_opening_date date,
  p_reporting_currency_code char(3),
  p_description text DEFAULT NULL,
  p_notes text DEFAULT NULL,
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
  account_row app.financial_accounts%ROWTYPE;
  normalized_description text := app.normalize_financial_optional_text(p_description);
  normalized_notes text := app.normalize_financial_optional_text(p_notes);
  previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id = p_financial_account_id FOR UPDATE;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR p_amount IS NULL OR p_amount <= 0 OR p_opening_date IS NULL OR p_reporting_currency_code IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid opening balance.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = p_reporting_currency_code AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid opening balance.';
  END IF;

  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  INSERT INTO app.financial_events (
    event_type, event_date, status, description, duplicate_fingerprint, created_by, updated_by
  )
  VALUES (
    'OPENING_BALANCE', p_opening_date, 'DRAFT', normalized_description, app.normalize_financial_optional_text(p_duplicate_fingerprint), actor_row.actor_user_id, actor_row.actor_user_id
  )
  RETURNING id, app.financial_events.event_number, app.financial_events.version_number
  INTO financial_event_id, event_number, version_number;

  INSERT INTO app.financial_transactions (
    financial_event_id, transaction_date, status, reporting_currency_code, description, created_by
  )
  VALUES (
    financial_event_id, p_opening_date, 'DRAFT', p_reporting_currency_code, normalized_description, actor_row.actor_user_id
  )
  RETURNING id, app.financial_transactions.transaction_number
  INTO financial_transaction_id, transaction_number;

  INSERT INTO app.account_opening_balances (
    financial_event_id, financial_account_id, amount, currency_code, opening_date, notes
  )
  VALUES (
    financial_event_id, account_row.id, p_amount, account_row.currency_code, p_opening_date, normalized_notes
  );
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'opening_balance_created', 'financial_event', financial_event_id, NULL, 'success',
    '{}'::jsonb,
    jsonb_build_object('event_number', event_number, 'transaction_number', transaction_number, 'financial_account_id', account_row.id, 'currency_code', account_row.currency_code, 'status', 'DRAFT'),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb
  );

  RETURN NEXT;
EXCEPTION
  WHEN unique_violation THEN
    PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Duplicate opening balance.';
  WHEN OTHERS THEN
    PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
    RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_opening_balance(
  p_actor_auth_subject uuid,
  p_financial_event_id uuid,
  p_expected_version_number integer,
  p_amount numeric,
  p_opening_date date,
  p_reporting_currency_code char(3),
  p_description text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  opening_row app.account_opening_balances%ROWTYPE;
  account_row app.financial_accounts%ROWTYPE;
  previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events AS fe WHERE fe.id = p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions AS ft WHERE ft.financial_event_id = p_financial_event_id FOR UPDATE;
  SELECT * INTO opening_row FROM app.account_opening_balances AS ob WHERE ob.financial_event_id = p_financial_event_id FOR UPDATE;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id = opening_row.financial_account_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR opening_row.id IS NULL OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance cannot be updated.';
  END IF;
  IF event_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Opening balance version conflict.';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_opening_date IS NULL OR p_reporting_currency_code IS NULL OR account_row.id IS NULL OR account_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid opening balance.';
  END IF;

  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_events
  SET event_date = p_opening_date,
      description = app.normalize_financial_optional_text(p_description),
      updated_by = actor_row.actor_user_id
  WHERE id = p_financial_event_id
  RETURNING app.financial_events.id, app.financial_events.version_number INTO financial_event_id, version_number;
  UPDATE app.financial_transactions
  SET transaction_date = p_opening_date,
      reporting_currency_code = p_reporting_currency_code,
      description = app.normalize_financial_optional_text(p_description)
  WHERE id = transaction_row.id
  RETURNING id INTO financial_transaction_id;
  UPDATE app.account_opening_balances
  SET amount = p_amount,
      currency_code = account_row.currency_code,
      opening_date = p_opening_date,
      notes = app.normalize_financial_optional_text(p_notes)
  WHERE id = opening_row.id;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'opening_balance_updated', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('version_number', event_row.version_number), jsonb_build_object('version_number', version_number, 'financial_account_id', account_row.id, 'currency_code', account_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_submit_opening_balance(
  p_actor_auth_subject uuid,
  p_financial_event_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  event_row app.financial_events%ROWTYPE;
  previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events AS fe WHERE fe.id = p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.status <> 'DRAFT' OR event_row.event_type <> 'OPENING_BALANCE' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance cannot be submitted.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Opening balance version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_events SET status = 'SUBMITTED', submitted_at = now(), submitted_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE id = p_financial_event_id RETURNING app.financial_events.id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status = 'SUBMITTED' WHERE app.financial_transactions.financial_event_id = p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'opening_balance_submitted', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status', 'DRAFT', 'version_number', event_row.version_number), jsonb_build_object('status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_reject_opening_balance(
  p_actor_auth_subject uuid,
  p_financial_event_id uuid,
  p_expected_version_number integer,
  p_rejection_reason text,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  event_row app.financial_events%ROWTYPE;
  reason_text text := btrim(coalesce(p_rejection_reason, ''));
  previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Rejection reason is required.'; END IF;
  SELECT * INTO event_row FROM app.financial_events AS fe WHERE fe.id = p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.status <> 'SUBMITTED' OR event_row.event_type <> 'OPENING_BALANCE' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance cannot be rejected.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Opening balance version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_events SET status = 'REJECTED', rejected_at = now(), rejected_by = actor_row.actor_user_id, rejection_reason = reason_text, updated_by = actor_row.actor_user_id WHERE id = p_financial_event_id RETURNING app.financial_events.id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status = 'REJECTED', rejected_at = now(), rejected_by = actor_row.actor_user_id, rejection_reason = reason_text WHERE app.financial_transactions.financial_event_id = p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'opening_balance_rejected', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status', 'SUBMITTED', 'version_number', event_row.version_number), jsonb_build_object('status', status, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided', true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_approve_opening_balance(
  p_actor_auth_subject uuid,
  p_financial_event_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  opening_row app.account_opening_balances%ROWTYPE;
  account_row app.financial_accounts%ROWTYPE;
  asset_ledger_row app.ledger_accounts%ROWTYPE;
  control_ledger_id uuid;
  control_ledger_row app.ledger_accounts%ROWTYPE;
  chosen_rate app.exchange_rates%ROWTYPE;
  converted_amount numeric;
  rounded_amount numeric;
  rounding_delta numeric;
  reporting_digits integer;
  previous_financial_context text := current_setting('app.financial_transaction_context', true);
  previous_posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events AS fe WHERE fe.id = p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions AS ft WHERE ft.financial_event_id = p_financial_event_id FOR UPDATE;
  SELECT * INTO opening_row FROM app.account_opening_balances AS ob WHERE ob.financial_event_id = p_financial_event_id FOR UPDATE;

  IF event_row.id IS NULL OR transaction_row.id IS NULL OR opening_row.id IS NULL OR event_row.event_type <> 'OPENING_BALANCE' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance cannot be approved.';
  END IF;
  IF event_row.status = 'APPROVED' AND transaction_row.status = 'POSTED' THEN
    financial_event_id := event_row.id;
    financial_transaction_id := transaction_row.id;
    event_status := event_row.status::text;
    transaction_status := transaction_row.status::text;
    ledger_entry_count := (SELECT count(*)::integer FROM app.ledger_entries WHERE app.ledger_entries.financial_transaction_id = transaction_row.id);
    version_number := event_row.version_number;
    RETURN NEXT;
    RETURN;
  END IF;
  IF event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance cannot be approved.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Opening balance version conflict.'; END IF;
  IF event_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Opening balance requires different Owner approval.'; END IF;

  SELECT * INTO account_row FROM app.financial_accounts WHERE id = opening_row.financial_account_id FOR UPDATE;
  SELECT * INTO asset_ledger_row FROM app.ledger_accounts WHERE financial_account_id = account_row.id AND account_kind = 'FINANCIAL_ASSET' FOR UPDATE;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR asset_ledger_row.id IS NULL OR NOT asset_ledger_row.is_active OR opening_row.amount <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid opening balance.';
  END IF;
  IF opening_row.currency_code IS DISTINCT FROM account_row.currency_code OR opening_row.currency_code IS DISTINCT FROM asset_ledger_row.currency_code OR opening_row.opening_date IS DISTINCT FROM event_row.event_date OR event_row.event_date IS DISTINCT FROM transaction_row.transaction_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid opening balance.';
  END IF;

  SELECT decimal_digits INTO reporting_digits FROM app.currencies WHERE code = transaction_row.reporting_currency_code;
  IF reporting_digits IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid opening balance.'; END IF;
  IF opening_row.currency_code = transaction_row.reporting_currency_code THEN
    converted_amount := opening_row.amount;
    rounded_amount := round(converted_amount, reporting_digits);
    rounding_delta := abs(converted_amount - rounded_amount);
  ELSE
    SELECT * INTO chosen_rate
    FROM app.exchange_rates AS er
    WHERE er.rate_date = transaction_row.transaction_date
      AND (
        (er.base_currency_code = opening_row.currency_code AND er.quote_currency_code = transaction_row.reporting_currency_code)
        OR
        (er.quote_currency_code = opening_row.currency_code AND er.base_currency_code = transaction_row.reporting_currency_code)
      )
    ORDER BY er.created_at DESC, er.id DESC
    LIMIT 1;
    IF chosen_rate.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Transaction-date exchange rate is required.'; END IF;
    converted_amount := app.convert_amount_with_exchange_rate(opening_row.amount, opening_row.currency_code, transaction_row.reporting_currency_code, chosen_rate.base_currency_code, chosen_rate.quote_currency_code, chosen_rate.rate_value);
    rounded_amount := round(converted_amount, reporting_digits);
    rounding_delta := abs(converted_amount - rounded_amount);
  END IF;

  control_ledger_id := app.ensure_opening_balance_control_ledger_account(opening_row.currency_code);
  SELECT * INTO control_ledger_row FROM app.ledger_accounts WHERE id = control_ledger_id FOR UPDATE;

  PERFORM set_config('app.ledger_posting_context', 'opening_balance_posting', true);
  INSERT INTO app.ledger_entries (
    financial_transaction_id, line_no, ledger_account_id, project_id, client_id,
    currency_code, debit_amount, credit_amount, reporting_currency_code,
    reporting_debit_amount, reporting_credit_amount, exchange_rate_id,
    rate_base_currency_code, rate_quote_currency_code, rate_value, rate_source,
    rounding_adjustment, memo, created_by
  )
  VALUES
    (transaction_row.id, 1, asset_ledger_row.id, NULL, NULL, opening_row.currency_code, opening_row.amount, 0, transaction_row.reporting_currency_code, rounded_amount, 0, chosen_rate.id, chosen_rate.base_currency_code, chosen_rate.quote_currency_code, chosen_rate.rate_value, chosen_rate.source, rounding_delta, 'Opening balance debit', actor_row.actor_user_id),
    (transaction_row.id, 2, control_ledger_row.id, NULL, NULL, opening_row.currency_code, 0, opening_row.amount, transaction_row.reporting_currency_code, 0, rounded_amount, chosen_rate.id, chosen_rate.base_currency_code, chosen_rate.quote_currency_code, chosen_rate.rate_value, chosen_rate.source, rounding_delta, 'Opening balance credit', actor_row.actor_user_id);
  PERFORM set_config('app.ledger_posting_context', coalesce(previous_posting_context, ''), true);

  IF EXISTS (
    SELECT 1
    FROM app.ledger_entries
    WHERE app.ledger_entries.financial_transaction_id = transaction_row.id
    GROUP BY currency_code
    HAVING sum(debit_amount) <> sum(credit_amount)
  ) OR EXISTS (
    SELECT 1
    FROM app.ledger_entries
    WHERE app.ledger_entries.financial_transaction_id = transaction_row.id
    GROUP BY reporting_currency_code
    HAVING sum(reporting_debit_amount) <> sum(reporting_credit_amount)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries do not balance.';
  END IF;

  PERFORM set_config('app.financial_transaction_context', 'owner_financial_mutation', true);
  UPDATE app.financial_transactions SET status = 'POSTED', approved_at = now(), approved_by = actor_row.actor_user_id, posted_at = now(), posted_by = actor_row.actor_user_id WHERE id = transaction_row.id RETURNING id, app.financial_transactions.status::text INTO financial_transaction_id, transaction_status;
  UPDATE app.financial_events SET status = 'APPROVED', approved_at = now(), approved_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE id = event_row.id RETURNING app.financial_events.id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, event_status, version_number;
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_financial_context, ''), true);

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'opening_balance_approved', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status', 'SUBMITTED', 'version_number', event_row.version_number), jsonb_build_object('status', event_status, 'version_number', version_number, 'financial_account_id', account_row.id, 'currency_code', opening_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'financial_transaction_posted', 'financial_transaction', financial_transaction_id, NULL, 'success', jsonb_build_object('status', 'SUBMITTED'), jsonb_build_object('status', transaction_status, 'ledger_entry_count', 2, 'financial_account_id', account_row.id, 'currency_code', opening_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);

  ledger_entry_count := 2;
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.ledger_posting_context', coalesce(previous_posting_context, ''), true);
  PERFORM set_config('app.financial_transaction_context', coalesce(previous_financial_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_opening_balance_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, financial_account_id uuid, amount numeric, currency_code char(3), opening_date date, event_status text, transaction_status text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100); safe_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY
  SELECT fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, ob.financial_account_id, ob.amount, ob.currency_code, ob.opening_date, fe.status::text, ft.status::text, fe.version_number
  FROM app.financial_events fe
  JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
  JOIN app.account_opening_balances ob ON ob.financial_event_id = fe.id
  WHERE fe.event_type = 'OPENING_BALANCE'
  ORDER BY fe.created_at DESC, fe.id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_opening_balance_detail(p_actor_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, financial_account_id uuid, amount numeric, currency_code char(3), opening_date date, reporting_currency_code char(3), event_status text, transaction_status text, description text, notes text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY
  SELECT fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, ob.financial_account_id, ob.amount, ob.currency_code, ob.opening_date, ft.reporting_currency_code, fe.status::text, ft.status::text, fe.description, ob.notes, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
  FROM app.financial_events fe
  JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
  JOIN app.account_opening_balances ob ON ob.financial_event_id = fe.id
  WHERE fe.id = p_financial_event_id AND fe.event_type = 'OPENING_BALANCE';
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_financial_account_balance(p_actor_auth_subject uuid, p_financial_account_id uuid)
RETURNS TABLE (financial_account_id uuid, account_number text, account_type text, currency_code char(3), balance numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY
  SELECT fa.id, fa.account_number::text, fa.account_type::text, fa.currency_code, coalesce(sum(le.debit_amount - le.credit_amount), 0)::numeric
  FROM app.financial_accounts fa
  JOIN app.ledger_accounts la ON la.financial_account_id = fa.id AND la.account_kind = 'FINANCIAL_ASSET'
  LEFT JOIN app.ledger_entries le ON le.ledger_account_id = la.id
  LEFT JOIN app.financial_transactions ft ON ft.id = le.financial_transaction_id AND ft.status = 'POSTED'
  WHERE fa.id = p_financial_account_id AND (le.id IS NULL OR ft.id IS NOT NULL)
  GROUP BY fa.id, fa.account_number, fa.account_type, fa.currency_code;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_financial_account_balances_by_currency(p_actor_auth_subject uuid)
RETURNS TABLE (currency_code char(3), balance numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY
  SELECT la.currency_code, coalesce(sum(le.debit_amount - le.credit_amount), 0)::numeric
  FROM app.ledger_accounts la
  JOIN app.ledger_entries le ON le.ledger_account_id = la.id
  JOIN app.financial_transactions ft ON ft.id = le.financial_transaction_id AND ft.status = 'POSTED'
  WHERE la.account_kind = 'FINANCIAL_ASSET'
  GROUP BY la.currency_code
  ORDER BY la.currency_code;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_cash_totals_by_currency(p_actor_auth_subject uuid)
RETURNS TABLE (currency_code char(3), balance numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY
  SELECT la.currency_code, coalesce(sum(le.debit_amount - le.credit_amount), 0)::numeric
  FROM app.financial_accounts fa
  JOIN app.ledger_accounts la ON la.financial_account_id = fa.id AND la.account_kind = 'FINANCIAL_ASSET'
  JOIN app.ledger_entries le ON le.ledger_account_id = la.id
  JOIN app.financial_transactions ft ON ft.id = le.financial_transaction_id AND ft.status = 'POSTED'
  WHERE fa.account_type = 'CASH'
  GROUP BY la.currency_code
  ORDER BY la.currency_code;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_bank_totals_by_currency(p_actor_auth_subject uuid)
RETURNS TABLE (currency_code char(3), balance numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY
  SELECT la.currency_code, coalesce(sum(le.debit_amount - le.credit_amount), 0)::numeric
  FROM app.financial_accounts fa
  JOIN app.ledger_accounts la ON la.financial_account_id = fa.id AND la.account_kind = 'FINANCIAL_ASSET'
  JOIN app.ledger_entries le ON le.ledger_account_id = la.id
  JOIN app.financial_transactions ft ON ft.id = le.financial_transaction_id AND ft.status = 'POSTED'
  WHERE fa.account_type = 'BANK'
  GROUP BY la.currency_code
  ORDER BY la.currency_code;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_opening_balance(p_verified_owner_auth_subject uuid, p_financial_account_id uuid, p_amount numeric, p_opening_date date, p_reporting_currency_code char(3), p_description text DEFAULT NULL, p_notes text DEFAULT NULL, p_duplicate_fingerprint text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_opening_balance(p_verified_owner_auth_subject,p_financial_account_id,p_amount,p_opening_date,p_reporting_currency_code,p_description,p_notes,p_duplicate_fingerprint,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_opening_balance(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_amount numeric, p_opening_date date, p_reporting_currency_code char(3), p_description text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_opening_balance(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_amount,p_opening_date,p_reporting_currency_code,p_description,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_submit_opening_balance(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_opening_balance(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_opening_balance(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_opening_balance(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_opening_balance(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_opening_balance(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_opening_balance_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, financial_account_id uuid, amount numeric, currency_code char(3), opening_date date, event_status text, transaction_status text, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_opening_balance_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_opening_balance_detail(p_verified_owner_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, financial_account_id uuid, amount numeric, currency_code char(3), opening_date date, reporting_currency_code char(3), event_status text, transaction_status text, description text, notes text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_opening_balance_detail(p_verified_owner_auth_subject,p_financial_event_id); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_financial_account_balance(p_verified_owner_auth_subject uuid, p_financial_account_id uuid) RETURNS TABLE (financial_account_id uuid, account_number text, account_type text, currency_code char(3), balance numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_financial_account_balance(p_verified_owner_auth_subject,p_financial_account_id); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_financial_account_balances_by_currency(p_verified_owner_auth_subject uuid) RETURNS TABLE (currency_code char(3), balance numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_financial_account_balances_by_currency(p_verified_owner_auth_subject); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_cash_totals_by_currency(p_verified_owner_auth_subject uuid) RETURNS TABLE (currency_code char(3), balance numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_cash_totals_by_currency(p_verified_owner_auth_subject); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_bank_totals_by_currency(p_verified_owner_auth_subject uuid) RETURNS TABLE (currency_code char(3), balance numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_bank_totals_by_currency(p_verified_owner_auth_subject); $function$;

COMMIT;
