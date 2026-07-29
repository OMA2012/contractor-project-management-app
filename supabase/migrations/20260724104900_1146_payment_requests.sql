BEGIN;

CREATE SEQUENCE app.payment_request_number_seq
  AS integer
  START WITH 1
  INCREMENT BY 1
  MINVALUE 1
  MAXVALUE 999999
  NO CYCLE;

CREATE TYPE app.payment_request_status AS ENUM (
  'DRAFT',
  'SENT',
  'VIEWED',
  'PARTIALLY_PAID',
  'PAID',
  'OVERDUE',
  'CANCELLED'
);

CREATE TABLE app.payment_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_number varchar(60) NOT NULL DEFAULT ('PREQ-' || lpad(nextval('app.payment_request_number_seq')::text, 6, '0')),
  project_id uuid NOT NULL,
  client_id uuid NOT NULL,
  requested_amount numeric(20,6) NOT NULL,
  currency_code char(3) NOT NULL,
  request_date date NOT NULL,
  due_date date,
  status app.payment_request_status NOT NULL DEFAULT 'DRAFT',
  description text NOT NULL,
  sent_at timestamptz,
  viewed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid,
  cancellation_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT payment_requests_request_number_uk UNIQUE (request_number),
  CONSTRAINT payment_requests_project_fk FOREIGN KEY (project_id) REFERENCES app.projects(id) ON DELETE RESTRICT,
  CONSTRAINT payment_requests_client_fk FOREIGN KEY (client_id) REFERENCES app.clients(id) ON DELETE RESTRICT,
  CONSTRAINT payment_requests_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT payment_requests_cancelled_by_fk FOREIGN KEY (cancelled_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT payment_requests_created_by_fk FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT payment_requests_updated_by_fk FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT payment_requests_request_number_ck CHECK (request_number ~ '^PREQ-[0-9]{6}$'),
  CONSTRAINT payment_requests_amount_ck CHECK (requested_amount > 0),
  CONSTRAINT payment_requests_date_order_ck CHECK (due_date IS NULL OR due_date >= request_date),
  CONSTRAINT payment_requests_description_ck CHECK (btrim(description) <> ''),
  CONSTRAINT payment_requests_version_ck CHECK (version_number >= 1),
  CONSTRAINT payment_requests_lifecycle_fields_ck CHECK (
    (
      status = 'DRAFT'
      AND sent_at IS NULL
      AND viewed_at IS NULL
      AND cancelled_at IS NULL
      AND cancelled_by IS NULL
      AND cancellation_reason IS NULL
    )
    OR
    (
      status IN ('SENT','VIEWED','PARTIALLY_PAID','PAID','OVERDUE')
      AND sent_at IS NOT NULL
      AND cancelled_at IS NULL
      AND cancelled_by IS NULL
      AND cancellation_reason IS NULL
    )
    OR
    (
      status = 'CANCELLED'
      AND cancelled_at IS NOT NULL
      AND cancelled_by IS NOT NULL
      AND btrim(coalesce(cancellation_reason, '')) <> ''
    )
  )
);

CREATE INDEX payment_requests_project_status_due_idx
  ON app.payment_requests(project_id, status, due_date, id);

CREATE INDEX payment_requests_client_status_due_idx
  ON app.payment_requests(client_id, status, due_date, id);

CREATE INDEX payment_requests_outstanding_due_idx
  ON app.payment_requests(due_date, id)
  WHERE due_date IS NOT NULL AND status IN ('SENT','VIEWED','OVERDUE');

CREATE OR REPLACE FUNCTION app.payment_requests_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  project_row app.projects%ROWTYPE;
  client_row app.clients%ROWTYPE;
  mutation_context text := coalesce(current_setting('app.payment_request_context', true), '');
