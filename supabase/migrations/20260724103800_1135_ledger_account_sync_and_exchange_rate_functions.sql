BEGIN;

CREATE OR REPLACE FUNCTION app.ensure_financial_asset_ledger_account(p_financial_account_id uuid)
RETURNS TABLE (ledger_account_id uuid, code text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  financial_row app.financial_accounts%ROWTYPE;
  desired_code text;
  previous_context text := current_setting('app.ledger_account_sync_context', true);
BEGIN
  IF p_financial_account_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account is required.';
  END IF;

  SELECT * INTO financial_row
  FROM app.financial_accounts AS fa
  WHERE fa.id = p_financial_account_id
  FOR UPDATE;

  IF financial_row.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Financial account not found.';
  END IF;

  desired_code := 'ASSET-' || financial_row.account_number;
  PERFORM set_config('app.ledger_account_sync_context', 'financial_account_sync', true);

  INSERT INTO app.ledger_accounts (
    code,
    name,
    account_kind,
    financial_account_id,
    currency_code,
    normal_side,
    is_system,
    is_active
  )
  VALUES (
    desired_code,
    financial_row.name,
    'FINANCIAL_ASSET',
    financial_row.id,
    financial_row.currency_code,
    'DEBIT',
    true,
    financial_row.is_active AND financial_row.archived_at IS NULL
  )
  ON CONFLICT (financial_account_id) DO UPDATE
  SET name = EXCLUDED.name,
      currency_code = EXCLUDED.currency_code,
      is_system = true,
      is_active = EXCLUDED.is_active
  RETURNING app.ledger_accounts.id, app.ledger_accounts.code
  INTO ledger_account_id, code;

  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RETURN NEXT;
EXCEPTION
  WHEN unique_violation THEN
    PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Financial account asset ledger account already exists.';
  WHEN OTHERS THEN
    PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
    RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.sync_financial_account_ledger_account()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.name IS DISTINCT FROM OLD.name
     OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
     OR NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.archived_at IS DISTINCT FROM OLD.archived_at THEN
    PERFORM app.ensure_financial_asset_ledger_account(NEW.id);
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER financial_accounts_asset_ledger_sync
AFTER INSERT OR UPDATE OF name, currency_code, is_active, archived_at ON app.financial_accounts
FOR EACH ROW EXECUTE FUNCTION app.sync_financial_account_ledger_account();

DO $backfill$
DECLARE
  account_row record;
BEGIN
  FOR account_row IN SELECT id FROM app.financial_accounts ORDER BY account_number LOOP
    PERFORM app.ensure_financial_asset_ledger_account(account_row.id);
  END LOOP;
END
$backfill$;

CREATE OR REPLACE FUNCTION app.owner_create_exchange_rate(
  p_actor_auth_subject uuid,
  p_rate_date date,
  p_base_currency_code char(3),
  p_quote_currency_code char(3),
  p_rate_value numeric,
  p_source text DEFAULT 'MANUAL',
  p_source_reference text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  exchange_rate_id uuid,
  rate_date date,
  base_currency_code char(3),
  quote_currency_code char(3),
  rate_value numeric,
  source text,
  created_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  normalized_source text := btrim(coalesce(p_source, 'MANUAL'));
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  IF p_rate_date IS NULL
     OR p_base_currency_code IS NULL
     OR p_quote_currency_code IS NULL
     OR p_rate_value IS NULL
     OR p_rate_value <= 0
     OR normalized_source = ''
     OR p_base_currency_code = p_quote_currency_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid exchange rate.';
  END IF;

  INSERT INTO app.exchange_rates (
    rate_date,
    base_currency_code,
    quote_currency_code,
    rate_value,
    source,
    source_reference,
    entered_by
  )
  VALUES (
    p_rate_date,
    upper(p_base_currency_code::text)::char(3),
    upper(p_quote_currency_code::text)::char(3),
    p_rate_value,
    normalized_source,
    app.normalize_financial_account_optional_text(p_source_reference),
    actor_row.actor_user_id
  )
  RETURNING id, app.exchange_rates.rate_date, app.exchange_rates.base_currency_code,
            app.exchange_rates.quote_currency_code, app.exchange_rates.rate_value,
            app.exchange_rates.source::text, app.exchange_rates.created_at
  INTO exchange_rate_id, rate_date, base_currency_code, quote_currency_code, rate_value, source, created_at;

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'exchange_rate_created',
    'exchange_rate',
    exchange_rate_id,
    NULL,
    'success',
    '{}'::jsonb,
    jsonb_build_object(
      'exchange_rate_id', exchange_rate_id,
      'rate_date', rate_date,
      'base_currency_code', base_currency_code,
      'quote_currency_code', quote_currency_code,
      'rate_value', rate_value,
      'source', source
    ),
    NULL,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    '{}'::jsonb
  );

  RETURN NEXT;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Duplicate exchange rate.';
  WHEN check_violation OR foreign_key_violation THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid exchange rate.';
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_exchange_rate_list(
  p_actor_auth_subject uuid,
  p_base_currency_code char(3) DEFAULT NULL,
  p_quote_currency_code char(3) DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  rate_date date,
  base_currency_code char(3),
  quote_currency_code char(3),
  rate_value numeric,
  source text,
  entered_by uuid,
  created_at timestamptz
)
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
  SELECT er.id, er.rate_date, er.base_currency_code, er.quote_currency_code,
         er.rate_value, er.source::text, er.entered_by, er.created_at
  FROM app.exchange_rates AS er
  WHERE (p_base_currency_code IS NULL OR er.base_currency_code = upper(p_base_currency_code::text)::char(3))
    AND (p_quote_currency_code IS NULL OR er.quote_currency_code = upper(p_quote_currency_code::text)::char(3))
  ORDER BY er.rate_date DESC, er.created_at DESC, er.id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_exchange_rate_detail(
  p_actor_auth_subject uuid,
  p_exchange_rate_id uuid
)
RETURNS TABLE (
  id uuid,
  rate_date date,
  base_currency_code char(3),
  quote_currency_code char(3),
  rate_value numeric,
  source text,
  source_reference text,
  entered_by uuid,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  RETURN QUERY
  SELECT er.id, er.rate_date, er.base_currency_code, er.quote_currency_code,
         er.rate_value, er.source::text, er.source_reference, er.entered_by, er.created_at
  FROM app.exchange_rates AS er
  WHERE er.id = p_exchange_rate_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.convert_amount_with_exchange_rate(
  p_amount numeric,
  p_source_currency_code char(3),
  p_target_currency_code char(3),
  p_rate_base_currency_code char(3),
  p_rate_quote_currency_code char(3),
  p_rate_value numeric
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
STRICT
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_amount < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Amount cannot be negative.';
  END IF;

  IF p_rate_value <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Exchange rate must be greater than zero.';
  END IF;

  IF p_source_currency_code = p_target_currency_code THEN
    RETURN p_amount;
  END IF;

  IF p_source_currency_code = p_rate_base_currency_code
     AND p_target_currency_code = p_rate_quote_currency_code THEN
    RETURN p_amount * p_rate_value;
  END IF;

  IF p_source_currency_code = p_rate_quote_currency_code
     AND p_target_currency_code = p_rate_base_currency_code THEN
    RETURN p_amount / p_rate_value;
  END IF;

  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Exchange rate does not match conversion currencies.';
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_exchange_rate(
  p_verified_owner_auth_subject uuid,
  p_rate_date date,
  p_base_currency_code char(3),
  p_quote_currency_code char(3),
  p_rate_value numeric,
  p_source text DEFAULT 'MANUAL',
  p_source_reference text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (
  exchange_rate_id uuid,
  rate_date date,
  base_currency_code char(3),
  quote_currency_code char(3),
  rate_value numeric,
  source text,
  created_at timestamptz
)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_create_exchange_rate(
    p_verified_owner_auth_subject,
    p_rate_date,
    p_base_currency_code,
    p_quote_currency_code,
    p_rate_value,
    p_source,
    p_source_reference,
    p_request_identifier,
    p_correlation_identifier,
    p_session_identifier,
    p_ip_address
  );
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_exchange_rate_list(
  p_verified_owner_auth_subject uuid,
  p_base_currency_code char(3) DEFAULT NULL,
  p_quote_currency_code char(3) DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  rate_date date,
  base_currency_code char(3),
  quote_currency_code char(3),
  rate_value numeric,
  source text,
  entered_by uuid,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_exchange_rate_list(
    p_verified_owner_auth_subject,
    p_base_currency_code,
    p_quote_currency_code,
    p_limit,
    p_offset
  );
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_exchange_rate_detail(
  p_verified_owner_auth_subject uuid,
  p_exchange_rate_id uuid
)
RETURNS TABLE (
  id uuid,
  rate_date date,
  base_currency_code char(3),
  quote_currency_code char(3),
  rate_value numeric,
  source text,
  source_reference text,
  entered_by uuid,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_exchange_rate_detail(
    p_verified_owner_auth_subject,
    p_exchange_rate_id
  );
$function$;

REVOKE ALL ON FUNCTION app.ensure_financial_asset_ledger_account(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.sync_financial_account_ledger_account() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_create_exchange_rate(uuid, date, char, char, numeric, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_exchange_rate_list(uuid, char, char, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_exchange_rate_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.convert_amount_with_exchange_rate(numeric, char, char, char, char, numeric) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.server_owner_create_exchange_rate(uuid, date, char, char, numeric, text, text, text, text, text, inet) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_exchange_rate_list(uuid, char, char, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_exchange_rate_detail(uuid, uuid) FROM PUBLIC, anon, authenticated;

COMMIT;
