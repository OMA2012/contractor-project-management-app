BEGIN;

CREATE TYPE app.payment_match_status AS ENUM (
  'DRAFT',
  'APPROVED',
  'VOIDED'
);

CREATE TABLE app.payment_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_payment_id uuid NOT NULL,
  payment_request_id uuid NOT NULL,
  matched_amount numeric(20,6) NOT NULL,
  currency_code char(3) NOT NULL,
  matched_at timestamptz NOT NULL DEFAULT now(),
  status app.payment_match_status NOT NULL DEFAULT 'DRAFT',
  approved_at timestamptz,
  approved_by uuid,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text,
  matched_by uuid NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT payment_matches_client_payment_fk FOREIGN KEY (client_payment_id) REFERENCES app.client_payments(id) ON DELETE RESTRICT,
  CONSTRAINT payment_matches_payment_request_fk FOREIGN KEY (payment_request_id) REFERENCES app.payment_requests(id) ON DELETE RESTRICT,
  CONSTRAINT payment_matches_currency_fk FOREIGN KEY (currency_code) REFERENCES app.currencies(code) ON DELETE RESTRICT,
  CONSTRAINT payment_matches_approved_by_fk FOREIGN KEY (approved_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT payment_matches_voided_by_fk FOREIGN KEY (voided_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT payment_matches_matched_by_fk FOREIGN KEY (matched_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT payment_matches_pair_uk UNIQUE (client_payment_id, payment_request_id),
  CONSTRAINT payment_matches_amount_ck CHECK (matched_amount > 0),
  CONSTRAINT payment_matches_state_fields_ck CHECK (
    (
      status = 'DRAFT'
      AND approved_at IS NULL
      AND approved_by IS NULL
      AND voided_at IS NULL
      AND voided_by IS NULL
      AND void_reason IS NULL
      AND is_active = true
    )
    OR
    (
      status = 'APPROVED'
      AND approved_at IS NOT NULL
      AND approved_by IS NOT NULL
      AND voided_at IS NULL
      AND voided_by IS NULL
      AND void_reason IS NULL
      AND is_active = true
    )
    OR
    (
      status = 'VOIDED'
      AND voided_at IS NOT NULL
      AND voided_by IS NOT NULL
      AND btrim(coalesce(void_reason, '')) <> ''
      AND is_active = false
    )
  )
);

CREATE INDEX payment_matches_request_approved_active_idx
  ON app.payment_matches(payment_request_id, id)
  WHERE status = 'APPROVED' AND is_active = true;

CREATE INDEX payment_matches_payment_approved_active_idx
  ON app.payment_matches(client_payment_id, id)
  WHERE status = 'APPROVED' AND is_active = true;

DROP INDEX IF EXISTS app.payment_requests_outstanding_due_idx;
CREATE INDEX payment_requests_outstanding_due_idx
  ON app.payment_requests(due_date, id)
  WHERE due_date IS NOT NULL AND status IN ('SENT','VIEWED','PARTIALLY_PAID','OVERDUE');

CREATE OR REPLACE FUNCTION app.payment_matches_trusted_mutation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  mutation_context text := coalesce(current_setting('app.payment_match_context', true), '');
BEGIN
  IF mutation_context <> 'payment_match_owner_mutation' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment matches require trusted functions.';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.client_payment_id IS DISTINCT FROM OLD.client_payment_id AND OLD.status <> 'DRAFT'
       OR NEW.payment_request_id IS DISTINCT FROM OLD.payment_request_id AND OLD.status <> 'DRAFT'
       OR NEW.matched_amount IS DISTINCT FROM OLD.matched_amount AND OLD.status <> 'DRAFT'
       OR NEW.currency_code IS DISTINCT FROM OLD.currency_code AND OLD.status <> 'DRAFT'
       OR NEW.matched_at IS DISTINCT FROM OLD.matched_at
       OR NEW.matched_by IS DISTINCT FROM OLD.matched_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match immutable fields cannot be changed.';
    END IF;

    IF OLD.status = 'DRAFT' AND NEW.status NOT IN ('DRAFT','APPROVED','VOIDED') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment match transition.';
    END IF;
    IF OLD.status = 'APPROVED' AND NEW.status <> 'VOIDED' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment match transition.';
    END IF;
    IF OLD.status = 'VOIDED' AND NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Voided payment matches are immutable.';
    END IF;
    IF OLD.status = 'APPROVED' AND NEW.status = 'VOIDED'
       AND (NEW.approved_at IS DISTINCT FROM OLD.approved_at OR NEW.approved_by IS DISTINCT FROM OLD.approved_by) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment match approval history is immutable.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_payment_match_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment matches cannot be deleted.'; END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_payment_match_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment matches cannot be truncated.'; END
$function$;

CREATE TRIGGER payment_matches_trusted_insert BEFORE INSERT ON app.payment_matches FOR EACH ROW EXECUTE FUNCTION app.payment_matches_trusted_mutation_guard();
CREATE TRIGGER payment_matches_trusted_update BEFORE UPDATE ON app.payment_matches FOR EACH ROW EXECUTE FUNCTION app.payment_matches_trusted_mutation_guard();
CREATE TRIGGER payment_matches_no_delete BEFORE DELETE ON app.payment_matches FOR EACH ROW EXECUTE FUNCTION app.prevent_payment_match_delete();
CREATE TRIGGER payment_matches_no_truncate BEFORE TRUNCATE ON app.payment_matches FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_payment_match_truncate();

ALTER TABLE app.payment_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.payment_matches FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.payment_matches FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.payment_matches_trusted_mutation_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_payment_match_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.prevent_payment_match_truncate() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
