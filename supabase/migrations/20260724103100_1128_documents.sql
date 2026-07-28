BEGIN;

CREATE SEQUENCE app.document_number_seq
  AS bigint
  START WITH 1
  INCREMENT BY 1
  MINVALUE 1
  MAXVALUE 999999
  NO CYCLE;

CREATE TYPE app.document_status AS ENUM (
  'ACTIVE',
  'ARCHIVED'
);

CREATE TABLE app.document_types (
  code varchar(50) PRIMARY KEY,
  name varchar(120) NOT NULL,
  default_client_visible boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT document_types_name_uk UNIQUE (name),
  CONSTRAINT document_types_code_ck CHECK (code ~ '^[A-Z][A-Z0-9_]{0,49}$'),
  CONSTRAINT document_types_name_ck CHECK (btrim(name) <> '')
);

INSERT INTO app.document_types (code, name, default_client_visible, is_active)
VALUES
  ('GENERAL', 'General Document', false, true),
  ('CONTRACT', 'Contract', false, true);

CREATE TABLE app.documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_number varchar(60) NOT NULL DEFAULT ('DOC-' || lpad(nextval('app.document_number_seq')::text, 6, '0')),
  storage_bucket varchar(100) NOT NULL,
  storage_object_key text NOT NULL,
  original_file_name varchar(255) NOT NULL,
  mime_type varchar(150) NOT NULL,
  file_size_bytes bigint NOT NULL,
  sha256_hash bytea NOT NULL,
  document_type_code varchar(50) NOT NULL,
  status app.document_status NOT NULL DEFAULT 'ACTIVE',
  client_visible boolean NOT NULL DEFAULT false,
  notes text,
  uploaded_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  uploaded_by uuid NOT NULL,
  archived_at timestamptz,
  archived_by uuid,
  CONSTRAINT documents_document_number_uk UNIQUE (document_number),
  CONSTRAINT documents_storage_object_key_uk UNIQUE (storage_object_key),
  CONSTRAINT documents_type_fk FOREIGN KEY (document_type_code) REFERENCES app.document_types(code) ON DELETE RESTRICT,
  CONSTRAINT documents_uploaded_by_fk FOREIGN KEY (uploaded_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT documents_archived_by_fk FOREIGN KEY (archived_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT documents_document_number_ck CHECK (document_number ~ '^DOC-[0-9]{6}$'),
  CONSTRAINT documents_storage_bucket_ck CHECK (btrim(storage_bucket) <> ''),
  CONSTRAINT documents_storage_object_key_ck CHECK (btrim(storage_object_key) <> ''),
  CONSTRAINT documents_original_file_name_ck CHECK (btrim(original_file_name) <> ''),
  CONSTRAINT documents_mime_type_ck CHECK (btrim(mime_type) <> ''),
  CONSTRAINT documents_file_size_bytes_ck CHECK (file_size_bytes > 0),
  CONSTRAINT documents_sha256_hash_ck CHECK (octet_length(sha256_hash) = 32),
  CONSTRAINT documents_archive_pair_ck CHECK (
    (archived_at IS NULL AND archived_by IS NULL)
    OR (archived_at IS NOT NULL AND archived_by IS NOT NULL)
  ),
  CONSTRAINT documents_status_archive_ck CHECK (
    (status = 'ACTIVE' AND archived_at IS NULL AND archived_by IS NULL)
    OR (status = 'ARCHIVED' AND archived_at IS NOT NULL AND archived_by IS NOT NULL)
  )
);

CREATE TABLE app.document_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL,
  client_id uuid,
  project_id uuid,
  task_id uuid,
  progress_update_id uuid,
  client_payment_id uuid,
  payment_request_id uuid,
  project_expense_id uuid,
  currency_exchange_id uuid,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid NOT NULL,
  CONSTRAINT document_links_document_fk FOREIGN KEY (document_id) REFERENCES app.documents(id) ON DELETE RESTRICT,
  CONSTRAINT document_links_client_fk FOREIGN KEY (client_id) REFERENCES app.clients(id) ON DELETE RESTRICT,
  CONSTRAINT document_links_project_fk FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT document_links_task_fk FOREIGN KEY (task_id) REFERENCES app.tasks(id) ON DELETE RESTRICT,
  CONSTRAINT document_links_progress_update_fk FOREIGN KEY (progress_update_id) REFERENCES app.progress_updates(id) ON DELETE RESTRICT,
  CONSTRAINT document_links_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT document_links_exactly_one_target_ck CHECK (
    num_nonnulls(client_id, project_id, task_id, progress_update_id, client_payment_id, payment_request_id, project_expense_id, currency_exchange_id) = 1
  ),
  CONSTRAINT document_links_finance_targets_disabled_ck CHECK (
    client_payment_id IS NULL
    AND payment_request_id IS NULL
    AND project_expense_id IS NULL
    AND currency_exchange_id IS NULL
  )
);

