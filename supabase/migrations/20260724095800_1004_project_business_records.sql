BEGIN;

CREATE TYPE app.project_record_status AS ENUM (
  'DRAFT',
  'QUOTATION',
  'APPROVED',
  'ACTIVE',
  'ON_HOLD',
  'COMPLETED',
  'CANCELLED',
  'ARCHIVED'
);

CREATE TABLE app.project_number_counters (
  project_year integer PRIMARY KEY,
  last_value integer NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT project_number_counters_year_ck CHECK (project_year BETWEEN 2000 AND 9999),
  CONSTRAINT project_number_counters_last_value_ck CHECK (last_value BETWEEN 1 AND 9999)
);

CREATE OR REPLACE FUNCTION app.prevent_project_number_counter_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project number counters cannot be deleted.';
END
$function$;

CREATE TRIGGER project_number_counters_no_delete
BEFORE DELETE ON app.project_number_counters
FOR EACH ROW EXECUTE FUNCTION app.prevent_project_number_counter_delete();

ALTER TABLE app.project_number_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project_number_counters FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION app.generate_project_number()
RETURNS public.citext
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  contractor_time_zone text;
  resolved_year integer;
  allocated_value integer;
BEGIN
  SELECT cp.time_zone INTO contractor_time_zone
  FROM app.contractor_profiles AS cp
  WHERE cp.singleton_key = 1;

  IF contractor_time_zone IS NULL OR btrim(contractor_time_zone) = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project number time zone is not configured.';
  END IF;

  resolved_year := extract(year FROM now() AT TIME ZONE contractor_time_zone)::integer;

  INSERT INTO app.project_number_counters (
    project_year,
    last_value
  )
  VALUES (
    resolved_year,
    1
  )
  ON CONFLICT (project_year)
  DO UPDATE
  SET
    last_value = app.project_number_counters.last_value + 1,
    updated_at = now()
  WHERE app.project_number_counters.last_value < 9999
  RETURNING last_value INTO allocated_value;

  IF allocated_value IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '54000', MESSAGE = 'Project number allocation exhausted for year.';
  END IF;

  RETURN ('PRJ-' || resolved_year::text || '-' || lpad(allocated_value::text, 4, '0'))::public.citext;
END
$function$;

