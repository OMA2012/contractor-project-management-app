BEGIN;

CREATE TABLE app.account_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id uuid NOT NULL,
  source_account_id uuid NOT NULL,
  destination_account_id uuid NOT NULL,
  amount numeric(20,6) NOT NULL,
  currency_code char(3) NOT NULL,
  transfer_date date NOT NULL,
  reference varchar(120),
  notes text,
  CONSTRAINT account_transfers_event_uk UNIQUE (financial_event_id),
  CONSTRAINT account_transfers_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT account_transfers_source_account_fk FOREIGN KEY (source_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT account_transfers_destination_account_fk FOREIGN KEY (destination_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT account_transfers_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT account_transfers_distinct_accounts_ck CHECK (source_account_id <> destination_account_id),
  CONSTRAINT account_transfers_amount_ck CHECK (amount > 0)
);

CREATE INDEX account_transfers_source_account_idx ON app.account_transfers(source_account_id);
CREATE INDEX account_transfers_destination_account_idx ON app.account_transfers(destination_account_id);
CREATE INDEX account_transfers_date_currency_idx ON app.account_transfers(transfer_date DESC, currency_code, id DESC);
CREATE INDEX account_transfers_reference_idx ON app.account_transfers(source_account_id, destination_account_id, transfer_date, currency_code, amount, reference) WHERE reference IS NOT NULL;

CREATE OR REPLACE FUNCTION app.account_transfers_trusted_mutation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  mutation_context text := coalesce(current_setting('app.financial_transaction_context', true), '');
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  source_row app.financial_accounts%ROWTYPE;
  destination_row app.financial_accounts%ROWTYPE;
BEGIN
  IF mutation_context <> 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Account transfers require trusted functions.';
  END IF;
  NEW.reference := upper(NULLIF(btrim(NEW.reference), ''))::varchar(120);
  NEW.notes := app.normalize_financial_optional_text(NEW.notes);
  SELECT * INTO event_row FROM app.financial_events WHERE id = NEW.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = NEW.financial_event_id;
  SELECT * INTO source_row FROM app.financial_accounts WHERE id = NEW.source_account_id;
  SELECT * INTO destination_row FROM app.financial_accounts WHERE id = NEW.destination_account_id;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR source_row.id IS NULL OR destination_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid account transfer.';
  END IF;
  IF event_row.event_type <> 'ACCOUNT_TRANSFER' OR event_row.project_id IS NOT NULL OR event_row.client_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid account transfer.';
  END IF;
  IF NEW.source_account_id = NEW.destination_account_id OR NEW.amount <= 0 OR NEW.transfer_date IS DISTINCT FROM event_row.event_date OR NEW.transfer_date IS DISTINCT FROM transaction_row.transaction_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid account transfer.';
  END IF;
  IF NEW.currency_code IS DISTINCT FROM source_row.currency_code OR NEW.currency_code IS DISTINCT FROM destination_row.currency_code OR source_row.currency_code IS DISTINCT FROM destination_row.currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid account transfer.';
  END IF;
  IF event_row.status IN ('SUBMITTED','APPROVED') AND (NOT source_row.is_active OR source_row.archived_at IS NOT NULL OR NOT destination_row.is_active OR destination_row.archived_at IS NOT NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = NEW.currency_code AND is_active)) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid account transfer.';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Account transfer identity fields are immutable.';
    END IF;
    IF event_row.status = 'APPROVED' OR transaction_row.status = 'POSTED' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved account transfers are immutable.';
    END IF;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION app.prevent_account_transfer_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Account transfers cannot be deleted.'; END $function$;

CREATE OR REPLACE FUNCTION app.prevent_account_transfer_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Account transfers cannot be truncated.'; END $function$;

CREATE TRIGGER account_transfers_trusted_insert BEFORE INSERT ON app.account_transfers FOR EACH ROW EXECUTE FUNCTION app.account_transfers_trusted_mutation_guard();
CREATE TRIGGER account_transfers_trusted_update BEFORE UPDATE ON app.account_transfers FOR EACH ROW EXECUTE FUNCTION app.account_transfers_trusted_mutation_guard();
CREATE TRIGGER account_transfers_no_delete BEFORE DELETE ON app.account_transfers FOR EACH ROW EXECUTE FUNCTION app.prevent_account_transfer_delete();
CREATE TRIGGER account_transfers_no_truncate BEFORE TRUNCATE ON app.account_transfers FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_account_transfer_truncate();

ALTER TABLE app.account_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.account_transfers FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.account_transfers FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