CREATE INDEX documents_uploaded_order_idx
  ON app.documents(uploaded_at DESC, id DESC);

CREATE INDEX documents_type_status_idx
  ON app.documents(document_type_code, status, uploaded_at DESC, id DESC);

CREATE INDEX document_links_document_idx
  ON app.document_links(document_id, created_at DESC, id DESC);

CREATE INDEX document_links_client_idx
  ON app.document_links(client_id, created_at DESC, id DESC)
  WHERE client_id IS NOT NULL;

CREATE INDEX document_links_project_idx
  ON app.document_links(project_id, created_at DESC, id DESC)
  WHERE project_id IS NOT NULL;

CREATE INDEX document_links_task_idx
  ON app.document_links(task_id, created_at DESC, id DESC)
  WHERE task_id IS NOT NULL;

CREATE INDEX document_links_progress_update_idx
  ON app.document_links(progress_update_id, created_at DESC, id DESC)
  WHERE progress_update_id IS NOT NULL;

CREATE OR REPLACE FUNCTION app.documents_normalize_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_setting('app.document_metadata_context', true) IS DISTINCT FROM 'owner_metadata_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Documents require trusted metadata functions.';
  END IF;
  NEW.storage_bucket := btrim(NEW.storage_bucket);
  NEW.storage_object_key := btrim(NEW.storage_object_key);
  NEW.original_file_name := btrim(NEW.original_file_name);
  NEW.mime_type := btrim(NEW.mime_type);
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.documents_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_setting('app.document_metadata_context', true) IS DISTINCT FROM 'owner_metadata_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Documents require trusted metadata functions.';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.document_number IS DISTINCT FROM OLD.document_number
     OR NEW.storage_bucket IS DISTINCT FROM OLD.storage_bucket
     OR NEW.storage_object_key IS DISTINCT FROM OLD.storage_object_key
     OR NEW.uploaded_at IS DISTINCT FROM OLD.uploaded_at
     OR NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document identity fields are immutable.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_document_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Documents cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_document_link_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document links cannot be deleted.';
END
$function$;

CREATE TRIGGER documents_normalize_insert
BEFORE INSERT ON app.documents
FOR EACH ROW EXECUTE FUNCTION app.documents_normalize_insert();

CREATE TRIGGER documents_trusted_update
BEFORE UPDATE ON app.documents
FOR EACH ROW EXECUTE FUNCTION app.documents_trusted_update_guard();

CREATE TRIGGER documents_no_delete
BEFORE DELETE ON app.documents
FOR EACH ROW EXECUTE FUNCTION app.prevent_document_delete();

CREATE TRIGGER document_links_no_delete
BEFORE DELETE ON app.document_links
FOR EACH ROW EXECUTE FUNCTION app.prevent_document_link_delete();

ALTER TABLE app.document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document_types FORCE ROW LEVEL SECURITY;
ALTER TABLE app.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.documents FORCE ROW LEVEL SECURITY;
ALTER TABLE app.document_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document_links FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.document_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.document_types FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.documents FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.document_links FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.documents_normalize_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.documents_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_document_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_document_link_delete() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
