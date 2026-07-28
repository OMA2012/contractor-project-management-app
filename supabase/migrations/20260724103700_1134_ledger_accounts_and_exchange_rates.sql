BEGIN;

CREATE TYPE app.ledger_account_kind AS ENUM ('FINANCIAL_ASSET', 'CONTROL');
CREATE TYPE app.entry_side AS ENUM ('DEBIT', 'CREDIT');

CREATE TABLE app.ledger_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code varchar(80) NOT NULL,
  name varchar(160) NOT NULL,
  account_kind app.ledger_account_kind NOT NULL,
  financial_account_id uuid,
  currency_code char(3) NOT NULL,
  normal_side app.entry_side NOT NULL,
  is_system boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT ledger_accounts_code_uk UNIQUE (code),
  CONSTRAINT ledger_accounts_financial_account_uk UNIQUE (financial_account_id),
  CONSTRAINT ledger_accounts_financial_account_fk
    FOREIGN KEY (financial_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT ledger_accounts_currency_fk
    FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT ledger_accounts_code_ck CHECK (btrim(code) <> ''),
  CONSTRAINT ledger_accounts_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT ledger_accounts_kind_financial_account_ck CHECK (
    (account_kind = 'FINANCIAL_ASSET' AND financial_account_id IS NOT NULL)
    OR
    (account_kind = 'CONTROL' AND financial_account_id IS NULL)
  ),
  CONSTRAINT ledger_accounts_financial_asset_debit_ck CHECK (
    account_kind <> 'FINANCIAL_ASSET' OR normal_side = 'DEBIT'
  ),
  CONSTRAINT ledger_accounts_system_managed_ck CHECK (is_system)
);

CREATE TABLE app.exchange_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rate_date date NOT NULL,
  base_currency_code char(3) NOT NULL,
  quote_currency_code char(3) NOT NULL,
  rate_value numeric(30,12) NOT NULL,
  source varchar(120) NOT NULL DEFAULT 'MANUAL',
  source_reference text,
  entered_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT exchange_rates_base_currency_fk
    FOREIGN KEY (base_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT exchange_rates_quote_currency_fk
    FOREIGN KEY (quote_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT exchange_rates_entered_by_fk
    FOREIGN KEY (entered_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT exchange_rates_distinct_currency_ck CHECK (base_currency_code <> quote_currency_code),
  CONSTRAINT exchange_rates_rate_value_ck CHECK (rate_value > 0),
  CONSTRAINT exchange_rates_source_ck CHECK (btrim(source) <> ''),
  CONSTRAINT exchange_rates_exact_duplicate_uk UNIQUE (
    rate_date,
    base_currency_code,
    quote_currency_code,
    rate_value,
    source
  )
);

CREATE INDEX ledger_accounts_financial_account_idx
  ON app.ledger_accounts(financial_account_id)
  WHERE financial_account_id IS NOT NULL;

CREATE INDEX ledger_accounts_currency_kind_idx
  ON app.ledger_accounts(currency_code, account_kind);

CREATE INDEX ledger_accounts_active_kind_idx
  ON app.ledger_accounts(account_kind, is_active, code);

CREATE INDEX exchange_rates_pair_date_idx
  ON app.exchange_rates(base_currency_code, quote_currency_code, rate_date DESC, created_at DESC, id DESC);

CREATE INDEX exchange_rates_reverse_pair_date_idx
  ON app.exchange_rates(quote_currency_code, base_currency_code, rate_date DESC, created_at DESC, id DESC);

CREATE INDEX exchange_rates_rate_date_idx
  ON app.exchange_rates(rate_date DESC, created_at DESC, id DESC);

CREATE INDEX exchange_rates_entered_by_idx
  ON app.exchange_rates(entered_by, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION app.ledger_accounts_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  financial_row app.financial_accounts%ROWTYPE;
BEGIN
  IF current_setting('app.ledger_account_sync_context', true) IS DISTINCT FROM 'financial_account_sync' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger accounts are system-managed.';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.code IS DISTINCT FROM OLD.code
       OR NEW.account_kind IS DISTINCT FROM OLD.account_kind
       OR NEW.financial_account_id IS DISTINCT FROM OLD.financial_account_id
       OR NEW.normal_side IS DISTINCT FROM OLD.normal_side THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger account identity fields are immutable.';
    END IF;
  END IF;

  IF NEW.account_kind = 'FINANCIAL_ASSET' THEN
    SELECT * INTO financial_row
    FROM app.financial_accounts AS fa
    WHERE fa.id = NEW.financial_account_id;

    IF financial_row.id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial asset ledger account requires a valid financial account.';
    END IF;

    IF NEW.currency_code IS DISTINCT FROM financial_row.currency_code THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Asset ledger currency must match financial account currency.';
    END IF;

    IF NEW.normal_side <> 'DEBIT' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial asset ledger accounts use debit normal side.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_ledger_account_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger accounts cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_ledger_account_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger accounts cannot be truncated.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_exchange_rate_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Exchange rates are append-only.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_exchange_rate_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Exchange rates cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_exchange_rate_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Exchange rates cannot be truncated.';
END
$function$;

CREATE TRIGGER ledger_accounts_trusted_insert
BEFORE INSERT ON app.ledger_accounts
FOR EACH ROW EXECUTE FUNCTION app.ledger_accounts_trusted_mutation_guard();

CREATE TRIGGER ledger_accounts_trusted_update
BEFORE UPDATE ON app.ledger_accounts
FOR EACH ROW EXECUTE FUNCTION app.ledger_accounts_trusted_mutation_guard();

CREATE TRIGGER ledger_accounts_no_delete
BEFORE DELETE ON app.ledger_accounts
FOR EACH ROW EXECUTE FUNCTION app.prevent_ledger_account_delete();

CREATE TRIGGER ledger_accounts_no_truncate
BEFORE TRUNCATE ON app.ledger_accounts
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_ledger_account_truncate();

CREATE TRIGGER exchange_rates_no_update
BEFORE UPDATE ON app.exchange_rates
FOR EACH ROW EXECUTE FUNCTION app.prevent_exchange_rate_update();

CREATE TRIGGER exchange_rates_no_delete
BEFORE DELETE ON app.exchange_rates
FOR EACH ROW EXECUTE FUNCTION app.prevent_exchange_rate_delete();

CREATE TRIGGER exchange_rates_no_truncate
BEFORE TRUNCATE ON app.exchange_rates
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_exchange_rate_truncate();

ALTER TABLE app.ledger_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.ledger_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE app.exchange_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.exchange_rates FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.ledger_accounts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.exchange_rates FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.ledger_accounts_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_ledger_account_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_ledger_account_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_exchange_rate_update() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_exchange_rate_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_exchange_rate_truncate() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
