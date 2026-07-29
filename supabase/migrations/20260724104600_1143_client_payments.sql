BEGIN;

CREATE TABLE app.client_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id uuid NOT NULL,
  project_id uuid NOT NULL,
  client_id uuid NOT NULL,
  amount numeric(20,6) NOT NULL,
  currency_code char(3) NOT NULL,
  received_account_id uuid,
  received_date date NOT NULL,
  payment_reference varchar(120),
  payer_name varchar(200),
  is_client_submitted boolean NOT NULL DEFAULT false,
  submitted_by_client_user_id uuid,
  notes text,
  CONSTRAINT client_payments_event_uk UNIQUE (financial_event_id),
  CONSTRAINT client_payments_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT client_payments_project_fk FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT client_payments_client_fk FOREIGN KEY (client_id) REFERENCES app.clients(id) ON DELETE RESTRICT,
  CONSTRAINT client_payments_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT client_payments_received_account_fk FOREIGN KEY (received_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT client_payments_submitted_by_client_user_fk FOREIGN KEY (submitted_by_client_user_id) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT client_payments_amount_ck CHECK (amount > 0),
  CONSTRAINT client_payments_client_submitter_ck CHECK (
    (is_client_submitted AND submitted_by_client_user_id IS NOT NULL)
    OR
    (NOT is_client_submitted)
  )
);

CREATE INDEX client_payments_project_date_idx ON app.client_payments(project_id, received_date DESC, id DESC);
CREATE INDEX client_payments_client_date_idx ON app.client_payments(client_id, received_date DESC, id DESC);
CREATE INDEX client_payments_received_account_idx ON app.client_payments(received_account_id) WHERE received_account_id IS NOT NULL;
CREATE INDEX client_payments_reference_idx ON app.client_payments(client_id, project_id, currency_code, upper(btrim(payment_reference))) WHERE payment_reference IS NOT NULL;

CREATE OR REPLACE FUNCTION app.client_payments_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  project_row app.projects%ROWTYPE;
  client_row app.clients%ROWTYPE;
  account_row app.financial_accounts%ROWTYPE;
  submitter_row app.users%ROWTYPE;
BEGIN
  IF current_setting('app.financial_transaction_context', true) NOT IN ('owner_financial_mutation','client_payment_client_submission','client_payment_owner_verification') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client payments require trusted functions.';
  END IF;

  IF TG_OP = 'UPDATE' AND current_setting('app.financial_transaction_context', true) = 'client_payment_owner_verification' THEN
    IF OLD.id IS DISTINCT FROM NEW.id
       OR OLD.financial_event_id IS DISTINCT FROM NEW.financial_event_id
       OR OLD.project_id IS DISTINCT FROM NEW.project_id
       OR OLD.client_id IS DISTINCT FROM NEW.client_id
       OR OLD.amount IS DISTINCT FROM NEW.amount
       OR OLD.currency_code IS DISTINCT FROM NEW.currency_code
       OR OLD.received_date IS DISTINCT FROM NEW.received_date
       OR OLD.payment_reference IS DISTINCT FROM NEW.payment_reference
       OR OLD.payer_name IS DISTINCT FROM NEW.payer_name
       OR OLD.is_client_submitted IS DISTINCT FROM NEW.is_client_submitted
       OR OLD.submitted_by_client_user_id IS DISTINCT FROM NEW.submitted_by_client_user_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client payment facts are immutable for this operation.';
    END IF;
  END IF;

  SELECT * INTO event_row FROM app.financial_events WHERE id = NEW.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = NEW.financial_event_id;
  SELECT * INTO project_row FROM app.projects WHERE id = NEW.project_id;
  SELECT * INTO client_row FROM app.clients WHERE id = NEW.client_id;

  IF event_row.id IS NULL OR transaction_row.id IS NULL OR project_row.id IS NULL OR client_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid client payment.';
  END IF;
  IF event_row.event_type <> 'CLIENT_PAYMENT'
     OR event_row.project_id IS DISTINCT FROM NEW.project_id
     OR event_row.client_id IS DISTINCT FROM NEW.client_id
     OR project_row.client_id IS DISTINCT FROM NEW.client_id
     OR event_row.event_date IS DISTINCT FROM NEW.received_date
     OR transaction_row.transaction_date IS DISTINCT FROM NEW.received_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid client payment.';
  END IF;
  IF transaction_row.reporting_currency_code IS DISTINCT FROM project_row.reporting_currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid client payment.';
  END IF;
  IF NEW.amount <= 0 OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = NEW.currency_code AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid client payment.';
  END IF;
  IF NEW.received_account_id IS NOT NULL THEN
    SELECT * INTO account_row FROM app.financial_accounts WHERE id = NEW.received_account_id;
    IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR account_row.currency_code IS DISTINCT FROM NEW.currency_code THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid receiving account.';
    END IF;
  END IF;
  IF NEW.is_client_submitted THEN
    SELECT * INTO submitter_row FROM app.users WHERE id = NEW.submitted_by_client_user_id;
    IF submitter_row.id IS NULL
       OR client_row.portal_user_id IS DISTINCT FROM submitter_row.id
       OR submitter_row.user_type <> 'CLIENT'
       OR submitter_row.status <> 'ACTIVE'
       OR NOT submitter_row.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid client payment submitter.';
    END IF;
  ELSIF NEW.submitted_by_client_user_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Contractor-created payments cannot claim a Client submitter.';
  END IF;
  IF (TG_OP = 'UPDATE' AND OLD IS DISTINCT FROM NEW AND (event_row.status = 'APPROVED' OR transaction_row.status = 'POSTED'))
     OR (TG_OP = 'INSERT' AND (event_row.status = 'APPROVED' OR transaction_row.status = 'POSTED')) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved client payments are immutable.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_client_payment_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client payments cannot be deleted.'; END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_client_payment_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client payments cannot be truncated.'; END
$function$;

CREATE TRIGGER client_payments_trusted_insert BEFORE INSERT ON app.client_payments FOR EACH ROW EXECUTE FUNCTION app.client_payments_trusted_mutation_guard();
CREATE TRIGGER client_payments_trusted_update BEFORE UPDATE ON app.client_payments FOR EACH ROW EXECUTE FUNCTION app.client_payments_trusted_mutation_guard();
CREATE TRIGGER client_payments_no_delete BEFORE DELETE ON app.client_payments FOR EACH ROW EXECUTE FUNCTION app.prevent_client_payment_delete();
CREATE TRIGGER client_payments_no_truncate BEFORE TRUNCATE ON app.client_payments FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_client_payment_truncate();

CREATE OR REPLACE FUNCTION app.ledger_entries_trusted_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  transaction_row app.financial_transactions%ROWTYPE;
  ledger_row app.ledger_accounts%ROWTYPE;
  posting_context text := coalesce(current_setting('app.ledger_posting_context', true), '');
BEGIN
  IF posting_context NOT IN ('opening_balance_posting','financial_reversal_posting','financial_adjustment_posting','client_payment_posting') THEN
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

ALTER TABLE app.client_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.client_payments FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.client_payments FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.client_payments_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_client_payment_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_client_payment_truncate() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
