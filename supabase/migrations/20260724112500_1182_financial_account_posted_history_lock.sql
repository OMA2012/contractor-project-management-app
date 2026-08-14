BEGIN;

CREATE OR REPLACE FUNCTION app.financial_account_has_posted_history(p_financial_account_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app.ledger_accounts AS la
    JOIN app.ledger_entries AS le
      ON le.ledger_account_id = la.id
    JOIN app.financial_transactions AS ft
      ON ft.id = le.financial_transaction_id
    WHERE la.financial_account_id = p_financial_account_id
      AND la.account_kind = 'FINANCIAL_ASSET'
      AND ft.status = 'POSTED'
  );
$function$;

CREATE OR REPLACE FUNCTION app.financial_accounts_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.account_number IS DISTINCT FROM OLD.account_number THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account number is immutable.';
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account creation fields are immutable.';
  END IF;

  IF OLD.archived_at IS NOT NULL AND NEW.archived_at IS DISTINCT FROM OLD.archived_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account archive timestamp is immutable.';
  END IF;

  IF OLD.archived_by IS NOT NULL AND NEW.archived_by IS DISTINCT FROM OLD.archived_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account archive actor is immutable.';
  END IF;

  IF (
    NEW.account_type IS DISTINCT FROM OLD.account_type
    OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
  ) AND app.financial_account_has_posted_history(OLD.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account type and currency are immutable after posted financial history.';
  END IF;

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION app.financial_account_has_posted_history(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.financial_accounts_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
