BEGIN;

CREATE TYPE app.adjustment_direction AS ENUM ('INCREASE', 'DECREASE');

CREATE TABLE app.financial_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id uuid NOT NULL,
  original_transaction_id uuid NOT NULL,
  reason text NOT NULL,
  full_reversal boolean NOT NULL DEFAULT true,
  reversal_date date NOT NULL,
  CONSTRAINT financial_reversals_event_uk UNIQUE (financial_event_id),
  CONSTRAINT financial_reversals_original_transaction_uk UNIQUE (original_transaction_id),
  CONSTRAINT financial_reversals_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT financial_reversals_original_transaction_fk FOREIGN KEY (original_transaction_id) REFERENCES app.financial_transactions(id) ON DELETE RESTRICT,
  CONSTRAINT financial_reversals_reason_ck CHECK (btrim(reason) <> ''),
  CONSTRAINT financial_reversals_full_only_ck CHECK (full_reversal IS TRUE)
);

CREATE TABLE app.financial_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id uuid NOT NULL,
  adjusted_transaction_id uuid,
  financial_account_id uuid NOT NULL,
  direction app.adjustment_direction NOT NULL,
  amount numeric(20,6) NOT NULL,
  currency_code char(3) NOT NULL,
  adjustment_date date NOT NULL,
  reason text NOT NULL,
  CONSTRAINT financial_adjustments_event_uk UNIQUE (financial_event_id),
  CONSTRAINT financial_adjustments_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT financial_adjustments_adjusted_transaction_fk FOREIGN KEY (adjusted_transaction_id) REFERENCES app.financial_transactions(id) ON DELETE RESTRICT,
  CONSTRAINT financial_adjustments_financial_account_fk FOREIGN KEY (financial_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT financial_adjustments_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT financial_adjustments_amount_ck CHECK (amount > 0),
  CONSTRAINT financial_adjustments_reason_ck CHECK (btrim(reason) <> '')
);

CREATE INDEX financial_reversals_original_transaction_idx ON app.financial_reversals(original_transaction_id);
CREATE INDEX financial_adjustments_adjusted_transaction_idx ON app.financial_adjustments(adjusted_transaction_id) WHERE adjusted_transaction_id IS NOT NULL;
CREATE INDEX financial_adjustments_financial_account_date_idx ON app.financial_adjustments(financial_account_id, adjustment_date DESC);

