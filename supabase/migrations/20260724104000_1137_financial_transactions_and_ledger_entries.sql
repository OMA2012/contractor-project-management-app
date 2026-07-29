BEGIN;

CREATE SEQUENCE app.financial_event_number_seq
  AS integer
  START WITH 1
  INCREMENT BY 1
  MINVALUE 1
  MAXVALUE 999999
  NO CYCLE;

CREATE SEQUENCE app.financial_transaction_number_seq
  AS integer
  START WITH 1
  INCREMENT BY 1
  MINVALUE 1
  MAXVALUE 999999
  NO CYCLE;

CREATE TYPE app.financial_event_type AS ENUM (
  'OPENING_BALANCE',
  'CLIENT_PAYMENT',
  'PROJECT_EXPENSE',
  'ACCOUNT_TRANSFER',
  'CURRENCY_EXCHANGE',
  'REFUND',
  'REVERSAL',
  'ADJUSTMENT'
);

CREATE TYPE app.financial_event_status AS ENUM (
  'DRAFT',
  'SUBMITTED',
  'APPROVED',
  'REJECTED'
);

CREATE TYPE app.financial_transaction_status AS ENUM (
  'DRAFT',
  'SUBMITTED',
  'APPROVED',
  'POSTED',
  'REJECTED'
);

