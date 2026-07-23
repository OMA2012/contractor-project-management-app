BEGIN;

CREATE TABLE app.activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  actor_user_id uuid,
  actor_auth_subject uuid,
  effective_role_code varchar(40),
  action varchar(120) NOT NULL,
  entity_type varchar(80) NOT NULL,
  entity_id uuid,
  project_id uuid,
  outcome varchar(40) NOT NULL,
  previous_values jsonb NOT NULL DEFAULT '{}'::jsonb,
  new_values jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason text,
  ip_address inet,
  session_identifier text,
  request_identifier text,
  correlation_identifier text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT activity_logs_actor_user_fk
    FOREIGN KEY (actor_user_id) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT activity_logs_effective_role_fk
    FOREIGN KEY (effective_role_code) REFERENCES app.roles(code) ON DELETE RESTRICT,
  CONSTRAINT activity_logs_action_ck CHECK (btrim(action) <> ''),
  CONSTRAINT activity_logs_entity_type_ck CHECK (btrim(entity_type) <> ''),
  CONSTRAINT activity_logs_outcome_ck CHECK (btrim(outcome) <> ''),
  CONSTRAINT activity_logs_previous_object_ck CHECK (jsonb_typeof(previous_values) = 'object'),
  CONSTRAINT activity_logs_new_object_ck CHECK (jsonb_typeof(new_values) = 'object'),
  CONSTRAINT activity_logs_metadata_object_ck CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX activity_logs_occurred_at_idx
  ON app.activity_logs(occurred_at, id);

CREATE INDEX activity_logs_actor_user_idx
  ON app.activity_logs(actor_user_id, occurred_at);

CREATE INDEX activity_logs_entity_idx
  ON app.activity_logs(entity_type, entity_id, occurred_at);

CREATE OR REPLACE FUNCTION app.mask_audit_json(p_value jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
DECLARE
  item jsonb;
  key_text text;
  normalized_key text;
  masked jsonb := '{}'::jsonb;
BEGIN
  IF p_value IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  IF jsonb_typeof(p_value) = 'object' THEN
    FOR key_text, item IN
      SELECT entries.key, entries.value
      FROM jsonb_each(p_value) AS entries(key, value)
    LOOP
      normalized_key := lower(regexp_replace(key_text, '[^a-z0-9]+', '-', 'g'));
      IF normalized_key = 'password'
         OR normalized_key LIKE '%-password'
         OR normalized_key LIKE 'password-%'
         OR normalized_key LIKE '%-password-%'
         OR normalized_key LIKE '%token%'
         OR normalized_key LIKE '%secret%'
         OR normalized_key = 'key'
         OR normalized_key LIKE '%-key'
         OR normalized_key LIKE 'key-%'
         OR normalized_key LIKE '%-key-%'
         OR normalized_key LIKE '%signed-url%'
         OR normalized_key LIKE '%service-role%'
         OR normalized_key LIKE '%access-token%'
         OR normalized_key LIKE '%refresh-token%'
         OR normalized_key LIKE '%full-account-number%'
         OR normalized_key LIKE '%private-note%'
         OR normalized_key LIKE '%password-reset-link%' THEN
        CONTINUE;
      END IF;

      masked := masked || jsonb_build_object(key_text, app.mask_audit_json(item));
    END LOOP;
    RETURN masked;
  END IF;

  IF jsonb_typeof(p_value) = 'array' THEN
    SELECT coalesce(jsonb_agg(app.mask_audit_json(elements.value)), '[]'::jsonb)
    INTO masked
    FROM jsonb_array_elements(p_value) AS elements(value);
    RETURN masked;
  END IF;

  RETURN p_value;
END
$function$;

CREATE OR REPLACE FUNCTION app.write_activity_log(
  p_actor_user_id uuid,
  p_actor_auth_subject uuid,
  p_effective_role_code varchar(40),
  p_action varchar(120),
  p_entity_type varchar(80),
  p_entity_id uuid,
  p_project_id uuid,
  p_outcome varchar(40),
  p_previous_values jsonb,
  p_new_values jsonb,
  p_reason text,
  p_ip_address inet,
  p_session_identifier text,
  p_request_identifier text,
  p_correlation_identifier text,
  p_metadata jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  inserted_id uuid;
BEGIN
  INSERT INTO app.activity_logs (
    actor_user_id,
    actor_auth_subject,
    effective_role_code,
    action,
    entity_type,
    entity_id,
    project_id,
    outcome,
    previous_values,
    new_values,
    reason,
    ip_address,
    session_identifier,
    request_identifier,
    correlation_identifier,
    metadata
  )
  VALUES (
    p_actor_user_id,
    p_actor_auth_subject,
    p_effective_role_code,
    p_action,
    p_entity_type,
    p_entity_id,
    p_project_id,
    p_outcome,
    app.mask_audit_json(coalesce(p_previous_values, '{}'::jsonb)),
    app.mask_audit_json(coalesce(p_new_values, '{}'::jsonb)),
    p_reason,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    app.mask_audit_json(coalesce(p_metadata, '{}'::jsonb))
  )
  RETURNING id INTO inserted_id;

  RETURN inserted_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_activity_log_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'activity_logs rows are append-only.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_activity_log_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'activity_logs rows cannot be deleted.';
END
$function$;

CREATE OR REPLACE FUNCTION app.prevent_activity_log_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'activity_logs cannot be truncated.';
END
$function$;

CREATE TRIGGER activity_logs_no_update
BEFORE UPDATE ON app.activity_logs
FOR EACH ROW EXECUTE FUNCTION app.prevent_activity_log_update();

CREATE TRIGGER activity_logs_no_delete
BEFORE DELETE ON app.activity_logs
FOR EACH ROW EXECUTE FUNCTION app.prevent_activity_log_delete();

CREATE TRIGGER activity_logs_no_truncate
BEFORE TRUNCATE ON app.activity_logs
FOR EACH STATEMENT EXECUTE FUNCTION app.prevent_activity_log_truncate();

ALTER TABLE app.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.activity_logs FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.activity_logs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.mask_audit_json(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.mask_audit_json(jsonb) FROM anon, authenticated;
REVOKE ALL ON FUNCTION app.write_activity_log(uuid, uuid, varchar, varchar, varchar, uuid, uuid, varchar, jsonb, jsonb, text, inet, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.write_activity_log(uuid, uuid, varchar, varchar, varchar, uuid, uuid, varchar, jsonb, jsonb, text, inet, text, text, text, jsonb) FROM anon, authenticated;
REVOKE ALL ON FUNCTION app.prevent_activity_log_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.prevent_activity_log_update() FROM anon, authenticated;
REVOKE ALL ON FUNCTION app.prevent_activity_log_delete() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.prevent_activity_log_delete() FROM anon, authenticated;
REVOKE ALL ON FUNCTION app.prevent_activity_log_truncate() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.prevent_activity_log_truncate() FROM anon, authenticated;

COMMIT;