CREATE OR REPLACE FUNCTION app.financial_reversals_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  original_row app.financial_transactions%ROWTYPE;
BEGIN
  IF current_setting('app.financial_transaction_context', true) IS DISTINCT FROM 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversals require trusted functions.';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id
       OR NEW.original_transaction_id IS DISTINCT FROM OLD.original_transaction_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversal identity fields are immutable.';
    END IF;
  END IF;

  SELECT * INTO event_row FROM app.financial_events WHERE id = NEW.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = NEW.financial_event_id;
  SELECT * INTO original_row FROM app.financial_transactions WHERE id = NEW.original_transaction_id;

  IF event_row.id IS NULL OR transaction_row.id IS NULL OR original_row.id IS NULL OR event_row.event_type <> 'REVERSAL' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial reversal.';
  END IF;
  IF original_row.status <> 'POSTED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Original transaction must be posted.';
  END IF;
  IF original_row.id = transaction_row.id THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Reversal cannot target itself.';
  END IF;
  IF NEW.reversal_date IS DISTINCT FROM event_row.event_date OR NEW.reversal_date IS DISTINCT FROM transaction_row.transaction_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Reversal date must match event and transaction dates.';
  END IF;
  IF NEW.full_reversal IS DISTINCT FROM true THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Only full reversals are supported.';
  END IF;
  IF TG_OP = 'INSERT' AND EXISTS (
    SELECT 1
    FROM app.financial_reversals fr
    JOIN app.financial_events fe ON fe.id = fr.financial_event_id
    JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id
    WHERE fr.original_transaction_id = NEW.original_transaction_id
      AND fr.full_reversal
      AND fe.status <> 'REJECTED'
      AND ft.status <> 'REJECTED'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Original transaction already has a full reversal.';
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.financial_adjustments_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  adjusted_row app.financial_transactions%ROWTYPE;
  account_row app.financial_accounts%ROWTYPE;
  asset_row app.ledger_accounts%ROWTYPE;
BEGIN
  IF current_setting('app.financial_transaction_context', true) IS DISTINCT FROM 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial adjustments require trusted functions.';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial adjustment identity fields are immutable.';
    END IF;
  END IF;

  SELECT * INTO event_row FROM app.financial_events WHERE id = NEW.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = NEW.financial_event_id;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id = NEW.financial_account_id;
  SELECT * INTO asset_row FROM app.ledger_accounts WHERE financial_account_id = NEW.financial_account_id AND account_kind = 'FINANCIAL_ASSET';

  IF event_row.id IS NULL OR transaction_row.id IS NULL OR account_row.id IS NULL OR asset_row.id IS NULL OR event_row.event_type <> 'ADJUSTMENT' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial adjustment.';
  END IF;
  IF NEW.adjusted_transaction_id IS NOT NULL THEN
    SELECT * INTO adjusted_row FROM app.financial_transactions WHERE id = NEW.adjusted_transaction_id;
    IF adjusted_row.id IS NULL OR adjusted_row.status <> 'POSTED' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Adjusted transaction must be posted.';
    END IF;
    IF adjusted_row.id = transaction_row.id OR adjusted_row.transaction_date > NEW.adjustment_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid adjusted transaction reference.';
    END IF;
  END IF;
  IF NEW.currency_code IS DISTINCT FROM account_row.currency_code OR NEW.currency_code IS DISTINCT FROM asset_row.currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Adjustment currency must match account currency.';
  END IF;
  IF NEW.adjustment_date IS DISTINCT FROM event_row.event_date OR NEW.adjustment_date IS DISTINCT FROM transaction_row.transaction_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Adjustment date must match event and transaction dates.';
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_financial_reversal_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversals cannot be deleted.'; END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_financial_reversal_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial reversals cannot be truncated.'; END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_financial_adjustment_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial adjustments cannot be deleted.'; END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_financial_adjustment_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial adjustments cannot be truncated.'; END
$function$;

CREATE OR REPLACE FUNCTION app.financial_transactions_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  event_row app.financial_events%ROWTYPE;
BEGIN
  IF current_setting('app.financial_transaction_context', true) IS DISTINCT FROM 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial transactions require trusted functions.';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    SELECT * INTO event_row FROM app.financial_events WHERE id = OLD.financial_event_id;
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.transaction_number IS DISTINCT FROM OLD.transaction_number
       OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial transaction identity fields are immutable.';
    END IF;
    IF NEW.reverses_transaction_id IS DISTINCT FROM OLD.reverses_transaction_id
       AND NOT (event_row.event_type = 'REVERSAL' AND OLD.reverses_transaction_id IS NULL AND NEW.reverses_transaction_id IS NOT NULL) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial transaction identity fields are immutable.';
    END IF;
    IF OLD.status IN ('POSTED','REJECTED') AND NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Terminal financial transactions are immutable.';
    END IF;
    NEW.version_number := OLD.version_number + 1;
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.ledger_entries_trusted_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  transaction_row app.financial_transactions%ROWTYPE;
  ledger_row app.ledger_accounts%ROWTYPE;
  posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  IF coalesce(posting_context, '') NOT IN ('opening_balance_posting','financial_reversal_posting','financial_adjustment_posting') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries require trusted posting.';
  END IF;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE id = NEW.financial_transaction_id;
  SELECT * INTO ledger_row FROM app.ledger_accounts WHERE id = NEW.ledger_account_id;
  IF transaction_row.id IS NULL OR ledger_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid ledger entry.';
  END IF;
  IF NEW.currency_code IS DISTINCT FROM ledger_row.currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry currency must match ledger account currency.';
  END IF;
  IF NEW.reporting_currency_code IS DISTINCT FROM transaction_row.reporting_currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry reporting currency must match transaction.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER financial_reversals_trusted_insert BEFORE INSERT ON app.financial_reversals FOR EACH ROW EXECUTE FUNCTION app.financial_reversals_trusted_mutation_guard();
CREATE TRIGGER financial_reversals_trusted_update BEFORE UPDATE ON app.financial_reversals FOR EACH ROW EXECUTE FUNCTION app.financial_reversals_trusted_mutation_guard();
CREATE TRIGGER financial_reversals_no_delete BEFORE DELETE ON app.financial_reversals FOR EACH ROW EXECUTE FUNCTION app.prevent_financial_reversal_delete();
CREATE TRIGGER financial_reversals_no_truncate BEFORE TRUNCATE ON app.financial_reversals FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_financial_reversal_truncate();

CREATE TRIGGER financial_adjustments_trusted_insert BEFORE INSERT ON app.financial_adjustments FOR EACH ROW EXECUTE FUNCTION app.financial_adjustments_trusted_mutation_guard();
CREATE TRIGGER financial_adjustments_trusted_update BEFORE UPDATE ON app.financial_adjustments FOR EACH ROW EXECUTE FUNCTION app.financial_adjustments_trusted_mutation_guard();
CREATE TRIGGER financial_adjustments_no_delete BEFORE DELETE ON app.financial_adjustments FOR EACH ROW EXECUTE FUNCTION app.prevent_financial_adjustment_delete();
CREATE TRIGGER financial_adjustments_no_truncate BEFORE TRUNCATE ON app.financial_adjustments FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_financial_adjustment_truncate();

ALTER TABLE app.financial_reversals ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.financial_reversals FORCE ROW LEVEL SECURITY;
ALTER TABLE app.financial_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.financial_adjustments FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.financial_reversals FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.financial_adjustments FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.financial_reversals_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.financial_adjustments_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_financial_reversal_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_financial_reversal_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_financial_adjustment_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_financial_adjustment_truncate() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
