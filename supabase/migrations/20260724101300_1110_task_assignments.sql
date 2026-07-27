BEGIN;

CREATE TABLE app.task_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  project_staff_assignment_id uuid NOT NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by uuid NOT NULL,
  removed_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT task_assignments_task_fk
    FOREIGN KEY (task_id) REFERENCES app.tasks(id) ON DELETE RESTRICT,
  CONSTRAINT task_assignments_project_staff_assignment_fk
    FOREIGN KEY (project_staff_assignment_id) REFERENCES app.project_staff_assignments(id) ON DELETE RESTRICT,
  CONSTRAINT task_assignments_assigned_by_fk
    FOREIGN KEY (assigned_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT task_assignments_lifecycle_ck CHECK (
    (is_active AND removed_at IS NULL)
    OR
    ((NOT is_active) AND removed_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX task_assignments_one_active_pair_idx
  ON app.task_assignments(task_id, project_staff_assignment_id)
  WHERE is_active;

CREATE INDEX task_assignments_task_order_idx
  ON app.task_assignments(task_id, is_active DESC, assigned_at ASC, id ASC);

CREATE INDEX task_assignments_project_staff_assignment_active_idx
  ON app.task_assignments(project_staff_assignment_id, task_id)
  WHERE is_active;

CREATE OR REPLACE FUNCTION app.prevent_task_assignment_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task assignments cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.task_assignments_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT OLD.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Inactive Project task assignments are immutable.';
  END IF;

  IF NEW.task_id IS DISTINCT FROM OLD.task_id
     OR NEW.project_staff_assignment_id IS DISTINCT FROM OLD.project_staff_assignment_id
     OR NEW.assigned_at IS DISTINCT FROM OLD.assigned_at
     OR NEW.assigned_by IS DISTINCT FROM OLD.assigned_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task assignment identity is immutable.';
  END IF;

  IF NEW.is_active AND NOT OLD.is_active THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Inactive Project task assignments cannot be reactivated.';
  END IF;

  IF (NEW.is_active IS DISTINCT FROM OLD.is_active
      OR NEW.removed_at IS DISTINCT FROM OLD.removed_at)
     AND current_setting('app.allow_project_task_assignment_removal', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task assignment removal requires trusted functions.';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER task_assignments_no_delete
BEFORE DELETE ON app.task_assignments
FOR EACH ROW EXECUTE FUNCTION app.prevent_task_assignment_delete();

CREATE TRIGGER task_assignments_trusted_update
BEFORE UPDATE ON app.task_assignments
FOR EACH ROW EXECUTE FUNCTION app.task_assignments_trusted_update_guard();

ALTER TABLE app.task_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.task_assignments FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.task_assignments FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_task_assignment_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.task_assignments_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
