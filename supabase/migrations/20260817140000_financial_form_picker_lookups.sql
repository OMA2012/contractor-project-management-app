BEGIN;

CREATE OR REPLACE FUNCTION app.owner_exchange_rate_picker_list(
  p_actor_auth_subject uuid,
  p_source_currency_code char(3),
  p_destination_currency_code char(3),
  p_rate_date date,
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
  source_code char(3) := upper(p_source_currency_code::text)::char(3);
  destination_code char(3) := upper(p_destination_currency_code::text)::char(3);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  IF source_code IS NULL OR destination_code IS NULL OR p_rate_date IS NULL OR source_code = destination_code THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid exchange rate lookup.';
  END IF;

  RETURN QUERY
  SELECT er.id, er.rate_date, er.base_currency_code, er.quote_currency_code,
         er.rate_value, er.source::text, er.created_at
  FROM app.exchange_rates AS er
  WHERE er.rate_date = p_rate_date
    AND (
      (er.base_currency_code = source_code AND er.quote_currency_code = destination_code)
      OR
      (er.base_currency_code = destination_code AND er.quote_currency_code = source_code)
    )
  ORDER BY
    CASE WHEN er.base_currency_code = source_code AND er.quote_currency_code = destination_code THEN 0 ELSE 1 END,
    er.created_at DESC,
    er.id DESC
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_expense_category_picker_list(
  p_actor_auth_subject uuid,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  code text,
  name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  safe_limit integer := least(greatest(coalesce(p_limit, 100), 1), 100);
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.';
  END IF;

  RETURN QUERY
  SELECT ec.id, ec.code::text, ec.name::text
  FROM app.expense_categories AS ec
  WHERE ec.is_active
  ORDER BY ec.name, ec.code, ec.id
  LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_exchange_rate_picker_list(
  p_verified_owner_auth_subject uuid,
  p_source_currency_code char(3),
  p_destination_currency_code char(3),
  p_rate_date date,
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
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_exchange_rate_picker_list(
    p_verified_owner_auth_subject,
    p_source_currency_code,
    p_destination_currency_code,
    p_rate_date,
    p_limit,
    p_offset
  );
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_expense_category_picker_list(
  p_verified_owner_auth_subject uuid,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  code text,
  name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.owner_expense_category_picker_list(
    p_verified_owner_auth_subject,
    p_limit,
    p_offset
  );
$function$;

REVOKE ALL ON FUNCTION app.owner_exchange_rate_picker_list(uuid, char, char, date, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.owner_expense_category_picker_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.server_owner_exchange_rate_picker_list(uuid, char, char, date, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.server_owner_expense_category_picker_list(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.server_owner_exchange_rate_picker_list(uuid, char, char, date, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.server_owner_expense_category_picker_list(uuid, integer, integer) TO service_role;

COMMIT;
