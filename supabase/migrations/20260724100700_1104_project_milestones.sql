BEGIN;

CREATE TABLE app.project_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  phase_id uuid,
  name varchar(160) NOT NULL,
  description text,
  due_date date,
  completed_at timestamptz,
  client_visible boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT project_milestones_project_fk
    FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT project_milestones_phase_fk
    FOREIGN KEY (phase_id) REFERENCES app.project_phases(id) ON DELETE RESTRICT,
  CONSTRAINT project_milestones_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_milestones_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_milestones_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT project_milestones_description_ck CHECK (
    description IS NULL OR (btrim(description) <> '' AND length(btrim(description)) <= 4000)
  ),
  CONSTRAINT project_milestones_version_ck CHECK (version_number >= 1)
);

CREATE INDEX project_milestones_project_order_idx
  ON app.project_milestones(project_id, due_date ASC NULLS LAST, created_at ASC, id ASC);

CREATE INDEX project_milestones_project_active_idx
  ON app.project_milestones(project_id, is_active, due_date ASC NULLS LAST, id);

CREATE INDEX project_milestones_phase_idx
  ON app.project_milestones(phase_id, is_active, due_date ASC NULLS LAST, id);

CREATE INDEX project_milestones_client_visible_active_idx
  ON app.project_milestones(project_id, due_date ASC NULLS LAST, created_at ASC, id ASC)
  WHERE is_active AND client_visible;

CREATE OR REPLACE FUNCTION app.prevent_project_milestone_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestones cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.project_milestones_validate_relationships()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  project_row app.projects%ROWTYPE;
  phase_row app.project_phases%ROWTYPE;
BEGIN
  SELECT * INTO project_row
  FROM app.projects AS p
  WHERE p.id = NEW.project_id;

  IF project_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone Project is not available.';
  END IF;

  IF NEW.phase_id IS NOT NULL THEN
    SELECT * INTO phase_row
    FROM app.project_phases AS pp
    WHERE pp.id = NEW.phase_id;

    IF phase_row.id IS NULL OR phase_row.project_id <> NEW.project_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone phase must belong to the same Project.';
    END IF;

    IF NEW.is_active AND NOT phase_row.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone requires an active phase.';
    END IF;
  END IF;

  IF NEW.due_date IS NOT NULL THEN
    IF project_row.start_date IS NOT NULL AND NEW.due_date < project_row.start_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone due date must fit inside Project dates.';
    END IF;
    IF project_row.end_date IS NOT NULL AND NEW.due_date > project_row.end_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone due date must fit inside Project dates.';
    END IF;
    IF NEW.phase_id IS NOT NULL THEN
      IF phase_row.start_date IS NOT NULL AND NEW.due_date < phase_row.start_date THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone due date must fit inside phase dates.';
      END IF;
      IF phase_row.end_date IS NOT NULL AND NEW.due_date > phase_row.end_date THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone due date must fit inside phase dates.';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.project_milestones_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.project_id IS DISTINCT FROM OLD.project_id THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone Project link is immutable.';
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone creation audit fields are immutable.';
  END IF;

  IF NOT OLD.is_active THEN
    IF NEW.name IS DISTINCT FROM OLD.name
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.phase_id IS DISTINCT FROM OLD.phase_id
       OR NEW.due_date IS DISTINCT FROM OLD.due_date
       OR NEW.completed_at IS DISTINCT FROM OLD.completed_at
       OR NEW.client_visible IS DISTINCT FROM OLD.client_visible
       OR NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Inactive Project milestone records are immutable.';
    END IF;
  END IF;

  IF OLD.completed_at IS NOT NULL AND OLD.is_active
     AND current_setting('app.allow_project_milestone_archive', true) IS DISTINCT FROM 'on' THEN
    IF NEW.name IS DISTINCT FROM OLD.name
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.phase_id IS DISTINCT FROM OLD.phase_id
       OR NEW.due_date IS DISTINCT FROM OLD.due_date
       OR NEW.completed_at IS DISTINCT FROM OLD.completed_at
       OR NEW.client_visible IS DISTINCT FROM OLD.client_visible THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Completed Project milestones are read-only.';
    END IF;
  END IF;

  IF NEW.is_active AND NOT OLD.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone reactivation is not supported.';
  END IF;

  IF NEW.completed_at IS DISTINCT FROM OLD.completed_at
     AND current_setting('app.allow_project_milestone_completion', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone completion requires trusted functions.';
  END IF;

  IF NEW.is_active IS DISTINCT FROM OLD.is_active
     AND current_setting('app.allow_project_milestone_archive', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project milestone archival requires trusted functions.';
  END IF;

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER project_milestones_no_delete
BEFORE DELETE ON app.project_milestones
FOR EACH ROW EXECUTE FUNCTION app.prevent_project_milestone_delete();

CREATE TRIGGER project_milestones_validate_relationships
BEFORE INSERT OR UPDATE ON app.project_milestones
FOR EACH ROW EXECUTE FUNCTION app.project_milestones_validate_relationships();

CREATE TRIGGER project_milestones_trusted_update
BEFORE UPDATE ON app.project_milestones
FOR EACH ROW EXECUTE FUNCTION app.project_milestones_trusted_update_guard();

ALTER TABLE app.project_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project_milestones FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.project_milestones FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_milestone_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.project_milestones_validate_relationships() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.project_milestones_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
