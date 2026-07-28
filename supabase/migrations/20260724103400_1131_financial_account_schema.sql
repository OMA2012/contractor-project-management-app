BEGIN;

CREATE SEQUENCE app.financial_account_number_seq
  AS integer
  START WITH 1
  INCREMENT BY 1
  MINVALUE 1
  MAXVALUE 999999
  NO CYCLE;

CREATE TYPE app.financial_account_type AS ENUM ('CASH', 'BANK');

CREATE TABLE app.financial_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_number varchar(50) NOT NULL DEFAULT ('FA-' || lpad(nextval('app.financial_account_number_seq')::text, 6, '0')),
  name varchar(160) NOT NULL,
  account_type app.financial_account_type NOT NULL,
  currency_code char(3) NOT NULL,
  bank_name varchar(160),
  masked_account_identifier varchar(80),
  encrypted_account_details bytea,
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  archived_at timestamptz,
  archived_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT financial_accounts_account_number_uk UNIQUE (account_number),
  CONSTRAINT financial_accounts_currency_fk
    FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT financial_accounts_archived_by_fk
    FOREIGN KEY (archived_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_accounts_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_accounts_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_accounts_account_number_ck CHECK (account_number ~ '^FA-[0-9]{6}$'),
  CONSTRAINT financial_accounts_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT financial_accounts_version_ck CHECK (version_number >= 1),
  CONSTRAINT financial_accounts_archive_pair_ck CHECK (
    (archived_at IS NULL AND archived_by IS NULL)
    OR
    (archived_at IS NOT NULL AND archived_by IS NOT NULL)
  ),
  CONSTRAINT financial_accounts_archived_inactive_ck CHECK (
    archived_at IS NULL OR NOT is_active
  ),
  CONSTRAINT financial_accounts_cash_bank_metadata_ck CHECK (
    (
      account_type = 'CASH'
      AND bank_name IS NULL
      AND masked_account_identifier IS NULL
      AND encrypted_account_details IS NULL
    )
    OR
    (
      account_type = 'BANK'
      AND bank_name IS NOT NULL
      AND btrim(bank_name) <> ''
      AND masked_account_identifier IS NOT NULL
      AND btrim(masked_account_identifier) <> ''
    )
  )
);

CREATE INDEX financial_accounts_owner_list_order_idx
  ON app.financial_accounts(created_at DESC, id DESC);

CREATE INDEX financial_accounts_active_lookup_idx
  ON app.financial_accounts(id, account_number)
  WHERE is_active AND archived_at IS NULL;

CREATE INDEX financial_accounts_currency_idx
  ON app.financial_accounts(currency_code);

CREATE INDEX financial_accounts_name_lower_idx
  ON app.financial_accounts(lower(name));

CREATE OR REPLACE FUNCTION app.prevent_financial_account_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial accounts cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_financial_account_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial accounts cannot be truncated.';
END
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

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER financial_accounts_no_delete
BEFORE DELETE ON app.financial_accounts
FOR EACH ROW EXECUTE FUNCTION app.prevent_financial_account_delete();

CREATE TRIGGER financial_accounts_no_truncate
BEFORE TRUNCATE ON app.financial_accounts
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_financial_account_truncate();

CREATE TRIGGER financial_accounts_trusted_update
BEFORE UPDATE ON app.financial_accounts
FOR EACH ROW EXECUTE FUNCTION app.financial_accounts_trusted_update_guard();

ALTER TABLE app.financial_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.financial_accounts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.financial_accounts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE app.financial_account_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_financial_account_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_financial_account_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.financial_accounts_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
