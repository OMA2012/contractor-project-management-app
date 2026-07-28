BEGIN;

CREATE TYPE app.progress_update_status AS ENUM (
  'DRAFT',
  'SUBMITTED',
  'APPROVED',
  'REJECTED'
);

CREATE TABLE app.progress_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES app.projects(id) ON DELETE RESTRICT,
  milestone_id uuid REFERENCES app.project_milestones(id) ON DELETE RESTRICT,
  title varchar(200) NOT NULL,
  summary text NOT NULL,
  reported_completion_percent numeric(5,2),
  status app.progress_update_status NOT NULL DEFAULT 'DRAFT',
  client_visible boolean NOT NULL DEFAULT false,
  submitted_at timestamptz,
  submitted_by uuid REFERENCES app.users(id) ON DELETE RESTRICT,
  approved_at timestamptz,
  approved_by uuid REFERENCES app.users(id) ON DELETE RESTRICT,
  rejected_at timestamptz,
  rejected_by uuid REFERENCES app.users(id) ON DELETE RESTRICT,
  rejection_reason text,
  published_at timestamptz,
  archived_at timestamptz,
  archived_by uuid REFERENCES app.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT progress_updates_title_ck CHECK (btrim(title) <> ''),
  CONSTRAINT progress_updates_summary_ck CHECK (btrim(summary) <> ''),
  CONSTRAINT progress_updates_reported_completion_ck CHECK (
    reported_completion_percent IS NULL
    OR (reported_completion_percent >= 0 AND reported_completion_percent <= 100)
  ),
  CONSTRAINT progress_updates_version_ck CHECK (version_number >= 1),
  CONSTRAINT progress_updates_archive_pair_ck CHECK (
    (archived_at IS NULL AND archived_by IS NULL)
    OR (archived_at IS NOT NULL AND archived_by IS NOT NULL)
  ),
  CONSTRAINT progress_updates_approver_differs_ck CHECK (
    approved_by IS NULL OR approved_by <> created_by
  ),
  CONSTRAINT progress_updates_publication_visibility_ck CHECK (
    published_at IS NULL OR client_visible
  ),
  CONSTRAINT progress_updates_state_ck CHECK (
    (
      status = 'DRAFT'
      AND submitted_at IS NULL
      AND submitted_by IS NULL
      AND approved_at IS NULL
      AND approved_by IS NULL
      AND rejected_at IS NULL
      AND rejected_by IS NULL
      AND rejection_reason IS NULL
      AND published_at IS NULL
    )
    OR (
      status = 'SUBMITTED'
      AND submitted_at IS NOT NULL
      AND submitted_by IS NOT NULL
      AND approved_at IS NULL
      AND approved_by IS NULL
      AND rejected_at IS NULL
      AND rejected_by IS NULL
      AND rejection_reason IS NULL
      AND published_at IS NULL
    )
    OR (
      status = 'APPROVED'
      AND submitted_at IS NOT NULL
      AND submitted_by IS NOT NULL
      AND approved_at IS NOT NULL
      AND approved_by IS NOT NULL
      AND rejected_at IS NULL
      AND rejected_by IS NULL
      AND rejection_reason IS NULL
    )
    OR (
      status = 'REJECTED'
      AND submitted_at IS NOT NULL
      AND submitted_by IS NOT NULL
      AND approved_at IS NULL
      AND approved_by IS NULL
      AND rejected_at IS NOT NULL
      AND rejected_by IS NOT NULL
      AND btrim(coalesce(rejection_reason, '')) <> ''
      AND published_at IS NULL
    )
  ),
  CONSTRAINT progress_updates_timestamp_order_ck CHECK (
    (submitted_at IS NULL OR created_at <= submitted_at)
    AND (approved_at IS NULL OR submitted_at <= approved_at)
    AND (rejected_at IS NULL OR submitted_at <= rejected_at)
    AND (published_at IS NULL OR approved_at <= published_at)
    AND (
      archived_at IS NULL
      OR (
        (published_at IS NULL OR published_at <= archived_at)
        AND (rejected_at IS NULL OR rejected_at <= archived_at)
      )
    )
  )
);

CREATE INDEX progress_updates_project_order_idx
  ON app.progress_updates(project_id, created_at DESC, id DESC);

CREATE INDEX progress_updates_project_status_order_idx
  ON app.progress_updates(project_id, status, created_at DESC, id DESC);

CREATE INDEX progress_updates_milestone_order_idx
  ON app.progress_updates(milestone_id, created_at DESC, id DESC)
  WHERE milestone_id IS NOT NULL;

CREATE INDEX progress_updates_client_feed_idx
  ON app.progress_updates(project_id, published_at DESC, id DESC)
  WHERE status = 'APPROVED'
    AND client_visible
    AND published_at IS NOT NULL
    AND archived_at IS NULL;

