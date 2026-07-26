BEGIN;

CREATE TYPE app.project_task_status AS ENUM (
  'TODO',
  'IN_PROGRESS',
  'BLOCKED',
  'COMPLETED',
  'CANCELLED'
);

CREATE TABLE app.project_task_number_counters (
  project_id uuid PRIMARY KEY,
  last_value integer NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT project_task_number_counters_project_fk
    FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT project_task_number_counters_last_value_ck CHECK (last_value >= 1)
);

CREATE OR REPLACE FUNCTION app.prevent_project_task_number_counter_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task number counters cannot be deleted.';
END
$function$;

CREATE TRIGGER project_task_number_counters_no_delete
BEFORE DELETE ON app.project_task_number_counters
FOR EACH ROW EXECUTE FUNCTION app.prevent_project_task_number_counter_delete();

ALTER TABLE app.project_task_number_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project_task_number_counters FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION app.generate_project_task_number(p_project_id uuid)
RETURNS varchar(40)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  allocated_value integer;
BEGIN
  IF p_project_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task number requires a Project.';
  END IF;

  INSERT INTO app.project_task_number_counters (project_id, last_value)
  VALUES (p_project_id, 1)
  ON CONFLICT (project_id)
  DO UPDATE
  SET last_value = app.project_task_number_counters.last_value + 1,
      updated_at = now()
  RETURNING last_value
  INTO allocated_value;

  RETURN 'TSK-' || lpad(allocated_value::text, 4, '0');
END
$function$;

CREATE TABLE app.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  phase_id uuid,
  milestone_id uuid,
  task_number varchar(40) NOT NULL,
  title varchar(200) NOT NULL,
  description text,
  client_summary text,
  status app.project_task_status NOT NULL DEFAULT 'TODO',
  completion_percent numeric(5,2) NOT NULL DEFAULT 0,
  weight_percent numeric(7,4),
  counts_toward_completion boolean NOT NULL DEFAULT true,
  start_date date,
  due_date date,
  completed_at timestamptz,
  client_visible boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT tasks_project_fk
    FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT tasks_phase_fk
    FOREIGN KEY (phase_id) REFERENCES app.project_phases(id) ON DELETE RESTRICT,
  CONSTRAINT tasks_milestone_fk
    FOREIGN KEY (milestone_id) REFERENCES app.project_milestones(id) ON DELETE RESTRICT,
  CONSTRAINT tasks_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT tasks_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT tasks_project_task_number_uk UNIQUE (project_id, task_number),
  CONSTRAINT tasks_task_number_ck CHECK (task_number ~ '^TSK-[0-9]{4,}$'),
  CONSTRAINT tasks_title_ck CHECK (btrim(title) <> ''),
  CONSTRAINT tasks_description_ck CHECK (
    description IS NULL OR (btrim(description) <> '' AND length(btrim(description)) <= 4000)
  ),
  CONSTRAINT tasks_client_summary_ck CHECK (
    client_summary IS NULL OR (btrim(client_summary) <> '' AND length(btrim(client_summary)) <= 4000)
  ),
  CONSTRAINT tasks_completion_percent_ck CHECK (completion_percent >= 0 AND completion_percent <= 100),
  CONSTRAINT tasks_initial_workflow_ck CHECK (
    status = 'TODO'
    AND completion_percent = 0
    AND completed_at IS NULL
  ),
  CONSTRAINT tasks_weight_ck CHECK (
    (counts_toward_completion AND (weight_percent IS NULL OR (weight_percent > 0 AND weight_percent <= 100)))
    OR ((NOT counts_toward_completion) AND weight_percent IS NULL)
  ),
  CONSTRAINT tasks_date_order_ck CHECK (start_date IS NULL OR due_date IS NULL OR start_date <= due_date),
  CONSTRAINT tasks_version_ck CHECK (version_number >= 1)
);

CREATE INDEX tasks_project_order_idx
  ON app.tasks(project_id, due_date ASC NULLS LAST, created_at ASC, id ASC);

CREATE INDEX tasks_project_active_idx
  ON app.tasks(project_id, is_active, due_date ASC NULLS LAST, id);

CREATE INDEX tasks_phase_active_idx
  ON app.tasks(phase_id, is_active, due_date ASC NULLS LAST, id);

CREATE INDEX tasks_milestone_active_idx
  ON app.tasks(milestone_id, is_active, due_date ASC NULLS LAST, id);

CREATE INDEX tasks_client_visible_active_idx
  ON app.tasks(project_id, due_date ASC NULLS LAST, created_at ASC, id ASC)
  WHERE is_active AND client_visible;