CREATE TABLE app.financial_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_number varchar NOT NULL DEFAULT ('FE-' || lpad(nextval('app.financial_event_number_seq')::text, 6, '0')),
  event_type app.financial_event_type NOT NULL,
  project_id uuid,
  client_id uuid,
  event_date date NOT NULL,
  status app.financial_event_status NOT NULL DEFAULT 'DRAFT',
  description text,
  submitted_at timestamptz,
  submitted_by uuid,
  duplicate_fingerprint text,
  approved_at timestamptz,
  approved_by uuid,
  rejected_at timestamptz,
  rejected_by uuid,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT financial_events_event_number_uk UNIQUE (event_number),
  CONSTRAINT financial_events_project_fk FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT financial_events_client_fk FOREIGN KEY (client_id) REFERENCES app.clients(id) ON DELETE RESTRICT,
  CONSTRAINT financial_events_submitted_by_fk FOREIGN KEY (submitted_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_events_approved_by_fk FOREIGN KEY (approved_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_events_rejected_by_fk FOREIGN KEY (rejected_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_events_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_events_updated_by_fk FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_events_event_number_ck CHECK (event_number ~ '^FE-[0-9]{6}$'),
  CONSTRAINT financial_events_version_ck CHECK (version_number >= 1),
  CONSTRAINT financial_events_opening_balance_scope_ck CHECK (
    event_type <> 'OPENING_BALANCE' OR (project_id IS NULL AND client_id IS NULL)
  ),
  CONSTRAINT financial_events_submission_pair_ck CHECK (
    (submitted_at IS NULL AND submitted_by IS NULL) OR (submitted_at IS NOT NULL AND submitted_by IS NOT NULL)
  ),
  CONSTRAINT financial_events_approval_pair_ck CHECK (
    (approved_at IS NULL AND approved_by IS NULL) OR (approved_at IS NOT NULL AND approved_by IS NOT NULL)
  ),
  CONSTRAINT financial_events_rejection_pair_ck CHECK (
    (rejected_at IS NULL AND rejected_by IS NULL AND rejection_reason IS NULL)
    OR
    (rejected_at IS NOT NULL AND rejected_by IS NOT NULL AND btrim(coalesce(rejection_reason, '')) <> '')
  ),
  CONSTRAINT financial_events_terminal_exclusive_ck CHECK (
    NOT (approved_at IS NOT NULL AND rejected_at IS NOT NULL)
  ),
  CONSTRAINT financial_events_status_fields_ck CHECK (
    (status = 'DRAFT' AND submitted_at IS NULL AND approved_at IS NULL AND rejected_at IS NULL)
    OR
    (status = 'SUBMITTED' AND submitted_at IS NOT NULL AND approved_at IS NULL AND rejected_at IS NULL)
    OR
    (status = 'APPROVED' AND submitted_at IS NOT NULL AND approved_at IS NOT NULL AND rejected_at IS NULL)
    OR
    (status = 'REJECTED' AND submitted_at IS NOT NULL AND approved_at IS NULL AND rejected_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX financial_events_non_rejected_duplicate_uk
  ON app.financial_events(duplicate_fingerprint)
  WHERE duplicate_fingerprint IS NOT NULL AND status <> 'REJECTED';

CREATE TABLE app.financial_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_number varchar NOT NULL DEFAULT ('FT-' || lpad(nextval('app.financial_transaction_number_seq')::text, 6, '0')),
  financial_event_id uuid NOT NULL,
  transaction_date date NOT NULL,
  status app.financial_transaction_status NOT NULL DEFAULT 'DRAFT',
  reporting_currency_code char(3) NOT NULL,
  description text,
  reverses_transaction_id uuid,
  approved_at timestamptz,
  approved_by uuid,
  posted_at timestamptz,
  posted_by uuid,
  rejected_at timestamptz,
  rejected_by uuid,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT financial_transactions_transaction_number_uk UNIQUE (transaction_number),
  CONSTRAINT financial_transactions_event_uk UNIQUE (financial_event_id),
  CONSTRAINT financial_transactions_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT financial_transactions_reporting_currency_fk FOREIGN KEY (reporting_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT financial_transactions_reverses_fk FOREIGN KEY (reverses_transaction_id) REFERENCES app.financial_transactions(id) ON DELETE RESTRICT,
  CONSTRAINT financial_transactions_approved_by_fk FOREIGN KEY (approved_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_transactions_posted_by_fk FOREIGN KEY (posted_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_transactions_rejected_by_fk FOREIGN KEY (rejected_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_transactions_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_transactions_transaction_number_ck CHECK (transaction_number ~ '^FT-[0-9]{6}$'),
  CONSTRAINT financial_transactions_version_ck CHECK (version_number >= 1),
  CONSTRAINT financial_transactions_approval_pair_ck CHECK (
    (approved_at IS NULL AND approved_by IS NULL) OR (approved_at IS NOT NULL AND approved_by IS NOT NULL)
  ),
  CONSTRAINT financial_transactions_posting_pair_ck CHECK (
    (posted_at IS NULL AND posted_by IS NULL) OR (posted_at IS NOT NULL AND posted_by IS NOT NULL)
  ),
  CONSTRAINT financial_transactions_rejection_pair_ck CHECK (
    (rejected_at IS NULL AND rejected_by IS NULL AND rejection_reason IS NULL)
    OR
    (rejected_at IS NOT NULL AND rejected_by IS NOT NULL AND btrim(coalesce(rejection_reason, '')) <> '')
  ),
  CONSTRAINT financial_transactions_terminal_exclusive_ck CHECK (
    NOT (posted_at IS NOT NULL AND rejected_at IS NOT NULL)
  ),
  CONSTRAINT financial_transactions_status_fields_ck CHECK (
    (status = 'DRAFT' AND approved_at IS NULL AND posted_at IS NULL AND rejected_at IS NULL)
    OR
    (status = 'SUBMITTED' AND approved_at IS NULL AND posted_at IS NULL AND rejected_at IS NULL)
    OR
    (status = 'APPROVED' AND approved_at IS NOT NULL AND posted_at IS NULL AND rejected_at IS NULL)
    OR
    (status = 'POSTED' AND approved_at IS NOT NULL AND posted_at IS NOT NULL AND rejected_at IS NULL)
    OR
    (status = 'REJECTED' AND approved_at IS NULL AND posted_at IS NULL AND rejected_at IS NOT NULL)
  )
);

CREATE TABLE app.ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_transaction_id uuid NOT NULL,
  line_no integer NOT NULL,
  ledger_account_id uuid NOT NULL,
  project_id uuid,
  client_id uuid,
  currency_code char(3) NOT NULL,
  debit_amount numeric NOT NULL DEFAULT 0,
  credit_amount numeric NOT NULL DEFAULT 0,
  reporting_currency_code char(3) NOT NULL,
  reporting_debit_amount numeric NOT NULL DEFAULT 0,
  reporting_credit_amount numeric NOT NULL DEFAULT 0,
  exchange_rate_id uuid,
  rate_base_currency_code char(3),
  rate_quote_currency_code char(3),
  rate_value numeric,
  rate_source varchar,
  rounding_adjustment numeric NOT NULL DEFAULT 0,
  memo text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  CONSTRAINT ledger_entries_transaction_line_uk UNIQUE (financial_transaction_id, line_no),
  CONSTRAINT ledger_entries_transaction_fk FOREIGN KEY (financial_transaction_id) REFERENCES app.financial_transactions(id) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_ledger_account_fk FOREIGN KEY (ledger_account_id) REFERENCES app.ledger_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_project_fk FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_client_fk FOREIGN KEY (client_id) REFERENCES app.clients(id) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_reporting_currency_fk FOREIGN KEY (reporting_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_exchange_rate_fk FOREIGN KEY (exchange_rate_id) REFERENCES app.exchange_rates(id) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_rate_base_currency_fk FOREIGN KEY (rate_base_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_rate_quote_currency_fk FOREIGN KEY (rate_quote_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT ledger_entries_line_no_ck CHECK (line_no >= 1),
  CONSTRAINT ledger_entries_amount_side_ck CHECK (
    (debit_amount > 0 AND credit_amount = 0)
    OR
    (credit_amount > 0 AND debit_amount = 0)
  ),
  CONSTRAINT ledger_entries_reporting_amount_side_ck CHECK (
    (reporting_debit_amount > 0 AND reporting_credit_amount = 0)
    OR
    (reporting_credit_amount > 0 AND reporting_debit_amount = 0)
  ),
  CONSTRAINT ledger_entries_nonnegative_ck CHECK (
    debit_amount >= 0
    AND credit_amount >= 0
    AND reporting_debit_amount >= 0
    AND reporting_credit_amount >= 0
    AND rounding_adjustment >= 0
  ),
  CONSTRAINT ledger_entries_rate_snapshot_ck CHECK (
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
  )
);

CREATE TABLE app.account_opening_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id uuid NOT NULL,
  financial_account_id uuid NOT NULL,
  amount numeric NOT NULL,
  currency_code char(3) NOT NULL,
  opening_date date NOT NULL,
  notes text,
  CONSTRAINT account_opening_balances_event_uk UNIQUE (financial_event_id),
  CONSTRAINT account_opening_balances_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT account_opening_balances_financial_account_fk FOREIGN KEY (financial_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT account_opening_balances_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT account_opening_balances_amount_ck CHECK (amount > 0)
);

CREATE INDEX financial_events_status_type_idx ON app.financial_events(status, event_type, event_date DESC, id DESC);
CREATE INDEX financial_events_created_order_idx ON app.financial_events(created_at DESC, id DESC);
CREATE INDEX financial_transactions_status_date_idx ON app.financial_transactions(status, transaction_date DESC, id DESC);
CREATE INDEX ledger_entries_transaction_idx ON app.ledger_entries(financial_transaction_id, line_no);
CREATE INDEX ledger_entries_account_currency_idx ON app.ledger_entries(ledger_account_id, currency_code);
CREATE INDEX ledger_entries_project_idx ON app.ledger_entries(project_id) WHERE project_id IS NOT NULL;
CREATE INDEX ledger_entries_client_idx ON app.ledger_entries(client_id) WHERE client_id IS NOT NULL;
CREATE INDEX account_opening_balances_financial_account_idx ON app.account_opening_balances(financial_account_id);

CREATE OR REPLACE FUNCTION app.financial_events_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_setting('app.financial_transaction_context', true) IS DISTINCT FROM 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial events require trusted functions.';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.event_number IS DISTINCT FROM OLD.event_number
       OR NEW.event_type IS DISTINCT FROM OLD.event_type
       OR NEW.project_id IS DISTINCT FROM OLD.project_id
       OR NEW.client_id IS DISTINCT FROM OLD.client_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial event identity fields are immutable.';
    END IF;
    IF OLD.status IN ('APPROVED','REJECTED') AND NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Terminal financial events are immutable.';
    END IF;
    NEW.updated_at := now();
    NEW.version_number := OLD.version_number + 1;
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.financial_transactions_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_setting('app.financial_transaction_context', true) IS DISTINCT FROM 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial transactions require trusted functions.';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.transaction_number IS DISTINCT FROM OLD.transaction_number
       OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id
       OR NEW.reverses_transaction_id IS DISTINCT FROM OLD.reverses_transaction_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
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
BEGIN
  IF current_setting('app.ledger_posting_context', true) IS DISTINCT FROM 'opening_balance_posting' THEN
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

CREATE OR REPLACE FUNCTION app.account_opening_balances_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  event_row app.financial_events%ROWTYPE;
  account_row app.financial_accounts%ROWTYPE;
BEGIN
  IF current_setting('app.financial_transaction_context', true) IS DISTINCT FROM 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balances require trusted functions.';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance identity fields are immutable.';
  END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id = NEW.financial_event_id;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id = NEW.financial_account_id;
  IF event_row.id IS NULL OR event_row.event_type <> 'OPENING_BALANCE' OR account_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid opening balance.';
  END IF;
  IF NEW.currency_code IS DISTINCT FROM account_row.currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance currency must match financial account currency.';
  END IF;
  IF NEW.opening_date IS DISTINCT FROM event_row.event_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balance date must match event date.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_financial_event_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial events cannot be deleted.'; END
$function$;
CREATE OR REPLACE FUNCTION app.prevent_financial_event_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial events cannot be truncated.'; END
$function$;
CREATE OR REPLACE FUNCTION app.prevent_financial_transaction_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial transactions cannot be deleted.'; END
$function$;
CREATE OR REPLACE FUNCTION app.prevent_financial_transaction_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial transactions cannot be truncated.'; END
$function$;
CREATE OR REPLACE FUNCTION app.prevent_ledger_entry_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Posted ledger entries are immutable.'; END
$function$;
CREATE OR REPLACE FUNCTION app.prevent_ledger_entry_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries cannot be deleted.'; END
$function$;
CREATE OR REPLACE FUNCTION app.prevent_ledger_entry_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries cannot be truncated.'; END
$function$;
CREATE OR REPLACE FUNCTION app.prevent_account_opening_balance_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Opening balances cannot be deleted.'; END
$function$;

CREATE TRIGGER financial_events_trusted_insert BEFORE INSERT ON app.financial_events FOR EACH ROW EXECUTE FUNCTION app.financial_events_trusted_mutation_guard();
CREATE TRIGGER financial_events_trusted_update BEFORE UPDATE ON app.financial_events FOR EACH ROW EXECUTE FUNCTION app.financial_events_trusted_mutation_guard();
CREATE TRIGGER financial_events_no_delete BEFORE DELETE ON app.financial_events FOR EACH ROW EXECUTE FUNCTION app.prevent_financial_event_delete();
CREATE TRIGGER financial_events_no_truncate BEFORE TRUNCATE ON app.financial_events FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_financial_event_truncate();
CREATE TRIGGER financial_transactions_trusted_insert BEFORE INSERT ON app.financial_transactions FOR EACH ROW EXECUTE FUNCTION app.financial_transactions_trusted_mutation_guard();
CREATE TRIGGER financial_transactions_trusted_update BEFORE UPDATE ON app.financial_transactions FOR EACH ROW EXECUTE FUNCTION app.financial_transactions_trusted_mutation_guard();
CREATE TRIGGER financial_transactions_no_delete BEFORE DELETE ON app.financial_transactions FOR EACH ROW EXECUTE FUNCTION app.prevent_financial_transaction_delete();
CREATE TRIGGER financial_transactions_no_truncate BEFORE TRUNCATE ON app.financial_transactions FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_financial_transaction_truncate();
CREATE TRIGGER ledger_entries_trusted_insert BEFORE INSERT ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION app.ledger_entries_trusted_insert_guard();
CREATE TRIGGER ledger_entries_no_update BEFORE UPDATE ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION app.prevent_ledger_entry_update();
CREATE TRIGGER ledger_entries_no_delete BEFORE DELETE ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION app.prevent_ledger_entry_delete();
CREATE TRIGGER ledger_entries_no_truncate BEFORE TRUNCATE ON app.ledger_entries FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_ledger_entry_truncate();
CREATE TRIGGER account_opening_balances_trusted_insert BEFORE INSERT ON app.account_opening_balances FOR EACH ROW EXECUTE FUNCTION app.account_opening_balances_trusted_mutation_guard();
CREATE TRIGGER account_opening_balances_trusted_update BEFORE UPDATE ON app.account_opening_balances FOR EACH ROW EXECUTE FUNCTION app.account_opening_balances_trusted_mutation_guard();
CREATE TRIGGER account_opening_balances_no_delete BEFORE DELETE ON app.account_opening_balances FOR EACH ROW EXECUTE FUNCTION app.prevent_account_opening_balance_delete();

ALTER TABLE app.financial_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.financial_events FORCE ROW LEVEL SECURITY;
ALTER TABLE app.financial_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.financial_transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE app.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.ledger_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE app.account_opening_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.account_opening_balances FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.financial_event_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.financial_transaction_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.financial_events FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.financial_transactions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.ledger_entries FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.account_opening_balances FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
