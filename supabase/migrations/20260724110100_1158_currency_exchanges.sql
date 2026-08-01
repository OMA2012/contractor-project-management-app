BEGIN;

ALTER TABLE app.ledger_entries
  DROP CONSTRAINT ledger_entries_nonnegative_ck,
  ADD CONSTRAINT ledger_entries_nonnegative_ck CHECK (
    debit_amount >= 0
    AND credit_amount >= 0
    AND reporting_debit_amount >= 0
    AND reporting_credit_amount >= 0
  );

ALTER TABLE app.ledger_entries
  DROP CONSTRAINT ledger_entries_rate_snapshot_ck,
  ADD CONSTRAINT ledger_entries_rate_snapshot_ck CHECK (
    (
      exchange_rate_id IS NULL
      AND rate_base_currency_code IS NULL
      AND rate_quote_currency_code IS NULL
      AND rate_value IS NULL
      AND rate_source IS NULL
    )
    OR
    (
      exchange_rate_id IS NOT NULL
      AND rate_base_currency_code IS NOT NULL
      AND rate_quote_currency_code IS NOT NULL
      AND rate_value IS NOT NULL
      AND rate_value > 0
      AND rate_source IS NOT NULL
      AND btrim(rate_source) <> ''
    )
    OR
    (
      exchange_rate_id IS NULL
      AND rate_base_currency_code IS NOT NULL
      AND rate_quote_currency_code IS NOT NULL
      AND rate_base_currency_code <> rate_quote_currency_code
      AND rate_value IS NOT NULL
      AND rate_value > 0
      AND rate_source = 'DERIVED_FROM_CURRENCY_EXCHANGE'
    )
  );

