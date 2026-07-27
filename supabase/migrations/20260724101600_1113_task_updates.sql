BEGIN;

CREATE TABLE app.task_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES app.tasks(id) ON DELETE RESTRICT,
  previous_status app.project_task_status,
  new_status app.project_task_status NOT NULL,
  previous_completion_percent numeric(5,2),
  new_completion_percent numeric(5,2) NOT NULL,
  update_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT task_updates_previous_completion_percent_ck CHECK (
    previous_completion_percent IS NULL OR (previous_completion_percent >= 0 AND previous_completion_percent <= 100)
  ),
  CONSTRAINT task_updates_new_completion_percent_ck CHECK (
    new_completion_percent >= 0 AND new_completion_percent <= 100
  ),
  CONSTRAINT task_updates_update_note_ck CHECK (
    update_note IS NULL OR (btrim(update_note) <> '' AND length(update_note) <= 4000)
  )
);

CREATE INDEX task_updates_task_history_idx
  ON app.task_updates(task_id, created_at ASC, id ASC);

CREATE INDEX task_updates_actor_audit_idx
  ON app.task_updates(created_by, created_at ASC, id ASC);

CREATE OR REPLACE FUNCTION app.normalize_task_update_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.update_note IS NOT NULL THEN
    NEW.update_note := nullif(btrim(NEW.update_note), '');
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_task_update_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task update history is append-only.';
END
$function$;

CREATE TRIGGER task_updates_normalize_insert
BEFORE INSERT ON app.task_updates
FOR EACH ROW EXECUTE FUNCTION app.normalize_task_update_insert();

CREATE TRIGGER task_updates_no_update
BEFORE UPDATE ON app.task_updates
FOR EACH ROW EXECUTE FUNCTION app.prevent_task_update_mutation();

CREATE TRIGGER task_updates_no_delete
BEFORE DELETE ON app.task_updates
FOR EACH ROW EXECUTE FUNCTION app.prevent_task_update_mutation();

CREATE TRIGGER task_updates_no_truncate
BEFORE TRUNCATE ON app.task_updates
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_task_update_mutation();

ALTER TABLE app.tasks DROP CONSTRAINT tasks_initial_workflow_ck;

ALTER TABLE app.tasks
  ADD CONSTRAINT tasks_workflow_state_ck CHECK (
    (
      status = 'COMPLETED'
      AND completion_percent = 100
      AND completed_at IS NOT NULL
    )
    OR (
      status <> 'COMPLETED'
      AND completion_percent < 100
      AND completed_at IS NULL
    )
  );

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
    IF current_setting('app.allow_project_task_workflow', true) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task workflow fields require trusted functions.';
    END IF;
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
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.completion_percent IS DISTINCT FROM OLD.completion_percent
       OR NEW.completed_at IS DISTINCT FROM OLD.completed_at
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

ALTER TABLE app.task_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.task_updates FORCE ROW LEVEL SECURITY;

REVOKE ALL ON FUNCTION app.normalize_task_update_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_task_update_mutation() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
