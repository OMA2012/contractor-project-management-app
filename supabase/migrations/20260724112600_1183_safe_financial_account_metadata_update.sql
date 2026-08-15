BEGIN;

CREATE OR REPLACE FUNCTION app.owner_update_financial_account_metadata(
  p_actor_auth_subject uuid,
  p_financial_account_id uuid,
  p_expected_version_number integer,
  p_name text,
  p_account_type app.financial_account_type,
  p_currency_code char(3),
  p_bank_name text DEFAULT NULL,
  p_masked_account_identifier text DEFAULT NULL,
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
  IF p_account_type = 'CASH' AND existing_row.encrypted_account_details IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account encrypted metadata cannot be silently cleared.';
  END IF;

  IF existing_row.name IS DISTINCT FROM normalized_name THEN changed_fields := changed_fields || ARRAY['name']; END IF;
  IF existing_row.account_type IS DISTINCT FROM p_account_type THEN changed_fields := changed_fields || ARRAY['account_type']; END IF;
  IF existing_row.currency_code IS DISTINCT FROM p_currency_code THEN changed_fields := changed_fields || ARRAY['currency_code']; END IF;
  IF existing_row.bank_name IS DISTINCT FROM normalized_bank_name THEN changed_fields := changed_fields || ARRAY['bank_name']; END IF;
  IF existing_row.masked_account_identifier IS DISTINCT FROM normalized_masked_identifier THEN changed_fields := changed_fields || ARRAY['masked_account_identifier']; END IF;
  IF existing_row.notes IS DISTINCT FROM normalized_notes THEN changed_fields := changed_fields || ARRAY['notes']; END IF;

  UPDATE app.financial_accounts AS fa
  SET name = normalized_name,
      account_type = p_account_type,
      currency_code = p_currency_code,
      bank_name = normalized_bank_name,
      masked_account_identifier = normalized_masked_identifier,
      notes = normalized_notes,
      updated_by = actor_row.actor_user_id
  WHERE fa.id = p_financial_account_id
  RETURNING fa.id, fa.account_number, fa.version_number
  INTO financial_account_id, account_number, version_number;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code,
    'financial_account_metadata_updated', 'financial_account', financial_account_id, NULL, 'success',
    jsonb_build_object('version_number', existing_row.version_number),
    jsonb_build_object('version_number', version_number, 'changed_fields', changed_fields),
    NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier,
    jsonb_build_object('encrypted_details_changed', false)
  );

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_update_financial_account_metadata(
  p_verified_owner_auth_subject uuid,
  p_financial_account_id uuid,
  p_expected_version_number integer,
  p_name text,
  p_account_type app.financial_account_type,
  p_currency_code char(3),
  p_bank_name text DEFAULT NULL,
  p_masked_account_identifier text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (financial_account_id uuid, account_number text, version_number integer)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_update_financial_account_metadata(
    p_verified_owner_auth_subject,
    p_financial_account_id,
    p_expected_version_number,
    p_name,
    p_account_type,
    p_currency_code,
    p_bank_name,
    p_masked_account_identifier,
    p_notes,
    p_request_identifier,
    p_correlation_identifier,
    p_session_identifier,
    p_ip_address
  );
$function$;

REVOKE ALL ON FUNCTION app.owner_update_financial_account_metadata(uuid, uuid, integer, text, app.financial_account_type, char, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_owner_update_financial_account_metadata(uuid, uuid, integer, text, app.financial_account_type, char, text, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_owner_update_financial_account_metadata(uuid, uuid, integer, text, app.financial_account_type, char, text, text, text, text, text, text, inet) TO service_role;

COMMIT;
