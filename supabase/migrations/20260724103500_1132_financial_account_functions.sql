BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_financial_account_optional_text(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT NULLIF(btrim(p_value), '');
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_financial_account(
  p_actor_auth_subject uuid,
  p_name text,
  p_account_type app.financial_account_type,
  p_currency_code char(3),
  p_bank_name text DEFAULT NULL,
  p_masked_account_identifier text DEFAULT NULL,
  p_encrypted_account_details bytea DEFAULT NULL,
  p_is_active boolean DEFAULT true,
  p_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_account_id uuid, account_number text, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  normalized_name text := btrim(coalesce(p_name, ''));
  normalized_bank_name text := app.normalize_financial_account_optional_text(p_bank_name);
  normalized_masked_identifier text := app.normalize_financial_account_optional_text(p_masked_account_identifier);
  normalized_notes text := app.normalize_financial_account_optional_text(p_notes);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF normalized_name = '' OR p_account_type IS NULL OR p_currency_code IS NULL OR p_is_active IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial account.';
  END IF;

  INSERT INTO app.financial_accounts (
    name, account_type, currency_code, bank_name, masked_account_identifier,
    encrypted_account_details, is_active, notes, created_by, updated_by
  )
  VALUES (
    normalized_name, p_account_type, p_currency_code, normalized_bank_name, normalized_masked_identifier,
    p_encrypted_account_details, p_is_active, normalized_notes, actor_row.actor_user_id, actor_row.actor_user_id
  )
  RETURNING id, app.financial_accounts.account_number, app.financial_accounts.version_number
  INTO financial_account_id, account_number, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'financial_account_created', 'financial_account', financial_account_id, NULL, 'success',
    '{}'::jsonb,
    jsonb_build_object(
      'account_number', account_number,
      'account_type', p_account_type::text,
      'currency_code', p_currency_code,
      'is_active', p_is_active,
      'encrypted_details_present', p_encrypted_account_details IS NOT NULL,
      'changed_fields', ARRAY['name','account_type','currency_code','bank_name','masked_account_identifier','encrypted_account_details','is_active','notes']
    ),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_financial_account(
  p_actor_auth_subject uuid,
  p_financial_account_id uuid,
  p_expected_version_number integer,
  p_name text,
  p_account_type app.financial_account_type,
  p_currency_code char(3),
  p_bank_name text DEFAULT NULL,
  p_masked_account_identifier text DEFAULT NULL,
  p_encrypted_account_details bytea DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_account_id uuid, account_number text, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.financial_accounts%ROWTYPE;
  normalized_name text := btrim(coalesce(p_name, ''));
  normalized_bank_name text := app.normalize_financial_account_optional_text(p_bank_name);
  normalized_masked_identifier text := app.normalize_financial_account_optional_text(p_masked_account_identifier);
  normalized_notes text := app.normalize_financial_account_optional_text(p_notes);
  changed_fields text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  IF normalized_name = '' OR p_account_type IS NULL OR p_currency_code IS NULL OR p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial account.';
  END IF;

  SELECT * INTO existing_row FROM app.financial_accounts AS fa WHERE fa.id = p_financial_account_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account cannot be updated.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Financial account version conflict.';
  END IF;

  IF existing_row.name IS DISTINCT FROM normalized_name THEN changed_fields := changed_fields || ARRAY['name']; END IF;
  IF existing_row.account_type IS DISTINCT FROM p_account_type THEN changed_fields := changed_fields || ARRAY['account_type']; END IF;
  IF existing_row.currency_code IS DISTINCT FROM p_currency_code THEN changed_fields := changed_fields || ARRAY['currency_code']; END IF;
  IF existing_row.bank_name IS DISTINCT FROM normalized_bank_name THEN changed_fields := changed_fields || ARRAY['bank_name']; END IF;
  IF existing_row.masked_account_identifier IS DISTINCT FROM normalized_masked_identifier THEN changed_fields := changed_fields || ARRAY['masked_account_identifier']; END IF;
  IF existing_row.encrypted_account_details IS DISTINCT FROM p_encrypted_account_details THEN changed_fields := changed_fields || ARRAY['encrypted_account_details']; END IF;
  IF existing_row.notes IS DISTINCT FROM normalized_notes THEN changed_fields := changed_fields || ARRAY['notes']; END IF;

  UPDATE app.financial_accounts AS fa
  SET name = normalized_name,
      account_type = p_account_type,
      currency_code = p_currency_code,
      bank_name = normalized_bank_name,
      masked_account_identifier = normalized_masked_identifier,
      encrypted_account_details = p_encrypted_account_details,
      notes = normalized_notes,
      updated_by = actor_row.actor_user_id
  WHERE fa.id = p_financial_account_id
  RETURNING fa.id, fa.account_number, fa.version_number
  INTO financial_account_id, account_number, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'financial_account_updated', 'financial_account', financial_account_id, NULL, 'success',
    jsonb_build_object('version_number', existing_row.version_number),
    jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('encrypted_details_changed', 'encrypted_account_details' = ANY(changed_fields))
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_activate_financial_account(
  p_actor_auth_subject uuid,
  p_financial_account_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_account_id uuid, is_active boolean, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.financial_accounts%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial account.'; END IF;
  SELECT * INTO existing_row FROM app.financial_accounts AS fa WHERE fa.id = p_financial_account_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account cannot be activated.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Financial account version conflict.'; END IF;
  IF existing_row.is_active THEN
    financial_account_id := existing_row.id; is_active := existing_row.is_active; version_number := existing_row.version_number; RETURN NEXT; RETURN;
  END IF;
  UPDATE app.financial_accounts AS fa SET is_active = true, updated_by = actor_row.actor_user_id WHERE fa.id = p_financial_account_id RETURNING fa.id, fa.is_active, fa.version_number INTO financial_account_id, is_active, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'financial_account_activated', 'financial_account', financial_account_id, NULL, 'success', jsonb_build_object('is_active', false, 'version_number', existing_row.version_number), jsonb_build_object('is_active', true, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_deactivate_financial_account(
  p_actor_auth_subject uuid,
  p_financial_account_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_account_id uuid, is_active boolean, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.financial_accounts%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial account.'; END IF;
  SELECT * INTO existing_row FROM app.financial_accounts AS fa WHERE fa.id = p_financial_account_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account cannot be deactivated.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Financial account version conflict.'; END IF;
  IF NOT existing_row.is_active THEN
    financial_account_id := existing_row.id; is_active := existing_row.is_active; version_number := existing_row.version_number; RETURN NEXT; RETURN;
  END IF;
  UPDATE app.financial_accounts AS fa SET is_active = false, updated_by = actor_row.actor_user_id WHERE fa.id = p_financial_account_id RETURNING fa.id, fa.is_active, fa.version_number INTO financial_account_id, is_active, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'financial_account_deactivated', 'financial_account', financial_account_id, NULL, 'success', jsonb_build_object('is_active', true, 'version_number', existing_row.version_number), jsonb_build_object('is_active', false, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_archive_financial_account(
  p_actor_auth_subject uuid,
  p_financial_account_id uuid,
  p_expected_version_number integer,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_account_id uuid, is_active boolean, archived_at timestamptz, archived_by uuid, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  existing_row app.financial_accounts%ROWTYPE;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;
  IF p_expected_version_number IS NULL OR p_expected_version_number < 1 THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid financial account.'; END IF;
  SELECT * INTO existing_row FROM app.financial_accounts AS fa WHERE fa.id = p_financial_account_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account cannot be archived.'; END IF;
  IF existing_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Financial account version conflict.'; END IF;
  UPDATE app.financial_accounts AS fa SET is_active = false, archived_at = now(), archived_by = actor_row.actor_user_id, updated_by = actor_row.actor_user_id WHERE fa.id = p_financial_account_id RETURNING fa.id, fa.is_active, fa.archived_at, fa.archived_by, fa.version_number INTO financial_account_id, is_active, archived_at, archived_by, version_number;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'financial_account_archived', 'financial_account', financial_account_id, NULL, 'success', jsonb_build_object('is_active', existing_row.is_active, 'archived', false, 'version_number', existing_row.version_number), jsonb_build_object('is_active', false, 'archived', true, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_financial_account_list(
  p_actor_auth_subject uuid,
  p_include_archived boolean DEFAULT false,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (id uuid, account_number text, name text, account_type text, currency_code char(3), bank_name text, masked_account_identifier text, is_active boolean, archived_at timestamptz, version_number integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;
  RETURN QUERY
  SELECT fa.id, fa.account_number::text, fa.name::text, fa.account_type::text, fa.currency_code, fa.bank_name::text, fa.masked_account_identifier::text, fa.is_active, fa.archived_at, fa.version_number
  FROM app.financial_accounts AS fa
  WHERE coalesce(p_include_archived, false) OR fa.archived_at IS NULL
  ORDER BY fa.created_at DESC, fa.id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_financial_account_detail(
  p_actor_auth_subject uuid,
  p_financial_account_id uuid
)
RETURNS TABLE (id uuid, account_number text, name text, account_type text, currency_code char(3), bank_name text, masked_account_identifier text, is_active boolean, notes text, archived_at timestamptz, archived_by uuid, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT fa.id, fa.account_number::text, fa.name::text, fa.account_type::text, fa.currency_code, fa.bank_name::text, fa.masked_account_identifier::text, fa.is_active, fa.notes, fa.archived_at, fa.archived_by, fa.created_at, fa.created_by, fa.updated_at, fa.updated_by, fa.version_number
  FROM app.financial_accounts AS fa
  WHERE fa.id = p_financial_account_id
    AND EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject));
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_financial_account(p_verified_owner_auth_subject uuid, p_name text, p_account_type app.financial_account_type, p_currency_code char(3), p_bank_name text DEFAULT NULL, p_masked_account_identifier text DEFAULT NULL, p_encrypted_account_details bytea DEFAULT NULL, p_is_active boolean DEFAULT true, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_account_id uuid, account_number text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_financial_account(p_verified_owner_auth_subject,p_name,p_account_type,p_currency_code,p_bank_name,p_masked_account_identifier,p_encrypted_account_details,p_is_active,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;

CREATE OR REPLACE FUNCTION public.server_owner_update_financial_account(p_verified_owner_auth_subject uuid, p_financial_account_id uuid, p_expected_version_number integer, p_name text, p_account_type app.financial_account_type, p_currency_code char(3), p_bank_name text DEFAULT NULL, p_masked_account_identifier text DEFAULT NULL, p_encrypted_account_details bytea DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_account_id uuid, account_number text, version_number integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_financial_account(p_verified_owner_auth_subject,p_financial_account_id,p_expected_version_number,p_name,p_account_type,p_currency_code,p_bank_name,p_masked_account_identifier,p_encrypted_account_details,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;

CREATE OR REPLACE FUNCTION public.server_owner_activate_financial_account(p_verified_owner_auth_subject uuid, p_financial_account_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_account_id uuid, is_active boolean, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_activate_financial_account(p_verified_owner_auth_subject,p_financial_account_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_deactivate_financial_account(p_verified_owner_auth_subject uuid, p_financial_account_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_account_id uuid, is_active boolean, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_deactivate_financial_account(p_verified_owner_auth_subject,p_financial_account_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_archive_financial_account(p_verified_owner_auth_subject uuid, p_financial_account_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_account_id uuid, is_active boolean, archived_at timestamptz, archived_by uuid, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_archive_financial_account(p_verified_owner_auth_subject,p_financial_account_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_financial_account_list(p_verified_owner_auth_subject uuid, p_include_archived boolean DEFAULT false, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (id uuid, account_number text, name text, account_type text, currency_code char(3), bank_name text, masked_account_identifier text, is_active boolean, archived_at timestamptz, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_financial_account_list(p_verified_owner_auth_subject,p_include_archived,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_financial_account_detail(p_verified_owner_auth_subject uuid, p_financial_account_id uuid) RETURNS TABLE (id uuid, account_number text, name text, account_type text, currency_code char(3), bank_name text, masked_account_identifier text, is_active boolean, notes text, archived_at timestamptz, archived_by uuid, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_financial_account_detail(p_verified_owner_auth_subject,p_financial_account_id); $function$;

COMMIT;