BEGIN
  IF mutation_context NOT IN ('payment_request_owner_mutation','payment_request_client_view','payment_request_overdue_refresh') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment requests require trusted functions.';
  END IF;

  SELECT * INTO project_row FROM app.projects WHERE id = NEW.project_id;
  SELECT * INTO client_row FROM app.clients WHERE id = NEW.client_id;

  IF project_row.id IS NULL
     OR client_row.id IS NULL
     OR project_row.client_id IS DISTINCT FROM NEW.client_id
     OR project_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request.';
  END IF;

  IF NEW.requested_amount <= 0
     OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = NEW.currency_code) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request.';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.request_number IS DISTINCT FROM OLD.request_number
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment request identity fields are immutable.';
    END IF;

    IF OLD.status = 'CANCELLED' AND NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Cancelled payment requests are immutable.';
    END IF;

    IF mutation_context = 'payment_request_client_view' THEN
      IF OLD.viewed_at IS NOT NULL THEN
        IF NEW IS DISTINCT FROM OLD THEN
          RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment request view is idempotent.';
        END IF;
      ELSIF NEW.viewed_at IS NULL
         OR NEW.project_id IS DISTINCT FROM OLD.project_id
         OR NEW.client_id IS DISTINCT FROM OLD.client_id
         OR NEW.requested_amount IS DISTINCT FROM OLD.requested_amount
         OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
         OR NEW.request_date IS DISTINCT FROM OLD.request_date
         OR NEW.due_date IS DISTINCT FROM OLD.due_date
         OR NEW.description IS DISTINCT FROM OLD.description
         OR NEW.sent_at IS DISTINCT FROM OLD.sent_at
         OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
         OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
         OR NEW.cancellation_reason IS DISTINCT FROM OLD.cancellation_reason
         OR NEW.created_at IS DISTINCT FROM OLD.created_at
         OR NEW.created_by IS DISTINCT FROM OLD.created_by
         OR NOT (
              (OLD.status = 'SENT' AND NEW.status IN ('SENT','VIEWED'))
              OR
              (OLD.status IN ('VIEWED','OVERDUE','CANCELLED','PARTIALLY_PAID','PAID') AND NEW.status = OLD.status)
            ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client view can only acknowledge the first view.';
      END IF;
    ELSIF mutation_context = 'payment_request_overdue_refresh' THEN
      IF OLD.status NOT IN ('SENT','VIEWED')
         OR NEW.status <> 'OVERDUE'
         OR NEW.viewed_at IS DISTINCT FROM OLD.viewed_at
         OR NEW.project_id IS DISTINCT FROM OLD.project_id
         OR NEW.client_id IS DISTINCT FROM OLD.client_id
         OR NEW.requested_amount IS DISTINCT FROM OLD.requested_amount
         OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
         OR NEW.request_date IS DISTINCT FROM OLD.request_date
         OR NEW.due_date IS DISTINCT FROM OLD.due_date
         OR NEW.description IS DISTINCT FROM OLD.description
         OR NEW.sent_at IS DISTINCT FROM OLD.sent_at
         OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
         OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
         OR NEW.cancellation_reason IS DISTINCT FROM OLD.cancellation_reason THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Overdue refresh can only mark outstanding requests overdue.';
      END IF;
    ELSIF OLD.status <> 'DRAFT' THEN
      IF NEW.project_id IS DISTINCT FROM OLD.project_id
         OR NEW.client_id IS DISTINCT FROM OLD.client_id
         OR NEW.requested_amount IS DISTINCT FROM OLD.requested_amount
         OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
         OR NEW.request_date IS DISTINCT FROM OLD.request_date
         OR NEW.due_date IS DISTINCT FROM OLD.due_date
         OR NEW.description IS DISTINCT FROM OLD.description THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Sent payment request facts are immutable.';
      END IF;
    END IF;

    IF OLD.status = 'DRAFT' AND NEW.status NOT IN ('DRAFT','SENT','CANCELLED') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
    END IF;
    IF OLD.status = 'SENT' AND NEW.status NOT IN ('SENT','VIEWED','OVERDUE','CANCELLED') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
    END IF;
    IF OLD.status = 'VIEWED' AND NEW.status NOT IN ('VIEWED','OVERDUE','CANCELLED') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
    END IF;
    IF OLD.status = 'OVERDUE' AND NEW.status NOT IN ('OVERDUE','CANCELLED') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request transition.';
    END IF;
    IF OLD.status IN ('PARTIALLY_PAID','PAID') AND NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment matching statuses require matching functions.';
    END IF;

    NEW.updated_at := now();
    NEW.version_number := OLD.version_number + 1;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_payment_request_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment requests cannot be deleted.'; END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_payment_request_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment requests cannot be truncated.'; END
$function$;

CREATE TRIGGER payment_requests_trusted_insert BEFORE INSERT ON app.payment_requests FOR EACH ROW EXECUTE FUNCTION app.payment_requests_trusted_mutation_guard();
CREATE TRIGGER payment_requests_trusted_update BEFORE UPDATE ON app.payment_requests FOR EACH ROW EXECUTE FUNCTION app.payment_requests_trusted_mutation_guard();
CREATE TRIGGER payment_requests_no_delete BEFORE DELETE ON app.payment_requests FOR EACH ROW EXECUTE FUNCTION app.prevent_payment_request_delete();
CREATE TRIGGER payment_requests_no_truncate BEFORE TRUNCATE ON app.payment_requests FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_payment_request_truncate();

ALTER TABLE app.payment_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.payment_requests FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.payment_request_number_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON app.payment_requests FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.payment_requests_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_payment_request_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_payment_request_truncate() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
