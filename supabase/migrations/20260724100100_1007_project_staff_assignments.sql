BEGIN;

CREATE TYPE app.project_staff_assignment_status AS ENUM (
  'ACTIVE',
  'REMOVED'
);

CREATE TABLE app.project_staff_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  user_id uuid NOT NULL,
  assignment_role_code varchar(40) NOT NULL,
  status app.project_staff_assignment_status NOT NULL DEFAULT 'ACTIVE',
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by uuid NOT NULL,
  removed_at timestamptz,
  removed_by uuid,
  notes text,
  CONSTRAINT project_staff_assignments_project_fk
    FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT project_staff_assignments_user_fk
    FOREIGN KEY (user_id) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_staff_assignments_role_fk
    FOREIGN KEY (assignment_role_code) REFERENCES app.roles(code) ON DELETE RESTRICT,
  CONSTRAINT project_staff_assignments_assigned_by_fk
    FOREIGN KEY (assigned_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_staff_assignments_removed_by_fk
    FOREIGN KEY (removed_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_staff_assignments_role_allowlist_ck CHECK (
    assignment_role_code IN ('project_manager', 'site_supervisor')
  ),
  CONSTRAINT project_staff_assignments_notes_ck CHECK (
    notes IS NULL OR (btrim(notes) <> '' AND length(btrim(notes)) <= 4000)
  ),
  CONSTRAINT project_staff_assignments_lifecycle_ck CHECK (
    (
      status = 'ACTIVE'
      AND removed_at IS NULL
      AND removed_by IS NULL
    )
    OR
    (
      status = 'REMOVED'
      AND removed_at IS NOT NULL
      AND removed_by IS NOT NULL
    )
  )
);

CREATE UNIQUE INDEX project_staff_assignments_one_active_idx
  ON app.project_staff_assignments(project_id, user_id, assignment_role_code)
  WHERE status = 'ACTIVE';

CREATE INDEX project_staff_assignments_project_order_idx
  ON app.project_staff_assignments(project_id, status, assigned_at DESC, id DESC);

CREATE INDEX project_staff_assignments_user_active_idx
  ON app.project_staff_assignments(user_id, project_id, assignment_role_code)
  WHERE status = 'ACTIVE';

CREATE INDEX project_staff_assignments_role_active_idx
  ON app.project_staff_assignments(assignment_role_code, user_id)
  WHERE status = 'ACTIVE';

CREATE OR REPLACE FUNCTION app.prevent_project_staff_assignment_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignments cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.project_staff_assignments_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF OLD.status = 'REMOVED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Removed Project staff assignments are immutable.';
  END IF;

  IF NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.assignment_role_code IS DISTINCT FROM OLD.assignment_role_code
     OR NEW.assigned_at IS DISTINCT FROM OLD.assigned_at
     OR NEW.assigned_by IS DISTINCT FROM OLD.assigned_by
     OR NEW.notes IS DISTINCT FROM OLD.notes THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment identity is immutable.';
  END IF;

  IF NEW.status = 'ACTIVE'
     AND OLD.status = 'REMOVED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Removed Project staff assignments cannot be reactivated.';
  END IF;

  IF (NEW.status IS DISTINCT FROM OLD.status
      OR NEW.removed_at IS DISTINCT FROM OLD.removed_at
      OR NEW.removed_by IS DISTINCT FROM OLD.removed_by)
     AND current_setting('app.allow_project_staff_assignment_removal', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project staff assignment removal requires trusted functions.';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER project_staff_assignments_no_delete
BEFORE DELETE ON app.project_staff_assignments
FOR EACH ROW EXECUTE FUNCTION app.prevent_project_staff_assignment_delete();

CREATE TRIGGER project_staff_assignments_trusted_update
BEFORE UPDATE ON app.project_staff_assignments
FOR EACH ROW EXECUTE FUNCTION app.project_staff_assignments_trusted_update_guard();

ALTER TABLE app.project_staff_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project_staff_assignments FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.project_staff_assignments FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_staff_assignment_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.project_staff_assignments_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
