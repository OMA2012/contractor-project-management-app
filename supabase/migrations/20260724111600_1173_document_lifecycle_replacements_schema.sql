BEGIN;

CREATE TABLE app.document_replacements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  superseded_document_id uuid NOT NULL,
  replacement_document_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid NOT NULL,
  CONSTRAINT document_replacements_superseded_fk FOREIGN KEY (superseded_document_id) REFERENCES app.documents(id) ON DELETE RESTRICT,
  CONSTRAINT document_replacements_replacement_fk FOREIGN KEY (replacement_document_id) REFERENCES app.documents(id) ON DELETE RESTRICT,
  CONSTRAINT document_replacements_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT document_replacements_not_self_ck CHECK (superseded_document_id <> replacement_document_id),
  CONSTRAINT document_replacements_superseded_uk UNIQUE (superseded_document_id),
  CONSTRAINT document_replacements_replacement_uk UNIQUE (replacement_document_id)
);

CREATE INDEX document_replacements_replacement_idx
  ON app.document_replacements(replacement_document_id, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION app.document_replacements_guard_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF current_setting('app.document_lifecycle_context', true) IS DISTINCT FROM 'owner_document_lifecycle_mutation' THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document replacement history requires trusted lifecycle functions.';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document replacement history is immutable.';
END
$function$;

CREATE TRIGGER document_replacements_guard_history_trg
BEFORE INSERT OR UPDATE OR DELETE ON app.document_replacements
FOR EACH ROW EXECUTE FUNCTION app.document_replacements_guard_history();

ALTER TABLE app.document_replacements ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document_replacements FORCE ROW LEVEL SECURITY;

CREATE TABLE app.document_client_access_privacy (
  document_id uuid PRIMARY KEY,
  privacy_reason varchar(80) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid NOT NULL,
  CONSTRAINT document_client_access_privacy_document_fk FOREIGN KEY (document_id) REFERENCES app.documents(id) ON DELETE RESTRICT,
  CONSTRAINT document_client_access_privacy_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT document_client_access_privacy_reason_ck CHECK (privacy_reason IN ('RESTORED_PRIVATE'))
);

CREATE OR REPLACE FUNCTION app.document_client_access_privacy_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF current_setting('app.document_lifecycle_context', true) IS DISTINCT FROM 'owner_document_lifecycle_mutation' THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document Client access privacy requires trusted lifecycle functions.';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Document Client access privacy is lifecycle-controlled.';
END
$function$;

CREATE TRIGGER document_client_access_privacy_guard_trg
BEFORE INSERT OR UPDATE OR DELETE ON app.document_client_access_privacy
FOR EACH ROW EXECUTE FUNCTION app.document_client_access_privacy_guard();

ALTER TABLE app.document_client_access_privacy ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document_client_access_privacy FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.document_replacements FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_replacements_guard_history() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.document_client_access_privacy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.document_client_access_privacy_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
