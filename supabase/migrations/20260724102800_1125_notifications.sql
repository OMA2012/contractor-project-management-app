BEGIN;

CREATE TYPE app.notification_status AS ENUM (
  'UNREAD',
  'READ',
  'ARCHIVED'
);

CREATE TABLE app.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  project_id uuid REFERENCES app.projects(id) ON DELETE RESTRICT,
  notification_type varchar(60) NOT NULL,
  title varchar(200) NOT NULL,
  body text NOT NULL,
  status app.notification_status NOT NULL DEFAULT 'UNREAD',
  related_entity_type varchar(60),
  related_entity_id uuid,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  read_at timestamptz,
  archived_at timestamptz,
  CONSTRAINT notifications_type_nonblank_ck CHECK (btrim(notification_type) <> ''),
  CONSTRAINT notifications_title_nonblank_ck CHECK (btrim(title) <> ''),
  CONSTRAINT notifications_body_nonblank_ck CHECK (btrim(body) <> ''),
  CONSTRAINT notifications_related_pair_ck CHECK (
    (related_entity_type IS NULL AND related_entity_id IS NULL)
    OR (related_entity_type IS NOT NULL AND related_entity_id IS NOT NULL AND btrim(related_entity_type) <> '')
  ),
  CONSTRAINT notifications_state_ck CHECK (
    (
      status = 'UNREAD'
      AND archived_at IS NULL
    )
    OR (
      status = 'READ'
      AND read_at IS NOT NULL
      AND archived_at IS NULL
    )
    OR (
      status = 'ARCHIVED'
      AND archived_at IS NOT NULL
    )
  ),
  CONSTRAINT notifications_timestamp_order_ck CHECK (
    (read_at IS NULL OR read_at >= created_at)
    AND (archived_at IS NULL OR archived_at >= created_at)
    AND (read_at IS NULL OR archived_at IS NULL OR archived_at >= read_at)
  )
);

CREATE INDEX notifications_recipient_inbox_idx
  ON app.notifications(recipient_user_id, created_at DESC, id DESC);

CREATE INDEX notifications_recipient_unread_idx
  ON app.notifications(recipient_user_id, created_at DESC, id DESC)
  WHERE status = 'UNREAD';

CREATE INDEX notifications_project_context_idx
  ON app.notifications(project_id, created_at DESC, id DESC)
  WHERE project_id IS NOT NULL;

CREATE UNIQUE INDEX notifications_related_unique_idx
  ON app.notifications(recipient_user_id, notification_type, related_entity_type, related_entity_id)
  WHERE related_entity_type IS NOT NULL
    AND related_entity_id IS NOT NULL;

CREATE OR REPLACE FUNCTION app.notifications_normalize_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_setting('app.notification_creation_context', true) IS DISTINCT FROM 'progress_update_publication' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notifications require trusted creation context.';
  END IF;

  NEW.notification_type := btrim(NEW.notification_type);
  NEW.title := btrim(NEW.title);
  NEW.body := btrim(NEW.body);
  IF NEW.related_entity_type IS NOT NULL THEN
    NEW.related_entity_type := NULLIF(btrim(NEW.related_entity_type), '');
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.notifications_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_setting('app.notification_state_context', true) IS DISTINCT FROM 'current_recipient_state_change' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notifications require trusted state functions.';
  END IF;

  IF NEW.recipient_user_id IS DISTINCT FROM OLD.recipient_user_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.notification_type IS DISTINCT FROM OLD.notification_type
     OR NEW.title IS DISTINCT FROM OLD.title
     OR NEW.body IS DISTINCT FROM OLD.body
     OR NEW.related_entity_type IS DISTINCT FROM OLD.related_entity_type
     OR NEW.related_entity_id IS DISTINCT FROM OLD.related_entity_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notification identity fields are immutable.';
  END IF;

  IF OLD.read_at IS NOT NULL AND NEW.read_at IS DISTINCT FROM OLD.read_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notification first-read timestamp is immutable.';
  END IF;
  IF OLD.archived_at IS NOT NULL AND NEW.archived_at IS DISTINCT FROM OLD.archived_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notification archive timestamp is immutable.';
  END IF;
  IF OLD.status = 'ARCHIVED' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Archived notifications are terminal.';
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_notification_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notifications cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_notification_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notifications cannot be truncated.';
END
$function$;

CREATE TRIGGER notifications_normalize_insert
BEFORE INSERT ON app.notifications
FOR EACH ROW EXECUTE FUNCTION app.notifications_normalize_insert();

CREATE TRIGGER notifications_trusted_update
BEFORE UPDATE ON app.notifications
FOR EACH ROW EXECUTE FUNCTION app.notifications_trusted_update_guard();

CREATE TRIGGER notifications_no_delete
BEFORE DELETE ON app.notifications
FOR EACH ROW EXECUTE FUNCTION app.prevent_notification_delete();

CREATE TRIGGER notifications_no_truncate
BEFORE TRUNCATE ON app.notifications
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_notification_truncate();

ALTER TABLE app.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notifications FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.notifications FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.notifications_normalize_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.notifications_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_notification_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_notification_truncate() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
