BEGIN;

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
  WITH queue_rows (
    financial_event_id, event_number, event_type, financial_transaction_id,
    transaction_number, related_label, amount, currency_code, event_date,
    event_status, transaction_status, created_by_me,
    eligible_for_my_approval, submitted_at, approved_at, rejected_at,
    rejection_reason, version_number
  ) AS (
    SELECT
      fe.id, fe.event_number::text, fe.event_type::text, ft.id,
      ft.transaction_number::text,
      coalesce(fa.name || ' (' || fa.account_number || ')', fe.description, fe.event_type::text),
      ob.amount, ob.currency_code, fe.event_date, fe.status::text,
      ft.status::text, fe.created_by = actor_row.actor_user_id,
      fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id,
      fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason,
      fe.version_number
    FROM app.financial_events fe
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    JOIN app.account_opening_balances ob ON ob.financial_event_id = fe.id
    JOIN app.financial_accounts fa ON fa.id = ob.financial_account_id
    WHERE fe.event_type = 'OPENING_BALANCE'
    UNION ALL
    SELECT
      fe.id, fe.event_number::text, fe.event_type::text, ft.id,
      ft.transaction_number::text,
      'Project ' || cp.project_id::text || ' / Client ' || cp.client_id::text,
      cp.amount, cp.currency_code, fe.event_date, fe.status::text,
      ft.status::text, fe.created_by = actor_row.actor_user_id,
      fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id,
      fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason,
      fe.version_number
    FROM app.financial_events fe
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    JOIN app.client_payments cp ON cp.financial_event_id = fe.id
    WHERE fe.event_type = 'CLIENT_PAYMENT'
    UNION ALL
    SELECT
      fe.id, fe.event_number::text, fe.event_type::text, ft.id,
      ft.transaction_number::text,
      'Project ' || pe.project_id::text || ' / Account ' || fa.name,
      pe.amount, pe.currency_code, fe.event_date, fe.status::text,
      ft.status::text, fe.created_by = actor_row.actor_user_id,
      fe.status = 'SUBMITTED' AND fe.created_by <> actor_row.actor_user_id,
      fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason,
      fe.version_number
    FROM app.financial_events fe
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    JOIN app.project_expenses pe ON pe.financial_event_id = fe.id
    JOIN app.financial_accounts fa ON fa.id = pe.paid_from_account_id
    WHERE fe.event_type = 'PROJECT_EXPENSE'
  )
  SELECT q.*
  FROM queue_rows q
  WHERE (
    (section = 'eligible' AND q.event_status = 'SUBMITTED' AND q.eligible_for_my_approval)
    OR (section = 'created_by_me' AND q.event_status = 'SUBMITTED' AND q.created_by_me)
    OR (section = 'recent' AND q.event_status = 'APPROVED')
    OR (section = 'rejected' AND q.event_status = 'REJECTED')
  )
  ORDER BY coalesce(q.submitted_at, q.approved_at, q.rejected_at) DESC, q.financial_event_id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_financial_approval_queue(
  p_verified_owner_auth_subject uuid,
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_financial_approval_queue(p_verified_owner_auth_subject, p_section, p_limit, p_offset);
$function$;

REVOKE ALL ON FUNCTION app.owner_financial_approval_queue(uuid, text, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_owner_financial_approval_queue(uuid, text, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_owner_financial_approval_queue(uuid, text, integer, integer) TO service_role;

COMMIT;