CREATE OR REPLACE FUNCTION app.prevent_task_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project tasks cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.tasks_validate_relationships()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  project_row app.projects%ROWTYPE;
  phase_row app.project_phases%ROWTYPE;
  milestone_row app.project_milestones%ROWTYPE;
BEGIN
  SELECT * INTO project_row FROM app.projects AS p WHERE p.id = NEW.project_id;
  IF project_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task Project is not available.';
  END IF;

  IF NEW.phase_id IS NOT NULL THEN
    SELECT * INTO phase_row FROM app.project_phases AS pp WHERE pp.id = NEW.phase_id;
    IF phase_row.id IS NULL OR phase_row.project_id <> NEW.project_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task phase must belong to the same Project.';
    END IF;
    IF NEW.is_active AND NOT phase_row.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task requires an active Project phase.';
    END IF;
  END IF;

  IF NEW.milestone_id IS NOT NULL THEN
    SELECT * INTO milestone_row FROM app.project_milestones AS pm WHERE pm.id = NEW.milestone_id;
    IF milestone_row.id IS NULL OR milestone_row.project_id <> NEW.project_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task milestone must belong to the same Project.';
    END IF;
    IF NEW.is_active AND NOT milestone_row.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task requires an active Project milestone.';
    END IF;
    IF NEW.phase_id IS NOT NULL
       AND milestone_row.phase_id IS NOT NULL
       AND milestone_row.phase_id <> NEW.phase_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task phase must match the milestone phase.';
    END IF;
  END IF;

  IF NEW.start_date IS NOT NULL THEN
    IF project_row.start_date IS NOT NULL AND NEW.start_date < project_row.start_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task dates must fit inside Project dates.';
    END IF;
    IF project_row.end_date IS NOT NULL AND NEW.start_date > project_row.end_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task dates must fit inside Project dates.';
    END IF;
  END IF;
  IF NEW.due_date IS NOT NULL THEN
    IF project_row.start_date IS NOT NULL AND NEW.due_date < project_row.start_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task dates must fit inside Project dates.';
    END IF;
    IF project_row.end_date IS NOT NULL AND NEW.due_date > project_row.end_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task dates must fit inside Project dates.';
    END IF;
  END IF;

  IF NEW.phase_id IS NOT NULL THEN
    IF NEW.start_date IS NOT NULL AND phase_row.start_date IS NOT NULL AND NEW.start_date < phase_row.start_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task dates must fit inside Project phase dates.';
    END IF;
    IF NEW.due_date IS NOT NULL AND phase_row.end_date IS NOT NULL AND NEW.due_date > phase_row.end_date THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task dates must fit inside Project phase dates.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.tasks_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.project_id IS DISTINCT FROM OLD.project_id OR NEW.task_number IS DISTINCT FROM OLD.task_number THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task identity fields are immutable.';
  END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task creation audit fields are immutable.';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status
     OR NEW.completion_percent IS DISTINCT FROM OLD.completion_percent
     OR NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task workflow fields require later trusted functions.';
  END IF;
  IF NOT OLD.is_active THEN
    IF NEW.title IS DISTINCT FROM OLD.title
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.client_summary IS DISTINCT FROM OLD.client_summary
       OR NEW.phase_id IS DISTINCT FROM OLD.phase_id
       OR NEW.milestone_id IS DISTINCT FROM OLD.milestone_id
       OR NEW.weight_percent IS DISTINCT FROM OLD.weight_percent
       OR NEW.counts_toward_completion IS DISTINCT FROM OLD.counts_toward_completion
       OR NEW.start_date IS DISTINCT FROM OLD.start_date
       OR NEW.due_date IS DISTINCT FROM OLD.due_date
       OR NEW.client_visible IS DISTINCT FROM OLD.client_visible
       OR NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Inactive Project task records are immutable.';
    END IF;
  END IF;
  IF NEW.is_active AND NOT OLD.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task reactivation is not supported.';
  END IF;
  IF NEW.is_active IS DISTINCT FROM OLD.is_active
     AND current_setting('app.allow_project_task_archive', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task archival requires trusted functions.';
  END IF;

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER tasks_no_delete
BEFORE DELETE ON app.tasks
FOR EACH ROW EXECUTE FUNCTION app.prevent_task_delete();

CREATE TRIGGER tasks_validate_relationships
BEFORE INSERT OR UPDATE ON app.tasks
FOR EACH ROW EXECUTE FUNCTION app.tasks_validate_relationships();

CREATE TRIGGER tasks_trusted_update
BEFORE UPDATE ON app.tasks
FOR EACH ROW EXECUTE FUNCTION app.tasks_trusted_update_guard();

ALTER TABLE app.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.tasks FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.project_task_number_counters FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.tasks FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.generate_project_task_number(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_task_number_counter_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_task_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.tasks_validate_relationships() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.tasks_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
