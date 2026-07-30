BEGIN;

CREATE OR REPLACE FUNCTION app.client_payment_transaction_id(p_client_payment_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT ft.id
  FROM app.client_payments cp
  JOIN app.financial_transactions ft ON ft.financial_event_id = cp.financial_event_id
  WHERE cp.id = p_client_payment_id
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION app.client_payment_economically_active(p_client_payment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH RECURSIVE chain(transaction_id, depth) AS (
    SELECT app.client_payment_transaction_id(p_client_payment_id), 0
    UNION ALL
    SELECT reversal_tx.id, chain.depth + 1
    FROM chain
    JOIN app.financial_reversals fr ON fr.original_transaction_id = chain.transaction_id AND fr.full_reversal
    JOIN app.financial_events fe ON fe.id = fr.financial_event_id AND fe.status = 'APPROVED'
    JOIN app.financial_transactions reversal_tx ON reversal_tx.financial_event_id = fe.id AND reversal_tx.status = 'POSTED'
    WHERE chain.depth < 20
  )
  SELECT coalesce(((count(*) - 1) % 2) = 0, false) FROM chain;
$function$;

CREATE OR REPLACE FUNCTION app.lock_payment_economic_chain(p_client_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  ignored uuid;
BEGIN
  FOR ignored IN
    WITH RECURSIVE chain(transaction_id, depth) AS (
      SELECT app.client_payment_transaction_id(p_client_payment_id), 0
      UNION ALL
      SELECT reversal_tx.id, chain.depth + 1
      FROM chain
      JOIN app.financial_reversals fr ON fr.original_transaction_id = chain.transaction_id AND fr.full_reversal
      JOIN app.financial_events fe ON fe.id = fr.financial_event_id AND fe.status = 'APPROVED'
      JOIN app.financial_transactions reversal_tx ON reversal_tx.financial_event_id = fe.id AND reversal_tx.status = 'POSTED'
      WHERE chain.depth < 20
    )
    SELECT ft.id FROM app.financial_transactions ft WHERE ft.id IN (SELECT transaction_id FROM chain) ORDER BY ft.id FOR UPDATE
  LOOP
  END LOOP;

  FOR ignored IN
    WITH RECURSIVE chain(transaction_id, depth) AS (
      SELECT app.client_payment_transaction_id(p_client_payment_id), 0
      UNION ALL
      SELECT reversal_tx.id, chain.depth + 1
      FROM chain
      JOIN app.financial_reversals fr ON fr.original_transaction_id = chain.transaction_id AND fr.full_reversal
      JOIN app.financial_events fe ON fe.id = fr.financial_event_id AND fe.status = 'APPROVED'
      JOIN app.financial_transactions reversal_tx ON reversal_tx.financial_event_id = fe.id AND reversal_tx.status = 'POSTED'
      WHERE chain.depth < 20
    )
    SELECT fr.id FROM app.financial_reversals fr WHERE fr.original_transaction_id IN (SELECT transaction_id FROM chain) ORDER BY fr.id FOR UPDATE
  LOOP
  END LOOP;
END
$function$;

CREATE OR REPLACE FUNCTION app.payment_request_amounts(p_payment_request_id uuid)
RETURNS TABLE (paid_amount numeric, remaining_amount numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    coalesce(sum(pm.matched_amount) FILTER (
      WHERE pm.status = 'APPROVED'
        AND pm.is_active
        AND fe.event_type = 'CLIENT_PAYMENT'
        AND fe.status = 'APPROVED'
        AND ft.status = 'POSTED'
        AND app.client_payment_economically_active(pm.client_payment_id)
    ), 0)::numeric(20,6) AS paid_amount,
    greatest(
      pr.requested_amount - coalesce(sum(pm.matched_amount) FILTER (
        WHERE pm.status = 'APPROVED'
          AND pm.is_active
          AND fe.event_type = 'CLIENT_PAYMENT'
          AND fe.status = 'APPROVED'
          AND ft.status = 'POSTED'
          AND app.client_payment_economically_active(pm.client_payment_id)
      ), 0),
      0
    )::numeric(20,6) AS remaining_amount
  FROM app.payment_requests pr
  LEFT JOIN app.payment_matches pm ON pm.payment_request_id = pr.id
  LEFT JOIN app.client_payments cp ON cp.id = pm.client_payment_id
  LEFT JOIN app.financial_events fe ON fe.id = cp.financial_event_id
  LEFT JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
  WHERE pr.id = p_payment_request_id
  GROUP BY pr.id, pr.requested_amount;
$function$;

CREATE OR REPLACE FUNCTION app.payment_request_effective_status(p_status app.payment_request_status, p_due_date date)
RETURNS app.payment_request_status
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_status IN ('SENT','VIEWED','PARTIALLY_PAID') AND p_due_date IS NOT NULL AND p_due_date < app.contractor_local_date() THEN
    RETURN 'OVERDUE';
  END IF;
  RETURN p_status;
END
$function$;

CREATE OR REPLACE FUNCTION app.payment_request_calculated_status(
  p_current_status app.payment_request_status,
  p_requested_amount numeric,
  p_due_date date,
  p_viewed_at timestamptz,
  p_paid_amount numeric,
  p_remaining_amount numeric
)
RETURNS app.payment_request_status
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_current_status = 'CANCELLED' THEN
    RETURN 'CANCELLED';
  END IF;
  IF coalesce(p_paid_amount, 0) >= p_requested_amount THEN
    RETURN 'PAID';
  END IF;
  IF coalesce(p_remaining_amount, p_requested_amount) > 0 AND p_due_date IS NOT NULL AND p_due_date < app.contractor_local_date() THEN
    RETURN 'OVERDUE';
  END IF;
  IF coalesce(p_paid_amount, 0) > 0 THEN
    RETURN 'PARTIALLY_PAID';
  END IF;
  IF p_viewed_at IS NOT NULL THEN
    RETURN 'VIEWED';
  END IF;
  RETURN 'SENT';
END
$function$;

CREATE OR REPLACE FUNCTION app.sync_payment_request_status_from_matches(
  p_actor_user_id uuid,
  p_actor_auth_subject uuid,
  p_actor_role_code text,
  p_payment_request_id uuid,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, paid_amount numeric, remaining_amount numeric, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  request_row app.payment_requests%ROWTYPE;
  amounts_row record;
  new_status app.payment_request_status;
  previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO request_row FROM app.payment_requests WHERE id = p_payment_request_id FOR UPDATE;
  IF request_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment request not found.';
  END IF;

  SELECT * INTO amounts_row FROM app.payment_request_amounts(request_row.id);
  new_status := app.payment_request_calculated_status(request_row.status, request_row.requested_amount, request_row.due_date, request_row.viewed_at, amounts_row.paid_amount, amounts_row.remaining_amount);

  IF request_row.status IS DISTINCT FROM new_status THEN
    PERFORM set_config('app.payment_request_context', 'payment_match_status_sync', true);
    UPDATE app.payment_requests
    SET status = new_status,
        updated_by = p_actor_user_id
    WHERE id = request_row.id
    RETURNING * INTO request_row;
    PERFORM set_config('app.payment_request_context', coalesce(previous_context, ''), true);

    PERFORM app.write_activity_log(p_actor_user_id, p_actor_auth_subject, p_actor_role_code::varchar, 'payment_request_status_synchronized', 'payment_request', request_row.id, NULL, 'success', jsonb_build_object('status', request_row.status::text), jsonb_build_object('request_number', request_row.request_number::text, 'project_id', request_row.project_id, 'client_id', request_row.client_id, 'currency_code', request_row.currency_code, 'status', new_status::text, 'version_number', request_row.version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  END IF;

  payment_request_id := request_row.id;
  request_number := request_row.request_number::text;
  status := request_row.status;
  paid_amount := amounts_row.paid_amount;
  remaining_amount := amounts_row.remaining_amount;
  version_number := request_row.version_number;
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.payment_request_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.payment_requests_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  project_row app.projects%ROWTYPE;
  client_row app.clients%ROWTYPE;
  mutation_context text := coalesce(current_setting('app.payment_request_context', true), '');
BEGIN
  IF mutation_context NOT IN ('payment_request_owner_mutation','payment_request_client_view','payment_request_overdue_refresh','payment_match_status_sync') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment requests require trusted functions.';
  END IF;

  SELECT * INTO project_row FROM app.projects WHERE id = NEW.project_id;
  SELECT * INTO client_row FROM app.clients WHERE id = NEW.client_id;
  IF project_row.id IS NULL OR client_row.id IS NULL OR project_row.client_id IS DISTINCT FROM NEW.client_id OR project_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request.';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.request_number IS DISTINCT FROM OLD.request_number OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment request identity fields are immutable.';
    END IF;

    IF OLD.status = 'CANCELLED' AND NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Cancelled payment requests are immutable.';
    END IF;

    IF mutation_context = 'payment_match_status_sync' THEN
      IF NEW.status NOT IN ('SENT','VIEWED','PARTIALLY_PAID','PAID','OVERDUE','CANCELLED')
         OR NEW.project_id IS DISTINCT FROM OLD.project_id
         OR NEW.client_id IS DISTINCT FROM OLD.client_id
         OR NEW.requested_amount IS DISTINCT FROM OLD.requested_amount
         OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
         OR NEW.request_date IS DISTINCT FROM OLD.request_date
         OR NEW.due_date IS DISTINCT FROM OLD.due_date
         OR NEW.description IS DISTINCT FROM OLD.description
         OR NEW.sent_at IS DISTINCT FROM OLD.sent_at
         OR NEW.viewed_at IS DISTINCT FROM OLD.viewed_at
         OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
         OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
         OR NEW.cancellation_reason IS DISTINCT FROM OLD.cancellation_reason THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match status synchronization can only update request status.';
      END IF;
    ELSIF mutation_context = 'payment_request_client_view' THEN
      IF OLD.viewed_at IS NOT NULL THEN
        IF NEW IS DISTINCT FROM OLD THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment request view is idempotent.'; END IF;
      ELSIF NEW.viewed_at IS NULL
         OR NEW.project_id IS DISTINCT FROM OLD.project_id
         OR NEW.client_id IS DISTINCT FROM OLD.client_id
         OR NEW.requested_amount IS DISTINCT FROM OLD.requested_amount
         OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
         OR NEW.request_date IS DISTINCT FROM OLD.request_date
         OR NEW.due_date IS DISTINCT FROM OLD.due_date
         OR NEW.description IS DISTINCT FROM OLD.description
         OR NEW.sent_at IS DISTINCT FROM OLD.sent_at
         OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
         OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
         OR NEW.cancellation_reason IS DISTINCT FROM OLD.cancellation_reason
         OR NOT ((OLD.status = 'SENT' AND NEW.status IN ('SENT','VIEWED')) OR (OLD.status IN ('VIEWED','OVERDUE','CANCELLED','PARTIALLY_PAID','PAID') AND NEW.status = OLD.status)) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client view can only acknowledge the first view.';
      END IF;
    ELSIF mutation_context = 'payment_request_overdue_refresh' THEN
      IF NEW.project_id IS DISTINCT FROM OLD.project_id
         OR NEW.client_id IS DISTINCT FROM OLD.client_id
         OR NEW.requested_amount IS DISTINCT FROM OLD.requested_amount
         OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
         OR NEW.request_date IS DISTINCT FROM OLD.request_date
         OR NEW.due_date IS DISTINCT FROM OLD.due_date
         OR NEW.description IS DISTINCT FROM OLD.description
         OR NEW.sent_at IS DISTINCT FROM OLD.sent_at
         OR NEW.viewed_at IS DISTINCT FROM OLD.viewed_at
         OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
         OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
         OR NEW.cancellation_reason IS DISTINCT FROM OLD.cancellation_reason THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Overdue refresh can only synchronize request status.';
      END IF;
    ELSIF OLD.status <> 'DRAFT' THEN
      IF NEW.project_id IS DISTINCT FROM OLD.project_id OR NEW.client_id IS DISTINCT FROM OLD.client_id OR NEW.requested_amount IS DISTINCT FROM OLD.requested_amount OR NEW.currency_code IS DISTINCT FROM OLD.currency_code OR NEW.request_date IS DISTINCT FROM OLD.request_date OR NEW.due_date IS DISTINCT FROM OLD.due_date OR NEW.description IS DISTINCT FROM OLD.description THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Sent payment request facts are immutable.';
      END IF;
    END IF;

    IF mutation_context = 'payment_request_owner_mutation' THEN
      IF OLD.status = 'DRAFT' AND NEW.status NOT IN ('DRAFT','SENT','CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
      END IF;
      IF OLD.status = 'SENT' AND NEW.status NOT IN ('SENT','VIEWED','OVERDUE','CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
      END IF;
      IF OLD.status = 'VIEWED' AND NEW.status NOT IN ('VIEWED','OVERDUE','CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
      END IF;
      IF OLD.status = 'OVERDUE' AND NEW.status NOT IN ('OVERDUE','CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
      END IF;
      IF OLD.status IN ('PARTIALLY_PAID','PAID') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment matching statuses require matching functions.';
      END IF;
    END IF;

    NEW.updated_at := now();
    NEW.version_number := OLD.version_number + 1;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.validate_payment_match_relationship(p_client_payment_id uuid, p_payment_request_id uuid, p_matched_amount numeric)
RETURNS TABLE (client_payment_id uuid, payment_request_id uuid, project_id uuid, client_id uuid, currency_code char(3), payment_amount numeric, request_amount numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  payment_row app.client_payments%ROWTYPE;
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  request_row app.payment_requests%ROWTYPE;
BEGIN
  SELECT * INTO payment_row FROM app.client_payments WHERE id = p_client_payment_id;
  SELECT * INTO event_row FROM app.financial_events WHERE id = payment_row.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = event_row.id;
  SELECT * INTO request_row FROM app.payment_requests WHERE id = p_payment_request_id;

  IF payment_row.id IS NULL OR request_row.id IS NULL OR p_matched_amount IS NULL OR p_matched_amount <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment match.';
  END IF;
  IF event_row.event_type <> 'CLIENT_PAYMENT' OR event_row.status <> 'APPROVED' OR transaction_row.status <> 'POSTED' OR NOT app.client_payment_economically_active(payment_row.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client payment is not matchable.';
  END IF;
  IF request_row.status NOT IN ('SENT','VIEWED','OVERDUE','PARTIALLY_PAID') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment request is not matchable.';
  END IF;
  IF payment_row.project_id IS DISTINCT FROM request_row.project_id OR payment_row.client_id IS DISTINCT FROM request_row.client_id OR payment_row.currency_code IS DISTINCT FROM request_row.currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match requires same Project, Client and currency.';
  END IF;

  client_payment_id := payment_row.id;
  payment_request_id := request_row.id;
  project_id := payment_row.project_id;
  client_id := payment_row.client_id;
  currency_code := payment_row.currency_code;
  payment_amount := payment_row.amount;
  request_amount := request_row.requested_amount;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_client_payment_availability(p_actor_auth_subject uuid, p_client_payment_id uuid)
RETURNS TABLE (client_payment_id uuid, payment_amount numeric, approved_active_matched_amount numeric, unmatched_amount numeric, economically_active boolean, eligible_for_matching boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  payment_row app.client_payments%ROWTYPE;
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  matched_total numeric(20,6);
  active_value boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO payment_row FROM app.client_payments WHERE id = p_client_payment_id;
  SELECT * INTO event_row FROM app.financial_events WHERE id = payment_row.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = event_row.id;
  active_value := app.client_payment_economically_active(payment_row.id);
  SELECT coalesce(sum(pm.matched_amount),0)::numeric(20,6) INTO matched_total FROM app.payment_matches pm WHERE pm.client_payment_id = p_client_payment_id AND pm.status = 'APPROVED' AND pm.is_active AND active_value;
  client_payment_id := payment_row.id;
  payment_amount := payment_row.amount;
  approved_active_matched_amount := matched_total;
  economically_active := coalesce(active_value, false);
  eligible_for_matching := payment_row.id IS NOT NULL AND event_row.event_type = 'CLIENT_PAYMENT' AND event_row.status = 'APPROVED' AND transaction_row.status = 'POSTED' AND coalesce(active_value, false);
  unmatched_amount := CASE WHEN eligible_for_matching THEN greatest(payment_row.amount - matched_total, 0)::numeric(20,6) ELSE 0::numeric(20,6) END;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_payment_request_balance(p_actor_auth_subject uuid, p_payment_request_id uuid)
RETURNS TABLE (payment_request_id uuid, request_number text, requested_amount numeric, paid_amount numeric, remaining_amount numeric, status app.payment_request_status, effective_status app.payment_request_status)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE amount_row record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY
  SELECT pr.id, pr.request_number::text, pr.requested_amount, a.paid_amount, a.remaining_amount, pr.status,
         app.payment_request_calculated_status(pr.status, pr.requested_amount, pr.due_date, pr.viewed_at, a.paid_amount, a.remaining_amount)
  FROM app.payment_requests pr
  CROSS JOIN LATERAL app.payment_request_amounts(pr.id) a
  WHERE pr.id = p_payment_request_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_payment_match(p_actor_auth_subject uuid, p_client_payment_id uuid, p_payment_request_id uuid, p_matched_amount numeric, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, matched_amount numeric, currency_code char(3))
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE actor_row record; rel_row record; previous_context text := current_setting('app.payment_match_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO rel_row FROM app.validate_payment_match_relationship(p_client_payment_id, p_payment_request_id, p_matched_amount);

  IF p_matched_amount > rel_row.payment_amount OR p_matched_amount > rel_row.request_amount THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match exceeds available amount.';
  END IF;

  PERFORM set_config('app.payment_match_context', 'payment_match_owner_mutation', true);
  INSERT INTO app.payment_matches (client_payment_id, payment_request_id, matched_amount, currency_code, matched_by)
  VALUES (rel_row.client_payment_id, rel_row.payment_request_id, p_matched_amount::numeric(20,6), rel_row.currency_code, actor_row.actor_user_id)
  RETURNING id, app.payment_matches.status, app.payment_matches.matched_amount, app.payment_matches.currency_code
  INTO payment_match_id, status, matched_amount, currency_code;
  PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true);

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_match_created', 'payment_match', payment_match_id, rel_row.project_id, 'success', '{}'::jsonb, jsonb_build_object('client_payment_id', rel_row.client_payment_id, 'payment_request_id', rel_row.payment_request_id, 'project_id', rel_row.project_id, 'client_id', rel_row.client_id, 'currency_code', rel_row.currency_code, 'matched_amount', p_matched_amount::numeric(20,6), 'status', status::text), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true); RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Payment and request pair already matched.';
WHEN OTHERS THEN PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_payment_match(p_actor_auth_subject uuid, p_payment_match_id uuid, p_expected_client_payment_id uuid, p_expected_payment_request_id uuid, p_expected_matched_amount numeric, p_client_payment_id uuid, p_payment_request_id uuid, p_matched_amount numeric, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, matched_amount numeric, currency_code char(3))
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE actor_row record; match_row app.payment_matches%ROWTYPE; rel_row record; previous_context text := current_setting('app.payment_match_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO match_row FROM app.payment_matches WHERE id = p_payment_match_id FOR UPDATE;
  IF match_row.id IS NULL OR match_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match cannot be updated.'; END IF;
  IF match_row.matched_by IS DISTINCT FROM actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the match creator can update the draft.'; END IF;
  IF match_row.client_payment_id IS DISTINCT FROM p_expected_client_payment_id OR match_row.payment_request_id IS DISTINCT FROM p_expected_payment_request_id OR match_row.matched_amount IS DISTINCT FROM p_expected_matched_amount::numeric(20,6) THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Payment match compare-and-lock conflict.';
  END IF;
  SELECT * INTO rel_row FROM app.validate_payment_match_relationship(p_client_payment_id, p_payment_request_id, p_matched_amount);
  PERFORM set_config('app.payment_match_context', 'payment_match_owner_mutation', true);
  UPDATE app.payment_matches SET client_payment_id = rel_row.client_payment_id, payment_request_id = rel_row.payment_request_id, matched_amount = p_matched_amount::numeric(20,6), currency_code = rel_row.currency_code WHERE id = match_row.id RETURNING id, app.payment_matches.status, app.payment_matches.matched_amount, app.payment_matches.currency_code INTO payment_match_id, status, matched_amount, currency_code;
  PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_match_updated', 'payment_match', payment_match_id, rel_row.project_id, 'success', jsonb_build_object('client_payment_id', match_row.client_payment_id, 'payment_request_id', match_row.payment_request_id, 'matched_amount', match_row.matched_amount, 'status', match_row.status::text), jsonb_build_object('client_payment_id', rel_row.client_payment_id, 'payment_request_id', rel_row.payment_request_id, 'project_id', rel_row.project_id, 'client_id', rel_row.client_id, 'currency_code', rel_row.currency_code, 'matched_amount', p_matched_amount::numeric(20,6), 'status', status::text), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true); RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Payment and request pair already matched.';
WHEN OTHERS THEN PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_approve_payment_match(p_actor_auth_subject uuid, p_payment_match_id uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, payment_request_id uuid, paid_amount numeric, remaining_amount numeric, request_status app.payment_request_status)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE actor_row record; match_row app.payment_matches%ROWTYPE; rel_row record; payment_total numeric(20,6); request_total numeric(20,6); sync_row record; previous_context text := current_setting('app.payment_match_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO match_row FROM app.payment_matches WHERE id = p_payment_match_id FOR UPDATE;
  IF match_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match cannot be approved.'; END IF;
  IF match_row.status = 'APPROVED' THEN
    SELECT * INTO sync_row FROM app.payment_request_amounts(match_row.payment_request_id);
    payment_match_id := match_row.id; status := match_row.status; payment_request_id := match_row.payment_request_id; paid_amount := sync_row.paid_amount; remaining_amount := sync_row.remaining_amount; request_status := (SELECT pr.status FROM app.payment_requests pr WHERE pr.id = match_row.payment_request_id); RETURN NEXT; RETURN;
  END IF;
  IF match_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match cannot be approved.'; END IF;
  IF match_row.matched_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Payment match requires different Owner approval.'; END IF;

  PERFORM app.lock_payment_economic_chain(match_row.client_payment_id);
  PERFORM 1 FROM app.client_payments WHERE id = match_row.client_payment_id FOR UPDATE;
  PERFORM 1 FROM app.payment_requests WHERE id = match_row.payment_request_id FOR UPDATE;
  SELECT * INTO rel_row FROM app.validate_payment_match_relationship(match_row.client_payment_id, match_row.payment_request_id, match_row.matched_amount);

  PERFORM 1 FROM app.payment_matches pm_lock WHERE pm_lock.client_payment_id = match_row.client_payment_id AND pm_lock.status = 'APPROVED' AND pm_lock.is_active ORDER BY pm_lock.id FOR UPDATE;
  PERFORM 1 FROM app.payment_matches pm_lock WHERE pm_lock.payment_request_id = match_row.payment_request_id AND pm_lock.status = 'APPROVED' AND pm_lock.is_active ORDER BY pm_lock.id FOR UPDATE;
  SELECT coalesce(sum(pm.matched_amount),0)::numeric(20,6) INTO payment_total FROM app.payment_matches pm WHERE pm.client_payment_id = match_row.client_payment_id AND pm.status = 'APPROVED' AND pm.is_active AND app.client_payment_economically_active(pm.client_payment_id);
  SELECT amount_check.paid_amount INTO request_total
  FROM app.payment_request_amounts(match_row.payment_request_id) AS amount_check;
  IF payment_total + match_row.matched_amount > rel_row.payment_amount OR request_total + match_row.matched_amount > rel_row.request_amount THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match exceeds available amount.';
  END IF;

  PERFORM set_config('app.payment_match_context', 'payment_match_owner_mutation', true);
  UPDATE app.payment_matches SET status = 'APPROVED', approved_at = now(), approved_by = actor_row.actor_user_id, is_active = true WHERE id = match_row.id RETURNING * INTO match_row;
  PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true);

  SELECT * INTO sync_row FROM app.sync_payment_request_status_from_matches(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, match_row.payment_request_id, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_match_approved', 'payment_match', match_row.id, rel_row.project_id, 'success', jsonb_build_object('status','DRAFT'), jsonb_build_object('client_payment_id', match_row.client_payment_id, 'payment_request_id', match_row.payment_request_id, 'project_id', rel_row.project_id, 'client_id', rel_row.client_id, 'currency_code', match_row.currency_code, 'matched_amount', match_row.matched_amount, 'status','APPROVED'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_balance_recalculated', 'payment_request', match_row.payment_request_id, rel_row.project_id, 'success', '{}'::jsonb, jsonb_build_object('client_payment_id', match_row.client_payment_id, 'payment_match_id', match_row.id, 'paid_amount', sync_row.paid_amount, 'remaining_amount', sync_row.remaining_amount, 'currency_code', match_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  payment_match_id := match_row.id; status := match_row.status; payment_request_id := match_row.payment_request_id; paid_amount := sync_row.paid_amount; remaining_amount := sync_row.remaining_amount; request_status := sync_row.status; RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_void_payment_match(p_actor_auth_subject uuid, p_payment_match_id uuid, p_void_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, payment_request_id uuid, paid_amount numeric, remaining_amount numeric, request_status app.payment_request_status)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE actor_row record; match_row app.payment_matches%ROWTYPE; rel_row record; sync_row record; reason_text text := btrim(coalesce(p_void_reason,'')); previous_context text := current_setting('app.payment_match_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  SELECT * INTO match_row FROM app.payment_matches WHERE id = p_payment_match_id FOR UPDATE;
  IF match_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match cannot be voided.'; END IF;
  IF match_row.status = 'VOIDED' THEN
    SELECT * INTO sync_row FROM app.payment_request_amounts(match_row.payment_request_id);
    payment_match_id := match_row.id; status := match_row.status; payment_request_id := match_row.payment_request_id; paid_amount := sync_row.paid_amount; remaining_amount := sync_row.remaining_amount; request_status := (SELECT pr.status FROM app.payment_requests pr WHERE pr.id = match_row.payment_request_id); RETURN NEXT; RETURN;
  END IF;
  IF match_row.status NOT IN ('DRAFT','APPROVED') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match cannot be voided.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Void reason is required.'; END IF;

  PERFORM app.lock_payment_economic_chain(match_row.client_payment_id);
  PERFORM 1 FROM app.client_payments WHERE id = match_row.client_payment_id FOR UPDATE;
  PERFORM 1 FROM app.payment_requests WHERE id = match_row.payment_request_id FOR UPDATE;
  SELECT * INTO rel_row FROM app.validate_payment_match_relationship(match_row.client_payment_id, match_row.payment_request_id, match_row.matched_amount);

  PERFORM set_config('app.payment_match_context', 'payment_match_owner_mutation', true);
  UPDATE app.payment_matches SET status = 'VOIDED', is_active = false, voided_at = now(), voided_by = actor_row.actor_user_id, void_reason = reason_text WHERE id = match_row.id RETURNING * INTO match_row;
  PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true);

  SELECT * INTO sync_row FROM app.sync_payment_request_status_from_matches(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, match_row.payment_request_id, p_request_identifier, p_correlation_identifier, p_session_identifier, p_ip_address);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_match_voided', 'payment_match', match_row.id, rel_row.project_id, 'success', jsonb_build_object('status', CASE WHEN match_row.approved_at IS NULL THEN 'DRAFT' ELSE 'APPROVED' END), jsonb_build_object('client_payment_id', match_row.client_payment_id, 'payment_request_id', match_row.payment_request_id, 'project_id', rel_row.project_id, 'client_id', rel_row.client_id, 'currency_code', match_row.currency_code, 'matched_amount', match_row.matched_amount, 'status','VOIDED'), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided', true));
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_balance_recalculated', 'payment_request', match_row.payment_request_id, rel_row.project_id, 'success', '{}'::jsonb, jsonb_build_object('client_payment_id', match_row.client_payment_id, 'payment_match_id', match_row.id, 'paid_amount', sync_row.paid_amount, 'remaining_amount', sync_row.remaining_amount, 'currency_code', match_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  payment_match_id := match_row.id; status := match_row.status; payment_request_id := match_row.payment_request_id; paid_amount := sync_row.paid_amount; remaining_amount := sync_row.remaining_amount; request_status := sync_row.status; RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_match_context', coalesce(previous_context, ''), true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_payment_match_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (payment_match_id uuid, client_payment_id uuid, payment_request_id uuid, project_id uuid, client_id uuid, matched_amount numeric, currency_code char(3), matched_at timestamptz, status app.payment_match_status, approved_at timestamptz, voided_at timestamptz, matched_by uuid, approved_by uuid, voided_by uuid, is_active boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pm.id, pm.client_payment_id, pm.payment_request_id, cp.project_id, cp.client_id, pm.matched_amount, pm.currency_code, pm.matched_at, pm.status, pm.approved_at, pm.voided_at, pm.matched_by, pm.approved_by, pm.voided_by, pm.is_active FROM app.payment_matches pm JOIN app.client_payments cp ON cp.id=pm.client_payment_id ORDER BY pm.matched_at DESC, pm.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_payment_match_detail(p_actor_auth_subject uuid, p_payment_match_id uuid)
RETURNS TABLE (payment_match_id uuid, client_payment_id uuid, payment_request_id uuid, project_id uuid, client_id uuid, matched_amount numeric, currency_code char(3), matched_at timestamptz, status app.payment_match_status, approved_at timestamptz, approved_by uuid, voided_at timestamptz, voided_by uuid, void_reason text, matched_by uuid, is_active boolean, payment_available_amount numeric, request_paid_amount numeric, request_remaining_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pm.id, pm.client_payment_id, pm.payment_request_id, cp.project_id, cp.client_id, pm.matched_amount, pm.currency_code, pm.matched_at, pm.status, pm.approved_at, pm.approved_by, pm.voided_at, pm.voided_by, pm.void_reason, pm.matched_by, pm.is_active, ava.unmatched_amount, amt.paid_amount, amt.remaining_amount FROM app.payment_matches pm JOIN app.client_payments cp ON cp.id=pm.client_payment_id CROSS JOIN LATERAL app.owner_client_payment_availability(p_actor_auth_subject, pm.client_payment_id) ava CROSS JOIN LATERAL app.payment_request_amounts(pm.payment_request_id) amt WHERE pm.id=p_payment_match_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_refresh_payment_request_overdue(p_actor_auth_subject uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; request_row app.payment_requests%ROWTYPE; amount_row record; calculated app.payment_request_status; previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  FOR request_row IN SELECT pr.* FROM app.payment_requests AS pr WHERE pr.status NOT IN ('DRAFT','CANCELLED') ORDER BY pr.due_date NULLS LAST, pr.id FOR UPDATE LOOP
    SELECT * INTO amount_row FROM app.payment_request_amounts(request_row.id);
    calculated := app.payment_request_calculated_status(request_row.status, request_row.requested_amount, request_row.due_date, request_row.viewed_at, amount_row.paid_amount, amount_row.remaining_amount);
    IF calculated IS DISTINCT FROM request_row.status THEN
      PERFORM set_config('app.payment_request_context','payment_request_overdue_refresh',true);
      UPDATE app.payment_requests SET status=calculated, updated_by=actor_row.actor_user_id WHERE id=request_row.id RETURNING id, app.payment_requests.request_number::text, app.payment_requests.status, app.payment_requests.version_number INTO payment_request_id, request_number, status, version_number;
      PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
      PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_marked_overdue', 'payment_request', payment_request_id, NULL, 'success', jsonb_build_object('status',request_row.status::text,'version_number',request_row.version_number), jsonb_build_object('request_number',request_number,'project_id',request_row.project_id,'client_id',request_row.client_id,'currency_code',request_row.currency_code,'status',status::text,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
      RETURN NEXT;
    END IF;
  END LOOP;
  PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_payment_request_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, client_id uuid, requested_amount numeric, currency_code char(3), request_date date, due_date date, status app.payment_request_status, effective_status app.payment_request_status, sent_at timestamptz, viewed_at timestamptz, cancelled_at timestamptz, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, pr.client_id, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.status, app.payment_request_calculated_status(pr.status, pr.requested_amount, pr.due_date, pr.viewed_at, a.paid_amount, a.remaining_amount), pr.sent_at, pr.viewed_at, pr.cancelled_at, pr.version_number FROM app.payment_requests pr CROSS JOIN LATERAL app.payment_request_amounts(pr.id) a ORDER BY pr.created_at DESC, pr.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_payment_request_detail(p_actor_auth_subject uuid, p_payment_request_id uuid)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, client_id uuid, requested_amount numeric, currency_code char(3), request_date date, due_date date, status app.payment_request_status, effective_status app.payment_request_status, description text, sent_at timestamptz, viewed_at timestamptz, cancelled_at timestamptz, cancelled_by uuid, cancellation_reason text, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer, paid_amount numeric, remaining_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, pr.client_id, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.status, app.payment_request_calculated_status(pr.status, pr.requested_amount, pr.due_date, pr.viewed_at, a.paid_amount, a.remaining_amount), pr.description, pr.sent_at, pr.viewed_at, pr.cancelled_at, pr.cancelled_by, pr.cancellation_reason, pr.created_at, pr.created_by, pr.updated_at, pr.updated_by, pr.version_number, a.paid_amount, a.remaining_amount FROM app.payment_requests pr CROSS JOIN LATERAL app.payment_request_amounts(pr.id) a WHERE pr.id=p_payment_request_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_payment_request_list(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, project_number text, requested_amount numeric, currency_code char(3), request_date date, due_date date, description text, sent_at timestamptz, viewed_at timestamptz, status app.payment_request_status, effective_status app.payment_request_status, paid_amount numeric, remaining_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE client_ctx record; safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  SELECT * INTO client_ctx FROM app.current_payment_request_client_context();
  IF client_ctx.client_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, p.project_number::text, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.description, pr.sent_at, pr.viewed_at, pr.status, app.payment_request_calculated_status(pr.status, pr.requested_amount, pr.due_date, pr.viewed_at, a.paid_amount, a.remaining_amount), a.paid_amount, a.remaining_amount FROM app.payment_requests pr JOIN app.projects p ON p.id=pr.project_id CROSS JOIN LATERAL app.payment_request_amounts(pr.id) a WHERE pr.client_id=client_ctx.client_id AND p.client_id=client_ctx.client_id AND pr.status IN ('SENT','VIEWED','OVERDUE','CANCELLED','PARTIALLY_PAID','PAID') AND pr.sent_at IS NOT NULL ORDER BY pr.request_date DESC, pr.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_view_payment_request_detail(p_payment_request_id uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, project_number text, requested_amount numeric, currency_code char(3), request_date date, due_date date, description text, sent_at timestamptz, viewed_at timestamptz, status app.payment_request_status, effective_status app.payment_request_status, paid_amount numeric, remaining_amount numeric)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE client_ctx record; request_row app.payment_requests%ROWTYPE; amount_row record; effective app.payment_request_status; prior_version integer; previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO client_ctx FROM app.current_payment_request_client_context();
  IF client_ctx.client_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  SELECT pr.* INTO request_row FROM app.payment_requests pr JOIN app.projects p ON p.id=pr.project_id WHERE pr.id=p_payment_request_id AND pr.client_id=client_ctx.client_id AND p.client_id=client_ctx.client_id FOR UPDATE;
  IF request_row.id IS NULL OR request_row.status = 'DRAFT' OR request_row.sent_at IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  SELECT * INTO amount_row FROM app.payment_request_amounts(request_row.id);
  effective := app.payment_request_calculated_status(request_row.status, request_row.requested_amount, request_row.due_date, request_row.viewed_at, amount_row.paid_amount, amount_row.remaining_amount);
  prior_version := request_row.version_number;
  IF request_row.viewed_at IS NULL THEN
    PERFORM set_config('app.payment_request_context','payment_request_client_view',true);
    UPDATE app.payment_requests SET viewed_at = now(), status = CASE WHEN request_row.status='SENT' AND effective <> 'OVERDUE' THEN 'VIEWED'::app.payment_request_status ELSE request_row.status END, updated_by = client_ctx.user_id WHERE id=request_row.id RETURNING * INTO request_row;
    PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
    PERFORM app.write_activity_log(client_ctx.user_id, client_ctx.auth_subject, 'client', 'payment_request_viewed', 'payment_request', request_row.id, NULL, 'success', jsonb_build_object('status', effective::text, 'version_number', prior_version), jsonb_build_object('request_number', request_row.request_number::text, 'project_id', request_row.project_id, 'client_id', request_row.client_id, 'currency_code', request_row.currency_code, 'status', request_row.status::text, 'version_number', request_row.version_number), NULL, NULL, NULL, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, p.project_number::text, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.description, pr.sent_at, pr.viewed_at, pr.status, app.payment_request_calculated_status(pr.status, pr.requested_amount, pr.due_date, pr.viewed_at, a.paid_amount, a.remaining_amount), a.paid_amount, a.remaining_amount FROM app.payment_requests pr JOIN app.projects p ON p.id=pr.project_id CROSS JOIN LATERAL app.payment_request_amounts(pr.id) a WHERE pr.id=request_row.id;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_payment_match(p_verified_owner_auth_subject uuid, p_client_payment_id uuid, p_payment_request_id uuid, p_matched_amount numeric, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, matched_amount numeric, currency_code char(3)) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_payment_match(p_verified_owner_auth_subject,p_client_payment_id,p_payment_request_id,p_matched_amount,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_payment_match(p_verified_owner_auth_subject uuid, p_payment_match_id uuid, p_expected_client_payment_id uuid, p_expected_payment_request_id uuid, p_expected_matched_amount numeric, p_client_payment_id uuid, p_payment_request_id uuid, p_matched_amount numeric, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, matched_amount numeric, currency_code char(3)) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_payment_match(p_verified_owner_auth_subject,p_payment_match_id,p_expected_client_payment_id,p_expected_payment_request_id,p_expected_matched_amount,p_client_payment_id,p_payment_request_id,p_matched_amount,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_payment_match(p_verified_owner_auth_subject uuid, p_payment_match_id uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, payment_request_id uuid, paid_amount numeric, remaining_amount numeric, request_status app.payment_request_status) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_payment_match(p_verified_owner_auth_subject,p_payment_match_id,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_void_payment_match(p_verified_owner_auth_subject uuid, p_payment_match_id uuid, p_void_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_match_id uuid, status app.payment_match_status, payment_request_id uuid, paid_amount numeric, remaining_amount numeric, request_status app.payment_request_status) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_void_payment_match(p_verified_owner_auth_subject,p_payment_match_id,p_void_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_payment_match_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (payment_match_id uuid, client_payment_id uuid, payment_request_id uuid, project_id uuid, client_id uuid, matched_amount numeric, currency_code char(3), matched_at timestamptz, status app.payment_match_status, approved_at timestamptz, voided_at timestamptz, matched_by uuid, approved_by uuid, voided_by uuid, is_active boolean) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_payment_match_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_payment_match_detail(p_verified_owner_auth_subject uuid, p_payment_match_id uuid) RETURNS TABLE (payment_match_id uuid, client_payment_id uuid, payment_request_id uuid, project_id uuid, client_id uuid, matched_amount numeric, currency_code char(3), matched_at timestamptz, status app.payment_match_status, approved_at timestamptz, approved_by uuid, voided_at timestamptz, voided_by uuid, void_reason text, matched_by uuid, is_active boolean, payment_available_amount numeric, request_paid_amount numeric, request_remaining_amount numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_payment_match_detail(p_verified_owner_auth_subject,p_payment_match_id); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_client_payment_availability(p_verified_owner_auth_subject uuid, p_client_payment_id uuid) RETURNS TABLE (client_payment_id uuid, payment_amount numeric, approved_active_matched_amount numeric, unmatched_amount numeric, economically_active boolean, eligible_for_matching boolean) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_client_payment_availability(p_verified_owner_auth_subject,p_client_payment_id); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_payment_request_balance(p_verified_owner_auth_subject uuid, p_payment_request_id uuid) RETURNS TABLE (payment_request_id uuid, request_number text, requested_amount numeric, paid_amount numeric, remaining_amount numeric, status app.payment_request_status, effective_status app.payment_request_status) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_payment_request_balance(p_verified_owner_auth_subject,p_payment_request_id); $function$;

COMMIT;
