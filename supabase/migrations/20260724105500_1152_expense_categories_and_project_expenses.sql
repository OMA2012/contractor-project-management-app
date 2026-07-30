BEGIN;

CREATE SEQUENCE app.project_expense_number_seq AS integer START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 999999 NO CYCLE;

CREATE TABLE app.expense_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code varchar(40) NOT NULL,
  name varchar(120) NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT expense_categories_code_uk UNIQUE (code),
  CONSTRAINT expense_categories_name_uk UNIQUE (name),
  CONSTRAINT expense_categories_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT expense_categories_updated_by_fk FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT expense_categories_code_ck CHECK (code = upper(btrim(code)) AND code ~ '^[A-Z0-9_]+$'),
  CONSTRAINT expense_categories_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT expense_categories_version_ck CHECK (version_number >= 1)
);

CREATE TABLE app.project_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id uuid NOT NULL,
  project_id uuid NOT NULL,
  expense_number varchar(60) NOT NULL DEFAULT ('EXP-' || lpad(nextval('app.project_expense_number_seq')::text, 6, '0')),
  expense_category_id uuid NOT NULL,
  amount numeric(20,6) NOT NULL,
  currency_code char(3) NOT NULL,
  paid_from_account_id uuid NOT NULL,
  expense_date date NOT NULL,
  vendor_name varchar(200),
  vendor_reference varchar(120),
  description text NOT NULL,
  private_notes text,
  CONSTRAINT project_expenses_event_uk UNIQUE (financial_event_id),
  CONSTRAINT project_expenses_number_uk UNIQUE (expense_number),
  CONSTRAINT project_expenses_event_fk FOREIGN KEY (financial_event_id) REFERENCES app.financial_events(id) ON DELETE RESTRICT,
  CONSTRAINT project_expenses_project_fk FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT project_expenses_category_fk FOREIGN KEY (expense_category_id) REFERENCES app.expense_categories(id) ON DELETE RESTRICT,
  CONSTRAINT project_expenses_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT project_expenses_paid_account_fk FOREIGN KEY (paid_from_account_id) REFERENCES app.financial_accounts(id) ON DELETE RESTRICT,
  CONSTRAINT project_expenses_number_ck CHECK (expense_number ~ '^EXP-[0-9]{6}$'),
  CONSTRAINT project_expenses_amount_ck CHECK (amount > 0),
  CONSTRAINT project_expenses_description_ck CHECK (btrim(description) <> '')
);

CREATE INDEX expense_categories_active_code_idx ON app.expense_categories(is_active, code);
CREATE INDEX project_expenses_project_date_idx ON app.project_expenses(project_id, expense_date DESC, id DESC);
CREATE INDEX project_expenses_category_idx ON app.project_expenses(expense_category_id);
CREATE INDEX project_expenses_paid_account_idx ON app.project_expenses(paid_from_account_id);
CREATE INDEX project_expenses_vendor_reference_idx ON app.project_expenses(project_id, expense_date, currency_code, amount, vendor_reference) WHERE vendor_reference IS NOT NULL;

