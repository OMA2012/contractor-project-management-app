BEGIN;

CREATE SEQUENCE app.client_number_seq
  AS integer
  START WITH 1
  INCREMENT BY 1
  MINVALUE 1
  MAXVALUE 999999
  NO CYCLE;

CREATE TYPE app.client_record_status AS ENUM ('ACTIVE', 'INACTIVE');

CREATE TABLE app.clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_number text NOT NULL DEFAULT ('CL-' || lpad(nextval('app.client_number_seq')::text, 6, '0')),
  portal_user_id uuid,
  display_name varchar(160) NOT NULL,
  legal_name varchar(200),
  email citext,
  phone varchar(40),
  address text,
  status app.client_record_status NOT NULL DEFAULT 'ACTIVE',
  internal_notes text,
  is_active boolean NOT NULL DEFAULT true,
  archived_at timestamptz,
  archived_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT clients_client_number_uk UNIQUE (client_number),
  CONSTRAINT clients_portal_user_uk UNIQUE (portal_user_id),
  CONSTRAINT clients_portal_user_fk
    FOREIGN KEY (portal_user_id) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT clients_archived_by_fk
    FOREIGN KEY (archived_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT clients_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT clients_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT clients_client_number_ck CHECK (client_number ~ '^CL-[0-9]{6}$'),
  CONSTRAINT clients_display_name_ck CHECK (btrim(display_name) <> ''),
  CONSTRAINT clients_email_ck CHECK (
    email IS NULL
    OR (
      email::text = lower(btrim(email::text))
      AND position('@' in email::text) > 1
    )
  ),
  CONSTRAINT clients_phone_ck CHECK (
    phone IS NULL OR btrim(phone) ~ '^[+]?[0-9][0-9 ()-]{5,38}$'
  ),
  CONSTRAINT clients_version_ck CHECK (version_number >= 1),
  CONSTRAINT clients_archive_pair_ck CHECK (
    (archived_at IS NULL AND archived_by IS NULL)
    OR
    (archived_at IS NOT NULL AND archived_by IS NOT NULL)
  ),
  CONSTRAINT clients_lifecycle_ck CHECK (
    (
      status = 'ACTIVE'
      AND is_active
      AND archived_at IS NULL
      AND archived_by IS NULL
    )
    OR
    (
      status = 'INACTIVE'
      AND NOT is_active
      AND portal_user_id IS NULL
    )
  )
);

CREATE INDEX clients_active_lookup_idx
  ON app.clients(id, portal_user_id)
  WHERE status = 'ACTIVE' AND is_active AND archived_at IS NULL;

CREATE INDEX clients_display_name_lower_idx
  ON app.clients(lower(display_name));

CREATE INDEX clients_email_non_null_idx
  ON app.clients(email)
  WHERE email IS NOT NULL;

CREATE INDEX clients_owner_list_order_idx
  ON app.clients(created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION app.prevent_client_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client records cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.clients_trusted_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.client_number IS DISTINCT FROM OLD.client_number THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client number is immutable.';
  END IF;

  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER clients_no_delete
BEFORE DELETE ON app.clients
FOR EACH ROW EXECUTE FUNCTION app.prevent_client_delete();

CREATE TRIGGER clients_trusted_update
BEFORE UPDATE ON app.clients
FOR EACH ROW EXECUTE FUNCTION app.clients_trusted_update_guard();

ALTER TABLE app.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.clients FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.clients FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE app.client_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_client_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.clients_trusted_update_guard() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
