BEGIN;

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
    SELECT
      fe.id AS financial_event_id,
      fe.event_number::text AS event_number,
      fe.event_type::text AS event_type,
      ft.id AS financial_transaction_id,
      ft.transaction_number::text AS transaction_number,
      fe.event_date,
      abs(sum(le.debit_amount - le.credit_amount))::numeric AS amount,
      min(le.currency_code)::char(3) AS currency_code
    FROM app.financial_events fe
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    JOIN app.ledger_entries le ON le.financial_transaction_id = ft.id
    WHERE fe.status = 'APPROVED'
      AND ft.status = 'POSTED'
      AND fe.event_type IN ('OPENING_BALANCE', 'CLIENT_PAYMENT', 'PROJECT_EXPENSE', 'ACCOUNT_TRANSFER', 'CURRENCY_EXCHANGE')
    GROUP BY fe.id, ft.id
    HAVING count(DISTINCT le.currency_code) = 1
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
    p.event_type || ' ' || p.event_number || ' / ' || p.transaction_number,
    NOT EXISTS (
      SELECT 1
      FROM app.financial_reversals fr
      JOIN app.financial_events rfe ON rfe.id = fr.financial_event_id
      JOIN app.financial_transactions rft ON rft.financial_event_id = rfe.id
      WHERE fr.original_transaction_id = p.financial_transaction_id
        AND rfe.status <> 'REJECTED'
        AND rft.status <> 'REJECTED'
    ),
    true,
    EXISTS (
      SELECT 1
      FROM app.financial_reversals fr
      JOIN app.financial_events rfe ON rfe.id = fr.financial_event_id
      JOIN app.financial_transactions rft ON rft.financial_event_id = rfe.id
      WHERE fr.original_transaction_id = p.financial_transaction_id
        AND rfe.status = 'APPROVED'
        AND rft.status = 'POSTED'
    ),
    EXISTS (
      SELECT 1
      FROM app.financial_adjustments fa
      JOIN app.financial_events afe ON afe.id = fa.financial_event_id
      JOIN app.financial_transactions aft ON aft.financial_event_id = afe.id
      WHERE fa.adjusted_transaction_id = p.financial_transaction_id
        AND afe.status = 'APPROVED'
        AND aft.status = 'POSTED'
    )
  FROM posted p
  ORDER BY p.event_date DESC, p.financial_event_id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_financial_correction_source_list(
  p_verified_owner_auth_subject uuid,
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_financial_correction_source_list(p_verified_owner_auth_subject, p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION app.owner_financial_approval_queue(
  p_actor_auth_subject uuid,
  p_section text DEFAULT 'eligible',
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  financial_event_id uuid,
  event_number text,
  event_type text,
  financial_transaction_id uuid,
  transaction_number text,
  related_label text,
  amount numeric,
  currency_code char(3),
  event_date date,
  event_status text,
  transaction_status text,
  created_by_me boolean,
  eligible_for_my_approval boolean,
  submitted_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  rejection_reason text,
  version_number integer
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
  section text := lower(coalesce(p_section, 'eligible'));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF section NOT IN ('eligible', 'created_by_me', 'recent', 'rejected') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial approval queue section is invalid.';
  END IF;

  RETURN QUERY
  WITH queue_rows AS (
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id AS ft_id, ft.transaction_number::text, coalesce(fa.name || ' (' || fa.account_number || ')', fe.description, fe.event_type::text) AS label, ob.amount, ob.currency_code, fe.event_date, fe.status::text AS event_status, ft.status::text AS transaction_status, fe.created_by = actor_row.actor_user_id AS created_by_me, fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id AS eligible_for_my_approval, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.account_opening_balances ob ON ob.financial_event_id = fe.id JOIN app.financial_accounts fa ON fa.id = ob.financial_account_id WHERE fe.event_type = 'OPENING_BALANCE'
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, 'Project ' || cp.project_id::text || ' / Client ' || cp.client_id::text, cp.amount, cp.currency_code, fe.event_date, fe.status::text, ft.status::text, fe.created_by = actor_row.actor_user_id, fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.client_payments cp ON cp.financial_event_id = fe.id WHERE fe.event_type = 'CLIENT_PAYMENT'
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, 'Project ' || pe.project_id::text || ' / Account ' || fa.name, pe.amount, pe.currency_code, fe.event_date, fe.status::text, ft.status::text, fe.created_by = actor_row.actor_user_id, fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.project_expenses pe ON pe.financial_event_id = fe.id JOIN app.financial_accounts fa ON fa.id = pe.paid_from_account_id WHERE fe.event_type = 'PROJECT_EXPENSE'
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, 'Reversal of ' || original_ft.transaction_number::text, abs(sum(le.debit_amount - le.credit_amount))::numeric, min(le.currency_code)::char(3), fe.event_date, fe.status::text, ft.status::text, fe.created_by = actor_row.actor_user_id, fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.financial_reversals fr ON fr.financial_event_id = fe.id JOIN app.financial_transactions original_ft ON original_ft.id = fr.original_transaction_id LEFT JOIN app.ledger_entries le ON le.financial_transaction_id = original_ft.id WHERE fe.event_type = 'REVERSAL' GROUP BY fe.id, ft.id, original_ft.transaction_number
    UNION ALL
    SELECT fe.id, fe.event_number::text, fe.event_type::text, ft.id, ft.transaction_number::text, 'Adjustment ' || fa.direction::text || ' ' || acct.name, fa.amount, fa.currency_code, fe.event_date, fe.status::text, ft.status::text, fe.created_by = actor_row.actor_user_id, fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number
    FROM app.financial_events fe JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id JOIN app.financial_adjustments fa ON fa.financial_event_id = fe.id JOIN app.financial_accounts acct ON acct.id = fa.financial_account_id WHERE fe.event_type = 'ADJUSTMENT'
  )
  SELECT q.id, q.event_number, q.event_type, q.ft_id, q.transaction_number, q.label, q.amount, q.currency_code, q.event_date, q.event_status, q.transaction_status, q.created_by_me, q.eligible_for_my_approval, q.submitted_at, q.approved_at, q.rejected_at, q.rejection_reason, q.version_number
  FROM queue_rows q
  WHERE (
    (section = 'eligible' AND q.event_status = 'SUBMITTED' AND q.eligible_for_my_approval)
    OR (section = 'created_by_me' AND q.event_status = 'SUBMITTED' AND q.created_by_me)
    OR (section = 'recent' AND q.event_status = 'APPROVED')
    OR (section = 'rejected' AND q.event_status = 'REJECTED')
  )
  ORDER BY coalesce(q.submitted_at, q.approved_at, q.rejected_at) DESC, q.id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

REVOKE ALL ON FUNCTION app.owner_financial_correction_source_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_owner_financial_correction_source_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_owner_financial_correction_source_list(uuid, integer, integer) TO service_role;

COMMIT;
