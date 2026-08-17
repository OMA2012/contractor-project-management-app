BEGIN;

ALTER TABLE app.financial_reversals
  DROP CONSTRAINT IF EXISTS financial_reversals_original_transaction_uk;

CREATE OR REPLACE FUNCTION app.owner_financial_correction_source_list(
  p_actor_auth_subject uuid,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  financial_event_id uuid,
  event_number text,
  event_type text,
  financial_transaction_id uuid,
  transaction_number text,
  amount numeric,
  currency_code char(3),
  event_date date,
  label text,
  can_reverse boolean,
  can_adjust boolean,
  reversal_recorded boolean,
  adjustment_recorded boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  RETURN QUERY
  WITH posted AS (
    SELECT fe.id AS financial_event_id, fe.event_number::text AS event_number, fe.event_type::text AS event_type, ft.id AS financial_transaction_id, ft.transaction_number::text AS transaction_number, ob.amount, ob.currency_code, fe.event_date, 'Opening Balance ' || fe.event_number::text || ' / ' || ft.transaction_number::text AS label
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.account_opening_balances ob ON ob.financial_event_id = fe.id
    WHERE fe.status = 'APPROVED' AND ft.status = 'POSTED' AND fe.event_type = 'OPENING_BALANCE'
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, cp.amount, cp.currency_code, fe.event_date, 'Client Payment ' || fe.event_number::text || ' / ' || ft.transaction_number::text
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.client_payments cp ON cp.financial_event_id = fe.id
    WHERE fe.status = 'APPROVED' AND ft.status = 'POSTED' AND fe.event_type = 'CLIENT_PAYMENT'
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, pe.amount, pe.currency_code, fe.event_date, 'Project Expense ' || fe.event_number::text || ' / ' || ft.transaction_number::text
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.project_expenses pe ON pe.financial_event_id = fe.id
    WHERE fe.status = 'APPROVED' AND ft.status = 'POSTED' AND fe.event_type = 'PROJECT_EXPENSE'
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, at.amount, at.currency_code, fe.event_date, 'Account Transfer ' || fe.event_number::text || ' / ' || ft.transaction_number::text
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.account_transfers at ON at.financial_event_id = fe.id
    WHERE fe.status = 'APPROVED' AND ft.status = 'POSTED' AND fe.event_type = 'ACCOUNT_TRANSFER'
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, ce.source_amount, ce.source_currency_code, fe.event_date, 'Currency Exchange ' || fe.event_number::text || ' / ' || ft.transaction_number::text
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.currency_exchanges ce ON ce.financial_event_id = fe.id
    WHERE fe.status = 'APPROVED' AND ft.status = 'POSTED' AND fe.event_type = 'CURRENCY_EXCHANGE'
  )
  SELECT
    p.financial_event_id,
    p.event_number,
    p.event_type,
    p.financial_transaction_id,
    p.transaction_number,
    p.amount,
    p.currency_code,
    p.event_date,
    p.label,
    NOT EXISTS (
      SELECT 1
      FROM app.financial_reversals fr
      JOIN app.financial_events rfe ON rfe.id = fr.financial_event_id
      JOIN app.financial_transactions rft ON rft.financial_event_id = rfe.id
      WHERE fr.original_transaction_id = p.financial_transaction_id
        AND rfe.status <> 'REJECTED'
        AND rft.status <> 'REJECTED'
    ) AS can_reverse,
    true AS can_adjust,
    EXISTS (
      SELECT 1
      FROM app.financial_reversals fr
      JOIN app.financial_events rfe ON rfe.id = fr.financial_event_id
      JOIN app.financial_transactions rft ON rft.financial_event_id = rfe.id
      WHERE fr.original_transaction_id = p.financial_transaction_id
        AND rfe.status = 'APPROVED'
        AND rft.status = 'POSTED'
    ) AS reversal_recorded,
    EXISTS (
      SELECT 1
      FROM app.financial_adjustments fa
      JOIN app.financial_events afe ON afe.id = fa.financial_event_id
      JOIN app.financial_transactions aft ON aft.financial_event_id = afe.id
      WHERE fa.adjusted_transaction_id = p.financial_transaction_id
        AND afe.status = 'APPROVED'
        AND aft.status = 'POSTED'
    ) AS adjustment_recorded
  FROM posted p
  ORDER BY p.event_date DESC, p.financial_event_id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

COMMIT;
