BEGIN;

CREATE TABLE app.project_phases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  name varchar(160) NOT NULL,
  description text,
  sequence_no integer NOT NULL,
  start_date date,
  end_date date,
  client_visible boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT project_phases_project_fk
    FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT project_phases_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_phases_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_phases_project_sequence_uk UNIQUE (project_id, sequence_no)
    DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT project_phases_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT project_phases_description_ck CHECK (
    description IS NULL OR (btrim(description) <> '' AND length(btrim(description)) <= 4000)
  ),
  CONSTRAINT project_phases_sequence_ck CHECK (sequence_no > 0),
  CONSTRAINT project_phases_date_order_ck CHECK (
    start_date IS NULL OR end_date IS NULL OR start_date <= end_date
  ),
  CONSTRAINT project_phases_version_ck CHECK (version_number >= 1)
);

CREATE INDEX project_phases_project_order_idx
  ON app.project_phases(project_id, sequence_no, id);

CREATE INDEX project_phases_project_active_idx
  ON app.project_phases(project_id, is_active, sequence_no, id);

CREATE INDEX project_phases_client_visible_active_idx
  ON app.project_phases(project_id, sequence_no, id)
  WHERE is_active AND client_visible;

CREATE OR REPLACE FUNCTION app.prevent_project_phase_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phases cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.project_phases_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.project_id IS DISTINCT FROM OLD.project_id THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase Project link is immutable.';
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase creation audit fields are immutable.';
  END IF;

  IF NOT OLD.is_active
     AND current_setting('app.allow_project_phase_ordering_maintenance', true) IS DISTINCT FROM 'on' THEN
    IF NEW.name IS DISTINCT FROM OLD.name
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.start_date IS DISTINCT FROM OLD.start_date
       OR NEW.end_date IS DISTINCT FROM OLD.end_date
       OR NEW.client_visible IS DISTINCT FROM OLD.client_visible
       OR NEW.is_active IS DISTINCT FROM OLD.is_active
       OR NEW.sequence_no IS DISTINCT FROM OLD.sequence_no THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Inactive Project phase content is immutable.';
    END IF;
  END IF;

  IF NEW.is_active AND NOT OLD.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase reactivation is not supported.';
  END IF;

  IF NEW.sequence_no IS DISTINCT FROM OLD.sequence_no
     AND current_setting('app.allow_project_phase_ordering_maintenance', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase ordering requires trusted functions.';
  END IF;

  IF NEW.is_active IS DISTINCT FROM OLD.is_active
     AND current_setting('app.allow_project_phase_archive', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project phase archival requires trusted functions.';
  END IF;

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER project_phases_no_delete
BEFORE DELETE ON app.project_phases
FOR EACH ROW EXECUTE FUNCTION app.prevent_project_phase_delete();

CREATE TRIGGER project_phases_trusted_update
BEFORE UPDATE ON app.project_phases
FOR EACH ROW EXECUTE FUNCTION app.project_phases_trusted_update_guard();

ALTER TABLE app.project_phases ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project_phases FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.project_phases FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_phase_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.project_phases_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
