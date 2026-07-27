BEGIN;

CREATE TABLE app.project_completion_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES app.projects(id) ON DELETE RESTRICT,
  override_percent numeric(5,2) NOT NULL,
  reason text NOT NULL,
  effective_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  approved_at timestamptz,
  approved_by uuid REFERENCES app.users(id) ON DELETE RESTRICT,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES app.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT project_completion_overrides_percent_ck CHECK (
    override_percent >= 0 AND override_percent <= 100
  ),
  CONSTRAINT project_completion_overrides_reason_ck CHECK (btrim(reason) <> ''),
  CONSTRAINT project_completion_overrides_approval_pair_ck CHECK (
    (approved_at IS NULL AND approved_by IS NULL)
    OR (approved_at IS NOT NULL AND approved_by IS NOT NULL)
  ),
  CONSTRAINT project_completion_overrides_revocation_pair_ck CHECK (
    (revoked_at IS NULL AND revoked_by IS NULL)
    OR (revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
  ),
  CONSTRAINT project_completion_overrides_state_ck CHECK (
    (
      approved_at IS NULL
      AND approved_by IS NULL
      AND revoked_at IS NULL
      AND revoked_by IS NULL
    )
    OR (
      approved_at IS NOT NULL
      AND approved_by IS NOT NULL
      AND revoked_at IS NULL
      AND revoked_by IS NULL
    )
    OR (
      approved_at IS NOT NULL
      AND approved_by IS NOT NULL
      AND revoked_at IS NOT NULL
      AND revoked_by IS NOT NULL
    )
  ),
  CONSTRAINT project_completion_overrides_approver_differs_ck CHECK (
    approved_by IS NULL OR approved_by <> created_by
  ),
  CONSTRAINT project_completion_overrides_approved_after_created_ck CHECK (
    approved_at IS NULL OR approved_at >= created_at
  ),
  CONSTRAINT project_completion_overrides_revoked_after_approved_ck CHECK (
    revoked_at IS NULL OR (approved_at IS NOT NULL AND revoked_at >= approved_at)
  )
);

CREATE UNIQUE INDEX project_completion_overrides_one_active_uk
  ON app.project_completion_overrides(project_id)
  WHERE approved_at IS NOT NULL
    AND approved_by IS NOT NULL
    AND revoked_at IS NULL
    AND revoked_by IS NULL;

CREATE INDEX project_completion_overrides_project_history_idx
  ON app.project_completion_overrides(project_id, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION app.normalize_project_completion_override_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  NEW.reason := btrim(NEW.reason);
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_project_completion_override_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override history cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_project_completion_override_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override history cannot be truncated.';
END
$function$;

CREATE OR REPLACE FUNCTION app.project_completion_overrides_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.override_percent IS DISTINCT FROM OLD.override_percent
     OR NEW.reason IS DISTINCT FROM OLD.reason
     OR NEW.effective_at IS DISTINCT FROM OLD.effective_at
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override business fields are immutable.';
  END IF;

  IF OLD.revoked_at IS NOT NULL OR OLD.revoked_by IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Revoked Project completion override history is immutable.';
  END IF;

  IF OLD.approved_at IS NULL AND OLD.approved_by IS NULL THEN
    IF NEW.revoked_at IS DISTINCT FROM OLD.revoked_at
       OR NEW.revoked_by IS DISTINCT FROM OLD.revoked_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Pending Project completion overrides cannot be revoked.';
    END IF;
    IF NEW.approved_at IS DISTINCT FROM OLD.approved_at
       OR NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN
      IF current_setting('app.allow_project_completion_override_approval', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override approval requires trusted functions.';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.approved_at IS NOT NULL AND OLD.approved_by IS NOT NULL THEN
    IF NEW.approved_at IS DISTINCT FROM OLD.approved_at
       OR NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override approval history is immutable.';
    END IF;
    IF NEW.revoked_at IS DISTINCT FROM OLD.revoked_at
       OR NEW.revoked_by IS DISTINCT FROM OLD.revoked_by THEN
      IF current_setting('app.allow_project_completion_override_revocation', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override revocation requires trusted functions.';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project completion override transition is invalid.';
END
$function$;

CREATE TRIGGER project_completion_overrides_normalize_insert
BEFORE INSERT ON app.project_completion_overrides
FOR EACH ROW EXECUTE FUNCTION app.normalize_project_completion_override_insert();

CREATE TRIGGER project_completion_overrides_trusted_update
BEFORE UPDATE ON app.project_completion_overrides
FOR EACH ROW EXECUTE FUNCTION app.project_completion_overrides_trusted_update_guard();

CREATE TRIGGER project_completion_overrides_no_delete
BEFORE DELETE ON app.project_completion_overrides
FOR EACH ROW EXECUTE FUNCTION app.prevent_project_completion_override_delete();

CREATE TRIGGER project_completion_overrides_no_truncate
BEFORE TRUNCATE ON app.project_completion_overrides
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_project_completion_override_truncate();

ALTER TABLE app.project_completion_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project_completion_overrides FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.project_completion_overrides FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.normalize_project_completion_override_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_completion_override_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_project_completion_override_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.project_completion_overrides_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