CREATE TABLE app.projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_number public.citext NOT NULL DEFAULT app.generate_project_number(),
  client_id uuid NOT NULL,
  name varchar(180) NOT NULL,
  project_type varchar(80),
  location text,
  status app.project_record_status NOT NULL DEFAULT 'DRAFT',
  start_date date,
  end_date date,
  contract_amount numeric(20,6),
  contract_currency_code char(3),
  budget_amount numeric(20,6),
  budget_currency_code char(3),
  reporting_currency_code char(3) NOT NULL,
  client_visible_summary text,
  internal_notes text,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  archived_at timestamptz,
  archived_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT projects_project_number_uk UNIQUE (project_number),
  CONSTRAINT projects_client_fk
    FOREIGN KEY (client_id) REFERENCES app.clients(id) ON DELETE RESTRICT,
  CONSTRAINT projects_contract_currency_fk
    FOREIGN KEY (contract_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT projects_budget_currency_fk
    FOREIGN KEY (budget_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT projects_reporting_currency_fk
    FOREIGN KEY (reporting_currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT projects_archived_by_fk
    FOREIGN KEY (archived_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT projects_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT projects_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT projects_project_number_ck CHECK (project_number::text ~ '^PRJ-[0-9]{4}-[0-9]{4}$'),
  CONSTRAINT projects_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT projects_project_type_ck CHECK (
    project_type IS NULL OR (btrim(project_type) <> '' AND length(btrim(project_type)) <= 80)
  ),
  CONSTRAINT projects_location_ck CHECK (
    location IS NULL OR (btrim(location) <> '' AND length(btrim(location)) <= 500)
  ),
  CONSTRAINT projects_date_order_ck CHECK (
    start_date IS NULL OR end_date IS NULL OR start_date <= end_date
  ),
  CONSTRAINT projects_contract_pair_ck CHECK (
    (contract_amount IS NULL AND contract_currency_code IS NULL)
    OR
    (contract_amount IS NOT NULL AND contract_currency_code IS NOT NULL)
  ),
  CONSTRAINT projects_budget_pair_ck CHECK (
    (budget_amount IS NULL AND budget_currency_code IS NULL)
    OR
    (budget_amount IS NOT NULL AND budget_currency_code IS NOT NULL)
  ),
  CONSTRAINT projects_contract_amount_ck CHECK (contract_amount IS NULL OR contract_amount >= 0),
  CONSTRAINT projects_budget_amount_ck CHECK (budget_amount IS NULL OR budget_amount >= 0),
  CONSTRAINT projects_version_ck CHECK (version_number >= 1),
  CONSTRAINT projects_lifecycle_ck CHECK (
    (
      status IN ('DRAFT', 'QUOTATION', 'APPROVED', 'ACTIVE', 'ON_HOLD')
      AND completed_at IS NULL
      AND cancelled_at IS NULL
      AND cancellation_reason IS NULL
      AND archived_at IS NULL
      AND archived_by IS NULL
    )
    OR
    (
      status = 'COMPLETED'
      AND completed_at IS NOT NULL
      AND cancelled_at IS NULL
      AND cancellation_reason IS NULL
      AND archived_at IS NULL
      AND archived_by IS NULL
    )
    OR
    (
      status = 'CANCELLED'
      AND completed_at IS NULL
      AND cancelled_at IS NOT NULL
      AND btrim(coalesce(cancellation_reason, '')) <> ''
      AND archived_at IS NULL
      AND archived_by IS NULL
    )
    OR
    (
      status = 'ARCHIVED'
      AND archived_at IS NOT NULL
      AND archived_by IS NOT NULL
      AND (
        (
          completed_at IS NOT NULL
          AND cancelled_at IS NULL
          AND cancellation_reason IS NULL
        )
        OR
        (
          completed_at IS NULL
          AND cancelled_at IS NOT NULL
          AND btrim(coalesce(cancellation_reason, '')) <> ''
        )
      )
    )
  )
);

CREATE INDEX projects_client_status_idx
  ON app.projects(client_id, status, created_at DESC, id DESC);

CREATE INDEX projects_owner_list_order_idx
  ON app.projects(created_at DESC, id DESC);

CREATE INDEX projects_name_lower_idx
  ON app.projects(lower(name));

CREATE OR REPLACE FUNCTION app.prevent_project_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project records cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.projects_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.project_number IS DISTINCT FROM OLD.project_number THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project number is immutable.';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND current_setting('app.allow_project_status_change', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project status changes require trusted lifecycle functions.';
  END IF;

  IF NEW.client_id IS DISTINCT FROM OLD.client_id
     AND current_setting('app.allow_project_client_change', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project Client changes require trusted reassignment.';
  END IF;

  IF (NEW.completed_at IS DISTINCT FROM OLD.completed_at
      OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
      OR NEW.cancellation_reason IS DISTINCT FROM OLD.cancellation_reason
      OR NEW.archived_at IS DISTINCT FROM OLD.archived_at
      OR NEW.archived_by IS DISTINCT FROM OLD.archived_by)
     AND current_setting('app.allow_project_lifecycle_fields', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project lifecycle fields require trusted lifecycle functions.';
  END IF;

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER projects_no_delete
BEFORE DELETE ON app.projects
FOR EACH ROW EXECUTE FUNCTION app.prevent_project_delete();

CREATE TRIGGER projects_trusted_update
BEFORE UPDATE ON app.projects
FOR EACH ROW EXECUTE FUNCTION app.projects_trusted_update_guard();

ALTER TABLE app.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.projects FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.project_number_counters FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.projects FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.generate_project_number() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_number_counter_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.projects_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