INSERT INTO app.expense_categories (code, name, description)
VALUES
  ('PROPERTY_LAND_PURCHASE','Property Land Purchase','Property and land acquisition costs'),
  ('CONSTRUCTION_MATERIALS','Construction Materials','Construction materials and supplies'),
  ('WORKER_WAGES','Worker Wages','Direct worker wage costs'),
  ('SUBCONTRACTOR_PAYMENTS','Subcontractor Payments','Subcontractor services and payments'),
  ('EQUIPMENT_RENTAL','Equipment Rental','Equipment rental costs'),
  ('TRANSPORTATION','Transportation','Transport and logistics costs'),
  ('PERMITS','Permits','Permit and approval fees'),
  ('UTILITIES','Utilities','Project utility expenses'),
  ('PROFESSIONAL_FEES','Professional Fees','Professional service fees'),
  ('MAINTENANCE','Maintenance','Maintenance and repair expenses'),
  ('OFFICE_EXPENSES','Office Expenses','Office and administrative expenses'),
  ('OTHER','Other','Other approved project expenses')
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION app.expense_categories_trusted_mutation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE mutation_context text := coalesce(current_setting('app.expense_category_context', true), '');
BEGIN
  IF mutation_context NOT IN ('expense_category_owner_mutation','expense_category_seed') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Expense categories require trusted functions.';
  END IF;
  NEW.code := upper(btrim(NEW.code));
  NEW.name := btrim(NEW.name);
  NEW.description := app.normalize_financial_optional_text(NEW.description);
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.code IS DISTINCT FROM OLD.code OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Expense category identity fields are immutable.';
    END IF;
    IF mutation_context = 'expense_category_owner_mutation' AND NEW.updated_by IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Expense category actor is required.';
    END IF;
    NEW.updated_at := now();
    NEW.version_number := OLD.version_number + 1;
  ELSIF mutation_context = 'expense_category_owner_mutation' AND (NEW.created_by IS NULL OR NEW.updated_by IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Expense category actor is required.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.project_expenses_trusted_mutation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  mutation_context text := coalesce(current_setting('app.financial_transaction_context', true), '');
  event_row app.financial_events%ROWTYPE;
  transaction_row app.financial_transactions%ROWTYPE;
  project_row app.projects%ROWTYPE;
  category_row app.expense_categories%ROWTYPE;
  account_row app.financial_accounts%ROWTYPE;
BEGIN
  IF mutation_context <> 'owner_financial_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project expenses require trusted functions.';
  END IF;
  NEW.vendor_reference := upper(NULLIF(btrim(NEW.vendor_reference), ''))::varchar(120);
  NEW.vendor_name := NULLIF(btrim(NEW.vendor_name), '')::varchar(200);
  NEW.description := btrim(NEW.description);
  NEW.private_notes := app.normalize_financial_optional_text(NEW.private_notes);
  SELECT * INTO event_row FROM app.financial_events WHERE id = NEW.financial_event_id;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE financial_event_id = NEW.financial_event_id;
  SELECT * INTO project_row FROM app.projects WHERE id = NEW.project_id;
  SELECT * INTO category_row FROM app.expense_categories WHERE id = NEW.expense_category_id;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id = NEW.paid_from_account_id;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR project_row.id IS NULL OR category_row.id IS NULL OR account_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid project expense.';
  END IF;
  IF event_row.event_type <> 'PROJECT_EXPENSE' OR event_row.project_id IS DISTINCT FROM NEW.project_id OR event_row.client_id IS DISTINCT FROM project_row.client_id OR project_row.archived_at IS NOT NULL OR transaction_row.reporting_currency_code IS DISTINCT FROM project_row.reporting_currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid project expense.';
  END IF;
  IF NEW.amount <= 0 OR NEW.expense_date IS DISTINCT FROM event_row.event_date OR NEW.expense_date IS DISTINCT FROM transaction_row.transaction_date OR NEW.currency_code IS DISTINCT FROM account_row.currency_code OR account_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid project expense.';
  END IF;
  IF event_row.status IN ('SUBMITTED','APPROVED') AND (NOT category_row.is_active OR NOT account_row.is_active OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = NEW.currency_code AND is_active)) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid project expense.';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.financial_event_id IS DISTINCT FROM OLD.financial_event_id OR NEW.expense_number IS DISTINCT FROM OLD.expense_number THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project expense identity fields are immutable.';
    END IF;
    IF event_row.status = 'APPROVED' OR transaction_row.status = 'POSTED' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved project expenses are immutable.';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_expense_category_delete() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$ BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Expense categories cannot be deleted.'; END $function$;
CREATE OR REPLACE FUNCTION app.prevent_expense_category_truncate() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$ BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Expense categories cannot be truncated.'; END $function$;
CREATE OR REPLACE FUNCTION app.prevent_project_expense_delete() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$ BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project expenses cannot be deleted.'; END $function$;
CREATE OR REPLACE FUNCTION app.prevent_project_expense_truncate() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$ BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project expenses cannot be truncated.'; END $function$;

CREATE TRIGGER expense_categories_trusted_insert BEFORE INSERT ON app.expense_categories FOR EACH ROW EXECUTE FUNCTION app.expense_categories_trusted_mutation_guard();
CREATE TRIGGER expense_categories_trusted_update BEFORE UPDATE ON app.expense_categories FOR EACH ROW EXECUTE FUNCTION app.expense_categories_trusted_mutation_guard();
CREATE TRIGGER expense_categories_no_delete BEFORE DELETE ON app.expense_categories FOR EACH ROW EXECUTE FUNCTION app.prevent_expense_category_delete();
CREATE TRIGGER expense_categories_no_truncate BEFORE TRUNCATE ON app.expense_categories FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_expense_category_truncate();
CREATE TRIGGER project_expenses_trusted_insert BEFORE INSERT ON app.project_expenses FOR EACH ROW EXECUTE FUNCTION app.project_expenses_trusted_mutation_guard();
CREATE TRIGGER project_expenses_trusted_update BEFORE UPDATE ON app.project_expenses FOR EACH ROW EXECUTE FUNCTION app.project_expenses_trusted_mutation_guard();
CREATE TRIGGER project_expenses_no_delete BEFORE DELETE ON app.project_expenses FOR EACH ROW EXECUTE FUNCTION app.prevent_project_expense_delete();
CREATE TRIGGER project_expenses_no_truncate BEFORE TRUNCATE ON app.project_expenses FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_project_expense_truncate();

ALTER TABLE app.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.expense_categories FORCE ROW LEVEL SECURITY;
ALTER TABLE app.project_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project_expenses FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.expense_categories FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.project_expenses FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE app.project_expense_number_seq FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