CREATE TABLE app.currency_exchanges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id uuid NOT NULL,
  source_account_id uuid NOT NULL,
  destination_account_id uuid NOT NULL,
  source_amount numeric(20,6) NOT NULL,
  source_currency_code char(3) NOT NULL,
  destination_amount numeric(20,6) NOT NULL,
  destination_currency_code char(3) NOT NULL,
  exchange_rate_id uuid,
  rate_base_currency_code char(3) NOT NULL,
  rate_quote_currency_code char(3) NOT NULL,
  rate_value numeric(30,12) NOT NULL,
  rate_source varchar(120) NOT NULL DEFAULT 'MANUAL',
  fee_amount numeric(20,6) NOT NULL DEFAULT 0,
  fee_currency_code char(3),
  fee_account_id uuid,
  exchange_date date NOT NULL,
  rounding_result numeric(20,6) NOT NULL DEFAULT 0,
  reference varchar(120),
  CONSTRAINT currency_exchanges_event_uk UNIQUE (financial_event_id),
  CONSTRAINT currency_exchanges_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_source_account_fk FOREIGN KEY (source_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_destination_account_fk FOREIGN KEY (destination_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_exchange_rate_fk FOREIGN KEY (exchange_rate_id) REFERENCES app.exchange_rates(id) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_rate_base_currency_fk FOREIGN KEY (rate_base_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_rate_quote_currency_fk FOREIGN KEY (rate_quote_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_source_currency_fk FOREIGN KEY (source_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_destination_currency_fk FOREIGN KEY (destination_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_fee_currency_fk FOREIGN KEY (fee_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_fee_account_fk FOREIGN KEY (fee_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT currency_exchanges_distinct_accounts_ck CHECK (source_account_id <> destination_account_id),
  CONSTRAINT currency_exchanges_positive_amounts_ck CHECK (source_amount > 0 AND destination_amount > 0),
  CONSTRAINT currency_exchanges_distinct_currencies_ck CHECK (source_currency_code <> destination_currency_code),
  CONSTRAINT currency_exchanges_rate_pair_ck CHECK (rate_base_currency_code <> rate_quote_currency_code),
  CONSTRAINT currency_exchanges_rate_value_ck CHECK (rate_value > 0),
  CONSTRAINT currency_exchanges_rate_source_ck CHECK (btrim(rate_source) <> ''),
  CONSTRAINT currency_exchanges_fee_ck CHECK (
    (fee_amount = 0 AND fee_currency_code IS NULL AND fee_account_id IS NULL)
    OR
    (fee_amount > 0 AND fee_currency_code IS NOT NULL AND fee_account_id IS NOT NULL)
  ),
  CONSTRAINT currency_exchanges_fee_nonnegative_ck CHECK (fee_amount >= 0)
);

CREATE INDEX currency_exchanges_source_account_idx ON app.currency_exchanges(source_account_id);
CREATE INDEX currency_exchanges_destination_account_idx ON app.currency_exchanges(destination_account_id);
CREATE INDEX currency_exchanges_exchange_date_idx ON app.currency_exchanges(exchange_date DESC, id DESC);
CREATE INDEX currency_exchanges_reference_idx ON app.currency_exchanges(source_account_id, destination_account_id, exchange_date, source_currency_code, destination_currency_code, source_amount, destination_amount, reference) WHERE reference IS NOT NULL;

CREATE OR REPLACE FUNCTION app.currency_exchanges_trusted_mutation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  mutation_context text := coalesce(current_setting('app.financial_transaction_context', true), '');
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  source_row app.financial_accounts%ROWTYPE;
  destination_row app.financial_accounts%ROWTYPE;
  fee_row app.financial_accounts%ROWTYPE;
BEGIN
  IF mutation_context <> 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Currency exchanges require trusted functions.';
  END IF;

  NEW.reference := upper(NULLIF(btrim(NEW.reference), ''))::varchar(120);
  NEW.rate_source := NULLIF(btrim(coalesce(NEW.rate_source, 'MANUAL')), '')::varchar(120);

  SELECT * INTO event_row FROM app.financial_events WHERE id = NEW.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = NEW.financial_event_id;
  SELECT * INTO source_row FROM app.financial_accounts WHERE id = NEW.source_account_id;
  SELECT * INTO destination_row FROM app.financial_accounts WHERE id = NEW.destination_account_id;

  IF event_row.id IS NULL OR transaction_row.id IS NULL OR source_row.id IS NULL OR destination_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange.';
  END IF;
  IF event_row.event_type <> 'CURRENCY_EXCHANGE' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange.';
  END IF;
  IF NEW.exchange_date IS DISTINCT FROM event_row.event_date OR NEW.exchange_date IS DISTINCT FROM transaction_row.transaction_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange.';
  END IF;
  IF NEW.source_account_id = NEW.destination_account_id
     OR NEW.source_amount <= 0
     OR NEW.destination_amount <= 0
     OR NEW.source_currency_code IS DISTINCT FROM source_row.currency_code
     OR NEW.destination_currency_code IS DISTINCT FROM destination_row.currency_code
     OR NEW.source_currency_code = NEW.destination_currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange.';
  END IF;
  IF NOT (
    (NEW.rate_base_currency_code = NEW.source_currency_code AND NEW.rate_quote_currency_code = NEW.destination_currency_code)
    OR
    (NEW.rate_quote_currency_code = NEW.source_currency_code AND NEW.rate_base_currency_code = NEW.destination_currency_code)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange rate.';
  END IF;
  IF NEW.fee_amount = 0 AND (NEW.fee_currency_code IS NOT NULL OR NEW.fee_account_id IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange fee.';
  END IF;
  IF NEW.fee_amount > 0 THEN
    SELECT * INTO fee_row FROM app.financial_accounts WHERE id = NEW.fee_account_id;
    IF fee_row.id IS NULL
       OR NEW.fee_currency_code IS DISTINCT FROM fee_row.currency_code
       OR NEW.fee_currency_code NOT IN (NEW.source_currency_code, NEW.destination_currency_code) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange fee.';
    END IF;
  END IF;
  IF event_row.status IN ('SUBMITTED','APPROVED')
     AND (
       NOT source_row.is_active OR source_row.archived_at IS NOT NULL
       OR NOT destination_row.is_active OR destination_row.archived_at IS NOT NULL
       OR (NEW.fee_amount > 0 AND (NOT fee_row.is_active OR fee_row.archived_at IS NOT NULL))
       OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = NEW.source_currency_code AND is_active)
       OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = NEW.destination_currency_code AND is_active)
       OR (NEW.fee_currency_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = NEW.fee_currency_code AND is_active))
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange.';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Currency exchange identity fields are immutable.';
    END IF;
    IF event_row.status = 'APPROVED' OR transaction_row.status = 'POSTED' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved currency exchanges are immutable.';
    END IF;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION app.prevent_currency_exchange_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Currency exchanges cannot be deleted.'; END $function$;

CREATE OR REPLACE FUNCTION app.prevent_currency_exchange_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Currency exchanges cannot be truncated.'; END $function$;

CREATE TRIGGER currency_exchanges_trusted_insert BEFORE INSERT ON app.currency_exchanges FOR EACH ROW EXECUTE FUNCTION app.currency_exchanges_trusted_mutation_guard();
CREATE TRIGGER currency_exchanges_trusted_update BEFORE UPDATE ON app.currency_exchanges FOR EACH ROW EXECUTE FUNCTION app.currency_exchanges_trusted_mutation_guard();
CREATE TRIGGER currency_exchanges_no_delete BEFORE DELETE ON app.currency_exchanges FOR EACH ROW EXECUTE FUNCTION app.prevent_currency_exchange_delete();
CREATE TRIGGER currency_exchanges_no_truncate BEFORE TRUNCATE ON app.currency_exchanges FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_currency_exchange_truncate();

ALTER TABLE app.currency_exchanges ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.currency_exchanges FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.currency_exchanges FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.currency_exchanges_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_currency_exchange_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_currency_exchange_truncate() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