CREATE OR REPLACE FUNCTION app.progress_updates_normalize_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  NEW.title := btrim(NEW.title);
  NEW.summary := btrim(NEW.summary);
  IF NEW.rejection_reason IS NOT NULL THEN
    NEW.rejection_reason := NULLIF(btrim(NEW.rejection_reason), '');
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.progress_updates_validate_relationships()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  milestone_row app.project_milestones%ROWTYPE;
BEGIN
  IF NEW.milestone_id IS NOT NULL THEN
    SELECT * INTO milestone_row
    FROM app.project_milestones AS pm
    WHERE pm.id = NEW.milestone_id;

    IF milestone_row.id IS NULL OR milestone_row.project_id <> NEW.project_id THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update milestone must belong to the same Project.';
    END IF;

    IF NEW.status = 'DRAFT'
       AND NOT milestone_row.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update requires an active milestone.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_progress_update_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress updates cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_progress_update_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress updates cannot be truncated.';
END
$function$;

CREATE OR REPLACE FUNCTION app.progress_updates_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_setting('app.allow_progress_update_mutation', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress updates require trusted workflow functions.';
  END IF;

  NEW.title := btrim(NEW.title);
  NEW.summary := btrim(NEW.summary);
  IF NEW.rejection_reason IS NOT NULL THEN
    NEW.rejection_reason := NULLIF(btrim(NEW.rejection_reason), '');
  END IF;

  IF NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update identity fields are immutable.';
  END IF;

  IF OLD.status <> 'DRAFT'
     AND (
       NEW.title IS DISTINCT FROM OLD.title
       OR NEW.summary IS DISTINCT FROM OLD.summary
       OR NEW.reported_completion_percent IS DISTINCT FROM OLD.reported_completion_percent
       OR NEW.milestone_id IS DISTINCT FROM OLD.milestone_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Submitted progress update content is immutable.';
  END IF;

  IF OLD.status <> 'DRAFT' AND NEW.status = 'DRAFT' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress updates cannot return to draft.';
  END IF;

  IF OLD.status = 'REJECTED' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Rejected progress updates are terminal.';
  END IF;

  IF OLD.submitted_at IS NOT NULL AND NEW.submitted_at IS DISTINCT FROM OLD.submitted_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update submission timestamp is immutable.';
  END IF;
  IF OLD.submitted_by IS NOT NULL AND NEW.submitted_by IS DISTINCT FROM OLD.submitted_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update submitter is immutable.';
  END IF;
  IF OLD.approved_at IS NOT NULL AND NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update approval timestamp is immutable.';
  END IF;
  IF OLD.approved_by IS NOT NULL AND NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update approver is immutable.';
  END IF;
  IF OLD.rejected_at IS NOT NULL AND NEW.rejected_at IS DISTINCT FROM OLD.rejected_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update rejection timestamp is immutable.';
  END IF;
  IF OLD.rejected_by IS NOT NULL AND NEW.rejected_by IS DISTINCT FROM OLD.rejected_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update rejector is immutable.';
  END IF;
  IF OLD.rejection_reason IS NOT NULL AND NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update rejection reason is immutable.';
  END IF;
  IF OLD.published_at IS NOT NULL AND NEW.published_at IS DISTINCT FROM OLD.published_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update publication timestamp is immutable.';
  END IF;
  IF OLD.archived_at IS NOT NULL AND NEW.archived_at IS DISTINCT FROM OLD.archived_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update archive timestamp is immutable.';
  END IF;
  IF OLD.archived_by IS NOT NULL AND NEW.archived_by IS DISTINCT FROM OLD.archived_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update archive actor is immutable.';
  END IF;
  IF OLD.published_at IS NOT NULL AND NEW.client_visible IS DISTINCT FROM OLD.client_visible THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Published progress update visibility is immutable.';
  END IF;

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER progress_updates_normalize_insert
BEFORE INSERT ON app.progress_updates
FOR EACH ROW EXECUTE FUNCTION app.progress_updates_normalize_insert();

CREATE TRIGGER progress_updates_validate_relationships
BEFORE INSERT OR UPDATE ON app.progress_updates
FOR EACH ROW EXECUTE FUNCTION app.progress_updates_validate_relationships();

CREATE TRIGGER progress_updates_trusted_update
BEFORE UPDATE ON app.progress_updates
FOR EACH ROW EXECUTE FUNCTION app.progress_updates_trusted_update_guard();

CREATE TRIGGER progress_updates_no_delete
BEFORE DELETE ON app.progress_updates
FOR EACH ROW EXECUTE FUNCTION app.prevent_progress_update_delete();

CREATE TRIGGER progress_updates_no_truncate
BEFORE TRUNCATE ON app.progress_updates
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_progress_update_truncate();

ALTER TABLE app.progress_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.progress_updates FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.progress_updates FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.progress_updates_normalize_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.progress_updates_validate_relationships() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_progress_update_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_progress_update_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.progress_updates_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
