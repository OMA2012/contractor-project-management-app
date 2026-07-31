BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_currency_exchange_reference(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT upper(NULLIF(btrim(p_value), ''));
$function$;

CREATE OR REPLACE FUNCTION app.currency_exchange_duplicate_fingerprint(
  p_source_account_id uuid,
  p_destination_account_id uuid,
  p_exchange_date date,
  p_source_currency_code char(3),
  p_destination_currency_code char(3),
  p_source_amount numeric,
  p_destination_amount numeric,
  p_rate_base_currency_code char(3),
  p_rate_quote_currency_code char(3),
  p_rate_value numeric,
  p_fee_amount numeric,
  p_fee_currency_code char(3),
  p_fee_account_id uuid,
  p_reference text,
  p_event_number text
)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT 'CURRENCY_EXCHANGE|source=' || p_source_account_id::text
    || '|destination=' || p_destination_account_id::text
    || '|date=' || p_exchange_date::text
    || '|source_currency=' || p_source_currency_code::text
    || '|destination_currency=' || p_destination_currency_code::text
    || '|source_amount=' || p_source_amount::numeric(20,6)::text
    || '|destination_amount=' || p_destination_amount::numeric(20,6)::text
    || '|rate_base=' || p_rate_base_currency_code::text
    || '|rate_quote=' || p_rate_quote_currency_code::text
    || '|rate_value=' || p_rate_value::numeric(30,12)::text
    || '|fee_amount=' || coalesce(p_fee_amount, 0)::numeric(20,6)::text
    || '|fee_currency=' || coalesce(p_fee_currency_code::text, 'NULL')
    || '|fee_account=' || coalesce(p_fee_account_id::text, 'NULL')
    || CASE WHEN app.normalize_currency_exchange_reference(p_reference) IS NULL
       THEN '|event_number=' || p_event_number
       ELSE '|reference=' || app.normalize_currency_exchange_reference(p_reference)
       END;
$function$;

CREATE OR REPLACE FUNCTION app.round_half_up_positive(p_amount numeric, p_decimal_digits integer)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE STRICT SECURITY DEFINER SET search_path = '' AS $function$
DECLARE scale_factor numeric := power(10::numeric, p_decimal_digits);
BEGIN
  IF p_amount < 0 OR p_decimal_digits < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid rounded amount.';
  END IF;
  RETURN floor((p_amount * scale_factor) + 0.5) / scale_factor;
END $function$;

CREATE OR REPLACE FUNCTION app.ensure_currency_exchange_clearing_ledger_account(p_currency_code char(3))
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE ledger_account_id uuid; previous_context text := current_setting('app.ledger_account_sync_context', true);
BEGIN
  IF p_currency_code IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = p_currency_code AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Valid FX clearing currency is required.';
  END IF;
  PERFORM set_config('app.ledger_account_sync_context', 'financial_account_sync', true);
  INSERT INTO app.ledger_accounts (code, name, account_kind, financial_account_id, currency_code, normal_side, is_system, is_active)
  VALUES ('CTRL-FX-CLEARING-' || p_currency_code::text, 'FX Clearing - ' || p_currency_code::text, 'CONTROL', NULL, p_currency_code, 'DEBIT', true, true)
  ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, account_kind='CONTROL', financial_account_id=NULL, currency_code=EXCLUDED.currency_code, normal_side='DEBIT', is_system=true, is_active=true
  RETURNING id INTO ledger_account_id;
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RETURN ledger_account_id;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.ensure_currency_exchange_fee_ledger_account(p_currency_code char(3))
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE ledger_account_id uuid; previous_context text := current_setting('app.ledger_account_sync_context', true);
BEGIN
  IF p_currency_code IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = p_currency_code AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Valid FX fee currency is required.';
  END IF;
  PERFORM set_config('app.ledger_account_sync_context', 'financial_account_sync', true);
  INSERT INTO app.ledger_accounts (code, name, account_kind, financial_account_id, currency_code, normal_side, is_system, is_active)
  VALUES ('CTRL-FX-FEE-' || p_currency_code::text, 'FX Fee - ' || p_currency_code::text, 'CONTROL', NULL, p_currency_code, 'DEBIT', true, true)
  ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, account_kind='CONTROL', financial_account_id=NULL, currency_code=EXCLUDED.currency_code, normal_side='DEBIT', is_system=true, is_active=true
  RETURNING id INTO ledger_account_id;
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RETURN ledger_account_id;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.currency_exchange_calculate_destination(
  p_source_amount numeric,
  p_source_currency_code char(3),
  p_destination_currency_code char(3),
  p_rate_base_currency_code char(3),
  p_rate_quote_currency_code char(3),
  p_rate_value numeric
)
RETURNS TABLE (destination_amount numeric, rounding_result numeric)
LANGUAGE plpgsql STABLE STRICT SECURITY DEFINER SET search_path = '' AS $function$
DECLARE exact_destination numeric; destination_digits integer; smallest_unit numeric; rounded_destination numeric;
BEGIN
  SELECT decimal_digits INTO destination_digits FROM app.currencies WHERE code = p_destination_currency_code;
  IF destination_digits IS NULL OR p_source_amount <= 0 OR p_rate_value <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid currency exchange.';
  END IF;
  exact_destination := app.convert_amount_with_exchange_rate(p_source_amount, p_source_currency_code, p_destination_currency_code, p_rate_base_currency_code, p_rate_quote_currency_code, p_rate_value);
  rounded_destination := app.round_half_up_positive(exact_destination, destination_digits);
  smallest_unit := power(10::numeric, -destination_digits);
  destination_amount := rounded_destination::numeric(20,6);
  rounding_result := (rounded_destination - exact_destination)::numeric(20,6);
  IF abs(rounding_result) > (0.5 * smallest_unit) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Currency exchange rounding exceeds tolerance.';
  END IF;
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.currency_exchange_reporting_snapshot(
  p_amount numeric,
  p_source_currency_code char(3),
  p_reporting_currency_code char(3),
  p_transaction_date date
)
RETURNS TABLE (reporting_amount numeric, exchange_rate_id uuid, rate_base_currency_code char(3), rate_quote_currency_code char(3), rate_value numeric, rate_source varchar)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE snap record;
BEGIN
  SELECT s.reporting_amount, s.exchange_rate_id, s.rate_base_currency_code, s.rate_quote_currency_code, s.rate_value, s.rate_source
  INTO reporting_amount, exchange_rate_id, rate_base_currency_code, rate_quote_currency_code, rate_value, rate_source
  FROM app.financial_transaction_reporting_snapshot(p_amount, p_source_currency_code, p_reporting_currency_code, p_transaction_date) AS s;
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.currency_exchange_validate_accounts(
  p_source_account_id uuid,
  p_destination_account_id uuid,
  p_fee_account_id uuid,
  p_fee_amount numeric,
  p_require_asset_ledgers boolean DEFAULT false
)
RETURNS TABLE (
  source_account_id uuid,
  destination_account_id uuid,
  fee_account_id uuid,
  source_currency_code char(3),
  destination_currency_code char(3),
  fee_currency_code char(3),
  source_ledger_account_id uuid,
  destination_ledger_account_id uuid,
  fee_ledger_account_id uuid
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE source_row app.financial_accounts%ROWTYPE; destination_row app.financial_accounts%ROWTYPE; fee_row app.financial_accounts%ROWTYPE; source_ledger app.ledger_accounts%ROWTYPE; destination_ledger app.ledger_accounts%ROWTYPE; fee_ledger app.ledger_accounts%ROWTYPE; effective_fee_account_id uuid;
BEGIN
  effective_fee_account_id := CASE WHEN coalesce(p_fee_amount,0) > 0 THEN coalesce(p_fee_account_id, p_source_account_id) ELSE NULL END;
  SELECT * INTO source_row FROM app.financial_accounts WHERE id = p_source_account_id FOR UPDATE;
  SELECT * INTO destination_row FROM app.financial_accounts WHERE id = p_destination_account_id FOR UPDATE;
  IF effective_fee_account_id IS NOT NULL THEN SELECT * INTO fee_row FROM app.financial_accounts WHERE id = effective_fee_account_id FOR UPDATE; END IF;
  SELECT * INTO source_ledger FROM app.ledger_accounts WHERE financial_account_id = source_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE;
  SELECT * INTO destination_ledger FROM app.ledger_accounts WHERE financial_account_id = destination_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE;
  IF effective_fee_account_id IS NOT NULL THEN SELECT * INTO fee_ledger FROM app.ledger_accounts WHERE financial_account_id = fee_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE; END IF;
  IF source_row.id IS NULL OR destination_row.id IS NULL OR source_row.id = destination_row.id OR source_row.currency_code = destination_row.currency_code THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange.';
  END IF;
  IF NOT source_row.is_active OR source_row.archived_at IS NOT NULL OR NOT destination_row.is_active OR destination_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange.';
  END IF;
  IF p_require_asset_ledgers AND (source_ledger.id IS NULL OR NOT source_ledger.is_active OR destination_ledger.id IS NULL OR NOT destination_ledger.is_active) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange.';
  END IF;
  IF effective_fee_account_id IS NOT NULL THEN
    IF fee_row.id IS NULL OR NOT fee_row.is_active OR fee_row.archived_at IS NOT NULL OR fee_row.currency_code NOT IN (source_row.currency_code, destination_row.currency_code) THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange fee.';
    END IF;
    IF p_require_asset_ledgers AND (fee_ledger.id IS NULL OR NOT fee_ledger.is_active) THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange fee.';
    END IF;
  END IF;
  source_account_id := source_row.id; destination_account_id := destination_row.id; fee_account_id := effective_fee_account_id;
  source_currency_code := source_row.currency_code; destination_currency_code := destination_row.currency_code; fee_currency_code := fee_row.currency_code;
  source_ledger_account_id := source_ledger.id; destination_ledger_account_id := destination_ledger.id; fee_ledger_account_id := fee_ledger.id;
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_create_currency_exchange(p_actor_auth_subject uuid, p_source_account_id uuid, p_destination_account_id uuid, p_source_amount numeric, p_exchange_rate_id uuid, p_fee_amount numeric DEFAULT 0, p_fee_account_id uuid DEFAULT NULL, p_exchange_date date DEFAULT NULL, p_project_id uuid DEFAULT NULL, p_reference text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, destination_amount numeric, rounding_result numeric, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; account_pair record; rate_row app.exchange_rates%ROWTYPE; calc record; project_row app.projects%ROWTYPE; contractor_row app.contractor_profiles%ROWTYPE; reporting_currency char(3); normalized_reference text := app.normalize_currency_exchange_reference(p_reference); fp text; generated_event_number text := 'FE-' || lpad(nextval('app.financial_event_number_seq')::text, 6, '0'); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  IF p_source_amount IS NULL OR p_source_amount <= 0 OR p_exchange_rate_id IS NULL OR p_exchange_date IS NULL OR coalesce(p_fee_amount,0) < 0 THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange.'; END IF;
  SELECT * INTO account_pair FROM app.currency_exchange_validate_accounts(p_source_account_id,p_destination_account_id,p_fee_account_id,coalesce(p_fee_amount,0),false);
  SELECT * INTO rate_row FROM app.exchange_rates WHERE id=p_exchange_rate_id AND rate_date=p_exchange_date FOR UPDATE;
  IF rate_row.id IS NULL OR rate_row.rate_value <= 0 OR NOT ((rate_row.base_currency_code=account_pair.source_currency_code AND rate_row.quote_currency_code=account_pair.destination_currency_code) OR (rate_row.quote_currency_code=account_pair.source_currency_code AND rate_row.base_currency_code=account_pair.destination_currency_code)) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange rate.'; END IF;
  SELECT * INTO calc FROM app.currency_exchange_calculate_destination(p_source_amount,account_pair.source_currency_code,account_pair.destination_currency_code,rate_row.base_currency_code,rate_row.quote_currency_code,rate_row.rate_value);
  IF p_project_id IS NOT NULL THEN SELECT * INTO project_row FROM app.projects WHERE id=p_project_id FOR UPDATE; IF project_row.id IS NULL OR project_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange Project.'; END IF; reporting_currency := project_row.reporting_currency_code; ELSE SELECT * INTO contractor_row FROM app.contractor_profiles WHERE singleton_key=1; reporting_currency := contractor_row.default_reporting_currency_code; END IF;
  IF reporting_currency IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=reporting_currency AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Valid reporting currency is required.'; END IF;
  fp := app.currency_exchange_duplicate_fingerprint(account_pair.source_account_id,account_pair.destination_account_id,p_exchange_date,account_pair.source_currency_code,account_pair.destination_currency_code,p_source_amount,calc.destination_amount,rate_row.base_currency_code,rate_row.quote_currency_code,rate_row.rate_value,coalesce(p_fee_amount,0),account_pair.fee_currency_code,account_pair.fee_account_id,normalized_reference,generated_event_number);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  INSERT INTO app.financial_events (event_number, event_type, project_id, client_id, event_date, status, description, duplicate_fingerprint, created_by, updated_by)
  VALUES (generated_event_number, 'CURRENCY_EXCHANGE', project_row.id, project_row.client_id, p_exchange_date, 'DRAFT', normalized_reference, fp, actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id, app.financial_events.event_number, app.financial_events.version_number INTO financial_event_id, event_number, version_number;
  INSERT INTO app.financial_transactions (financial_event_id, transaction_date, status, reporting_currency_code, description, created_by) VALUES (financial_event_id,p_exchange_date,'DRAFT',reporting_currency,normalized_reference,actor_row.actor_user_id) RETURNING id, app.financial_transactions.transaction_number INTO financial_transaction_id, transaction_number;
  INSERT INTO app.currency_exchanges (financial_event_id, source_account_id, destination_account_id, source_amount, source_currency_code, destination_amount, destination_currency_code, exchange_rate_id, rate_base_currency_code, rate_quote_currency_code, rate_value, rate_source, fee_amount, fee_currency_code, fee_account_id, exchange_date, rounding_result, reference)
  VALUES (financial_event_id, account_pair.source_account_id, account_pair.destination_account_id, p_source_amount::numeric(20,6), account_pair.source_currency_code, calc.destination_amount, account_pair.destination_currency_code, rate_row.id, rate_row.base_currency_code, rate_row.quote_currency_code, rate_row.rate_value, rate_row.source, coalesce(p_fee_amount,0)::numeric(20,6), account_pair.fee_currency_code, account_pair.fee_account_id, p_exchange_date, calc.rounding_result, normalized_reference::varchar(120)) RETURNING id INTO currency_exchange_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id,actor_row.actor_auth_subject,actor_row.effective_role_code,'currency_exchange_created','financial_event',financial_event_id,project_row.id,'success','{}'::jsonb,jsonb_build_object('currency_exchange_id',currency_exchange_id,'event_number',event_number,'transaction_number',transaction_number,'source_account_id',account_pair.source_account_id,'destination_account_id',account_pair.destination_account_id,'source_currency_code',account_pair.source_currency_code,'destination_currency_code',account_pair.destination_currency_code,'status','DRAFT','version_number',version_number),NULL,p_ip_address,p_session_identifier,p_request_identifier,p_correlation_identifier,'{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate currency exchange.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_update_currency_exchange(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_source_account_id uuid, p_destination_account_id uuid, p_source_amount numeric, p_exchange_rate_id uuid, p_fee_amount numeric DEFAULT 0, p_fee_account_id uuid DEFAULT NULL, p_exchange_date date DEFAULT NULL, p_project_id uuid DEFAULT NULL, p_reference text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, financial_transaction_id uuid, destination_amount numeric, rounding_result numeric, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; exchange_row app.currency_exchanges%ROWTYPE; account_pair record; rate_row app.exchange_rates%ROWTYPE; calc record; project_row app.projects%ROWTYPE; contractor_row app.contractor_profiles%ROWTYPE; reporting_currency char(3); normalized_reference text := app.normalize_currency_exchange_reference(p_reference); fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE; SELECT * INTO transaction_row FROM app.financial_transactions AS ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE; SELECT * INTO exchange_row FROM app.currency_exchanges AS ce WHERE ce.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR exchange_row.id IS NULL OR event_row.event_type <> 'CURRENCY_EXCHANGE' OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Currency exchange cannot be updated.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Currency exchange version conflict.'; END IF;
  IF p_source_amount IS NULL OR p_source_amount <= 0 OR p_exchange_rate_id IS NULL OR p_exchange_date IS NULL OR coalesce(p_fee_amount,0) < 0 THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange.'; END IF;
  SELECT * INTO account_pair FROM app.currency_exchange_validate_accounts(p_source_account_id,p_destination_account_id,p_fee_account_id,coalesce(p_fee_amount,0),false);
  SELECT * INTO rate_row FROM app.exchange_rates WHERE id=p_exchange_rate_id AND rate_date=p_exchange_date FOR UPDATE;
  IF rate_row.id IS NULL OR rate_row.rate_value <= 0 OR NOT ((rate_row.base_currency_code=account_pair.source_currency_code AND rate_row.quote_currency_code=account_pair.destination_currency_code) OR (rate_row.quote_currency_code=account_pair.source_currency_code AND rate_row.base_currency_code=account_pair.destination_currency_code)) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange rate.'; END IF;
  SELECT * INTO calc FROM app.currency_exchange_calculate_destination(p_source_amount,account_pair.source_currency_code,account_pair.destination_currency_code,rate_row.base_currency_code,rate_row.quote_currency_code,rate_row.rate_value);
  IF p_project_id IS NOT NULL THEN SELECT * INTO project_row FROM app.projects WHERE id=p_project_id FOR UPDATE; IF project_row.id IS NULL OR project_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange Project.'; END IF; reporting_currency := project_row.reporting_currency_code; ELSE SELECT * INTO contractor_row FROM app.contractor_profiles WHERE singleton_key=1; reporting_currency := contractor_row.default_reporting_currency_code; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  fp := app.currency_exchange_duplicate_fingerprint(account_pair.source_account_id,account_pair.destination_account_id,p_exchange_date,account_pair.source_currency_code,account_pair.destination_currency_code,p_source_amount,calc.destination_amount,rate_row.base_currency_code,rate_row.quote_currency_code,rate_row.rate_value,coalesce(p_fee_amount,0),account_pair.fee_currency_code,account_pair.fee_account_id,normalized_reference,event_row.event_number::text);
  UPDATE app.financial_events SET project_id=project_row.id, client_id=project_row.client_id, event_date=p_exchange_date, description=normalized_reference, duplicate_fingerprint=fp, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.version_number INTO financial_event_id, version_number;
  IF transaction_row.reporting_currency_code IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=transaction_row.reporting_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Valid reporting currency is required.'; END IF;
  UPDATE app.financial_transactions SET transaction_date=p_exchange_date, description=normalized_reference WHERE id=transaction_row.id RETURNING id INTO financial_transaction_id;
  UPDATE app.currency_exchanges SET source_account_id=account_pair.source_account_id, destination_account_id=account_pair.destination_account_id, source_amount=p_source_amount::numeric(20,6), source_currency_code=account_pair.source_currency_code, destination_amount=calc.destination_amount, destination_currency_code=account_pair.destination_currency_code, exchange_rate_id=rate_row.id, rate_base_currency_code=rate_row.base_currency_code, rate_quote_currency_code=rate_row.quote_currency_code, rate_value=rate_row.rate_value, rate_source=rate_row.source, fee_amount=coalesce(p_fee_amount,0)::numeric(20,6), fee_currency_code=account_pair.fee_currency_code, fee_account_id=account_pair.fee_account_id, exchange_date=p_exchange_date, rounding_result=calc.rounding_result, reference=normalized_reference::varchar(120) WHERE id=exchange_row.id RETURNING id, app.currency_exchanges.destination_amount, app.currency_exchanges.rounding_result INTO currency_exchange_id, destination_amount, rounding_result;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id,actor_row.actor_auth_subject,actor_row.effective_role_code,'currency_exchange_updated','financial_event',financial_event_id,project_row.id,'success',jsonb_build_object('version_number',event_row.version_number),jsonb_build_object('currency_exchange_id',currency_exchange_id,'version_number',version_number,'source_account_id',account_pair.source_account_id,'destination_account_id',account_pair.destination_account_id),NULL,p_ip_address,p_session_identifier,p_request_identifier,p_correlation_identifier,'{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate currency exchange.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_submit_currency_exchange(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; exchange_row app.currency_exchanges%ROWTYPE; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE; SELECT * INTO exchange_row FROM app.currency_exchanges AS ce WHERE ce.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR exchange_row.id IS NULL OR event_row.event_type <> 'CURRENCY_EXCHANGE' OR event_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Currency exchange cannot be submitted.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Currency exchange version conflict.'; END IF;
  PERFORM app.currency_exchange_validate_accounts(exchange_row.source_account_id,exchange_row.destination_account_id,exchange_row.fee_account_id,exchange_row.fee_amount,true);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='SUBMITTED', submitted_at=now(), submitted_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='SUBMITTED' WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id,actor_row.actor_auth_subject,actor_row.effective_role_code,'currency_exchange_submitted','financial_event',financial_event_id,event_row.project_id,'success',jsonb_build_object('status','DRAFT','version_number',event_row.version_number),jsonb_build_object('currency_exchange_id',exchange_row.id,'status',status,'version_number',version_number),NULL,p_ip_address,p_session_identifier,p_request_identifier,p_correlation_identifier,'{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_reject_currency_exchange(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; exchange_row app.currency_exchanges%ROWTYPE; reason_text text := btrim(coalesce(p_rejection_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  IF reason_text='' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Rejection reason is required.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE; SELECT * INTO exchange_row FROM app.currency_exchanges AS ce WHERE ce.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR exchange_row.id IS NULL OR event_row.event_type <> 'CURRENCY_EXCHANGE' OR event_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Currency exchange cannot be rejected.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Currency exchange version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id,actor_row.actor_auth_subject,actor_row.effective_role_code,'currency_exchange_rejected','financial_event',financial_event_id,event_row.project_id,'success',jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number),jsonb_build_object('currency_exchange_id',exchange_row.id,'status',status,'version_number',version_number),NULL,p_ip_address,p_session_identifier,p_request_identifier,p_correlation_identifier,jsonb_build_object('reason_provided',true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_approve_currency_exchange(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; exchange_row app.currency_exchanges%ROWTYPE; account_pair record; common_snap record; fee_snap record; source_clearing_id uuid; destination_clearing_id uuid; fee_control_id uuid; common_reporting_amount numeric; source_snapshot_rate_id uuid; source_snapshot_base char(3); source_snapshot_quote char(3); source_snapshot_value numeric; source_snapshot_source varchar; derived_dest_rate numeric; previous_financial_context text := current_setting('app.financial_transaction_context', true); previous_posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE; SELECT * INTO transaction_row FROM app.financial_transactions AS ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE; SELECT * INTO exchange_row FROM app.currency_exchanges AS ce WHERE ce.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR exchange_row.id IS NULL OR event_row.event_type <> 'CURRENCY_EXCHANGE' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Currency exchange cannot be approved.'; END IF;
  IF event_row.status='APPROVED' AND transaction_row.status='POSTED' THEN financial_event_id:=event_row.id; financial_transaction_id:=transaction_row.id; event_status:=event_row.status::text; transaction_status:=transaction_row.status::text; ledger_entry_count:=(SELECT count(*)::integer FROM app.ledger_entries WHERE app.ledger_entries.financial_transaction_id=transaction_row.id); version_number:=event_row.version_number; RETURN NEXT; RETURN; END IF;
  IF event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Currency exchange cannot be approved.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Currency exchange version conflict.'; END IF;
  IF event_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Currency exchange requires different Owner approval.'; END IF;
  SELECT * INTO account_pair FROM app.currency_exchange_validate_accounts(exchange_row.source_account_id,exchange_row.destination_account_id,exchange_row.fee_account_id,exchange_row.fee_amount,true);
  IF NOT EXISTS (SELECT 1 FROM app.exchange_rates er WHERE er.id=exchange_row.exchange_rate_id AND er.rate_date=exchange_row.exchange_date AND er.base_currency_code=exchange_row.rate_base_currency_code AND er.quote_currency_code=exchange_row.rate_quote_currency_code AND er.rate_value=exchange_row.rate_value AND er.source=exchange_row.rate_source) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid currency exchange rate.'; END IF;
  IF transaction_row.reporting_currency_code = exchange_row.source_currency_code THEN
    common_reporting_amount := exchange_row.source_amount;
    source_snapshot_rate_id := NULL;
    source_snapshot_base := NULL;
    source_snapshot_quote := NULL;
    source_snapshot_value := NULL;
    source_snapshot_source := NULL;
  ELSIF transaction_row.reporting_currency_code = exchange_row.destination_currency_code THEN
    common_reporting_amount := exchange_row.destination_amount;
    source_snapshot_rate_id := exchange_row.exchange_rate_id;
    source_snapshot_base := exchange_row.rate_base_currency_code;
    source_snapshot_quote := exchange_row.rate_quote_currency_code;
    source_snapshot_value := exchange_row.rate_value;
    source_snapshot_source := exchange_row.rate_source;
  ELSE
    SELECT * INTO common_snap FROM app.currency_exchange_reporting_snapshot(exchange_row.source_amount, exchange_row.source_currency_code, transaction_row.reporting_currency_code, transaction_row.transaction_date);
    common_reporting_amount := common_snap.reporting_amount;
    source_snapshot_rate_id := common_snap.exchange_rate_id;
    source_snapshot_base := common_snap.rate_base_currency_code;
    source_snapshot_quote := common_snap.rate_quote_currency_code;
    source_snapshot_value := common_snap.rate_value;
    source_snapshot_source := common_snap.rate_source;
  END IF;
  source_clearing_id := app.ensure_currency_exchange_clearing_ledger_account(exchange_row.source_currency_code);
  destination_clearing_id := app.ensure_currency_exchange_clearing_ledger_account(exchange_row.destination_currency_code);
  IF exchange_row.destination_currency_code = transaction_row.reporting_currency_code THEN
    derived_dest_rate := NULL;
  ELSE
    derived_dest_rate := common_reporting_amount / exchange_row.destination_amount;
  END IF;
  IF exchange_row.fee_amount > 0 THEN
    SELECT * INTO fee_snap FROM app.financial_transaction_reporting_snapshot(exchange_row.fee_amount, exchange_row.fee_currency_code, transaction_row.reporting_currency_code, transaction_row.transaction_date);
    fee_control_id := app.ensure_currency_exchange_fee_ledger_account(exchange_row.fee_currency_code);
  END IF;
  PERFORM set_config('app.ledger_posting_context','currency_exchange_posting',true);
  INSERT INTO app.ledger_entries (financial_transaction_id,line_no,ledger_account_id,project_id,client_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,exchange_rate_id,rate_base_currency_code,rate_quote_currency_code,rate_value,rate_source,rounding_adjustment,memo,created_by)
  VALUES
    (transaction_row.id,1,account_pair.destination_ledger_account_id,event_row.project_id,event_row.client_id,exchange_row.destination_currency_code,exchange_row.destination_amount,0,transaction_row.reporting_currency_code,common_reporting_amount,0,NULL,CASE WHEN derived_dest_rate IS NULL THEN NULL ELSE exchange_row.destination_currency_code END,CASE WHEN derived_dest_rate IS NULL THEN NULL ELSE transaction_row.reporting_currency_code END,derived_dest_rate,CASE WHEN derived_dest_rate IS NULL THEN NULL ELSE 'DERIVED_FROM_CURRENCY_EXCHANGE' END,0,'Currency exchange destination debit',actor_row.actor_user_id),
    (transaction_row.id,2,destination_clearing_id,event_row.project_id,event_row.client_id,exchange_row.destination_currency_code,0,exchange_row.destination_amount,transaction_row.reporting_currency_code,0,common_reporting_amount,NULL,CASE WHEN derived_dest_rate IS NULL THEN NULL ELSE exchange_row.destination_currency_code END,CASE WHEN derived_dest_rate IS NULL THEN NULL ELSE transaction_row.reporting_currency_code END,derived_dest_rate,CASE WHEN derived_dest_rate IS NULL THEN NULL ELSE 'DERIVED_FROM_CURRENCY_EXCHANGE' END,exchange_row.rounding_result,'Currency exchange destination clearing credit',actor_row.actor_user_id),
    (transaction_row.id,3,source_clearing_id,event_row.project_id,event_row.client_id,exchange_row.source_currency_code,exchange_row.source_amount,0,transaction_row.reporting_currency_code,common_reporting_amount,0,source_snapshot_rate_id,source_snapshot_base,source_snapshot_quote,source_snapshot_value,source_snapshot_source,0,'Currency exchange source clearing debit',actor_row.actor_user_id),
    (transaction_row.id,4,account_pair.source_ledger_account_id,event_row.project_id,event_row.client_id,exchange_row.source_currency_code,0,exchange_row.source_amount,transaction_row.reporting_currency_code,0,common_reporting_amount,source_snapshot_rate_id,source_snapshot_base,source_snapshot_quote,source_snapshot_value,source_snapshot_source,0,'Currency exchange source credit',actor_row.actor_user_id);
  IF exchange_row.fee_amount > 0 THEN
    INSERT INTO app.ledger_entries (financial_transaction_id,line_no,ledger_account_id,project_id,client_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,exchange_rate_id,rate_base_currency_code,rate_quote_currency_code,rate_value,rate_source,rounding_adjustment,memo,created_by)
    VALUES
      (transaction_row.id,5,fee_control_id,event_row.project_id,event_row.client_id,exchange_row.fee_currency_code,exchange_row.fee_amount,0,transaction_row.reporting_currency_code,fee_snap.reporting_amount,0,fee_snap.exchange_rate_id,fee_snap.rate_base_currency_code,fee_snap.rate_quote_currency_code,fee_snap.rate_value,fee_snap.rate_source,fee_snap.rounding_adjustment,'Currency exchange fee debit',actor_row.actor_user_id),
      (transaction_row.id,6,account_pair.fee_ledger_account_id,event_row.project_id,event_row.client_id,exchange_row.fee_currency_code,0,exchange_row.fee_amount,transaction_row.reporting_currency_code,0,fee_snap.reporting_amount,fee_snap.exchange_rate_id,fee_snap.rate_base_currency_code,fee_snap.rate_quote_currency_code,fee_snap.rate_value,fee_snap.rate_source,fee_snap.rounding_adjustment,'Currency exchange fee credit',actor_row.actor_user_id);
  END IF;
  PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true);
  IF EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY currency_code HAVING sum(debit_amount)<>sum(credit_amount)) OR EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY reporting_currency_code HAVING sum(reporting_debit_amount)<>sum(reporting_credit_amount)) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Ledger entries do not balance.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_transactions SET status='POSTED', approved_at=now(), approved_by=actor_row.actor_user_id, posted_at=now(), posted_by=actor_row.actor_user_id WHERE id=transaction_row.id RETURNING id, app.financial_transactions.status::text INTO financial_transaction_id, transaction_status;
  UPDATE app.financial_events SET status='APPROVED', approved_at=now(), approved_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=event_row.id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, event_status, version_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true);
  ledger_entry_count := CASE WHEN exchange_row.fee_amount > 0 THEN 6 ELSE 4 END;
  PERFORM app.write_activity_log(actor_row.actor_user_id,actor_row.actor_auth_subject,actor_row.effective_role_code,'currency_exchange_approved','financial_event',financial_event_id,event_row.project_id,'success',jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number),jsonb_build_object('currency_exchange_id',exchange_row.id,'status',event_status,'version_number',version_number,'ledger_entry_count',ledger_entry_count),NULL,p_ip_address,p_session_identifier,p_request_identifier,p_correlation_identifier,'{}'::jsonb);
  PERFORM app.write_activity_log(actor_row.actor_user_id,actor_row.actor_auth_subject,actor_row.effective_role_code,'currency_exchange_transaction_posted','financial_transaction',financial_transaction_id,event_row.project_id,'success',jsonb_build_object('status','SUBMITTED'),jsonb_build_object('currency_exchange_id',exchange_row.id,'status',transaction_status,'ledger_entry_count',ledger_entry_count),NULL,p_ip_address,p_session_identifier,p_request_identifier,p_correlation_identifier,'{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true); PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_currency_exchange_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, source_account_id uuid, destination_account_id uuid, source_amount numeric, source_currency_code char(3), destination_amount numeric, destination_currency_code char(3), fee_amount numeric, fee_currency_code char(3), exchange_date date, event_status text, transaction_status text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT ce.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, fe.project_id, fe.client_id, ce.source_account_id, ce.destination_account_id, ce.source_amount, ce.source_currency_code, ce.destination_amount, ce.destination_currency_code, ce.fee_amount, ce.fee_currency_code, ce.exchange_date, fe.status::text, ft.status::text, fe.version_number FROM app.currency_exchanges ce JOIN app.financial_events fe ON fe.id=ce.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.event_type='CURRENCY_EXCHANGE' ORDER BY fe.created_at DESC, fe.id DESC LIMIT safe_limit OFFSET safe_offset;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_currency_exchange_detail(p_actor_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, source_account_id uuid, destination_account_id uuid, source_amount numeric, source_currency_code char(3), destination_amount numeric, destination_currency_code char(3), exchange_rate_id uuid, rate_base_currency_code char(3), rate_quote_currency_code char(3), rate_value numeric, rate_source text, fee_amount numeric, fee_currency_code char(3), fee_account_id uuid, exchange_date date, rounding_result numeric, reference text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT ce.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, fe.project_id, fe.client_id, ce.source_account_id, ce.destination_account_id, ce.source_amount, ce.source_currency_code, ce.destination_amount, ce.destination_currency_code, ce.exchange_rate_id, ce.rate_base_currency_code, ce.rate_quote_currency_code, ce.rate_value, ce.rate_source::text, ce.fee_amount, ce.fee_currency_code, ce.fee_account_id, ce.exchange_date, ce.rounding_result, ce.reference::text, ft.reporting_currency_code, fe.status::text, ft.status::text, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number FROM app.currency_exchanges ce JOIN app.financial_events fe ON fe.id=ce.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.id=p_financial_event_id AND fe.event_type='CURRENCY_EXCHANGE';
END $function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_currency_exchange(p_verified_owner_auth_subject uuid, p_source_account_id uuid, p_destination_account_id uuid, p_source_amount numeric, p_exchange_rate_id uuid, p_fee_amount numeric DEFAULT 0, p_fee_account_id uuid DEFAULT NULL, p_exchange_date date DEFAULT NULL, p_project_id uuid DEFAULT NULL, p_reference text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, destination_amount numeric, rounding_result numeric, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_currency_exchange(p_verified_owner_auth_subject,p_source_account_id,p_destination_account_id,p_source_amount,p_exchange_rate_id,p_fee_amount,p_fee_account_id,p_exchange_date,p_project_id,p_reference,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_currency_exchange(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_source_account_id uuid, p_destination_account_id uuid, p_source_amount numeric, p_exchange_rate_id uuid, p_fee_amount numeric DEFAULT 0, p_fee_account_id uuid DEFAULT NULL, p_exchange_date date DEFAULT NULL, p_project_id uuid DEFAULT NULL, p_reference text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, financial_transaction_id uuid, destination_amount numeric, rounding_result numeric, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_currency_exchange(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_source_account_id,p_destination_account_id,p_source_amount,p_exchange_rate_id,p_fee_amount,p_fee_account_id,p_exchange_date,p_project_id,p_reference,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_submit_currency_exchange(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_currency_exchange(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_currency_exchange(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_currency_exchange(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_currency_exchange(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_currency_exchange(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_currency_exchange_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, source_account_id uuid, destination_account_id uuid, source_amount numeric, source_currency_code char(3), destination_amount numeric, destination_currency_code char(3), fee_amount numeric, fee_currency_code char(3), exchange_date date, event_status text, transaction_status text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_currency_exchange_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_currency_exchange_detail(p_verified_owner_auth_subject uuid, p_financial_event_id uuid) RETURNS TABLE (currency_exchange_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, source_account_id uuid, destination_account_id uuid, source_amount numeric, source_currency_code char(3), destination_amount numeric, destination_currency_code char(3), exchange_rate_id uuid, rate_base_currency_code char(3), rate_quote_currency_code char(3), rate_value numeric, rate_source text, fee_amount numeric, fee_currency_code char(3), fee_account_id uuid, exchange_date date, rounding_result numeric, reference text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_currency_exchange_detail(p_verified_owner_auth_subject,p_financial_event_id); $function$;

CREATE OR REPLACE FUNCTION app.ledger_entries_trusted_insert_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE transaction_row app.financial_transactions%ROWTYPE; ledger_row app.ledger_accounts%ROWTYPE; posting_context text := coalesce(current_setting('app.ledger_posting_context', true), '');
BEGIN
  IF posting_context NOT IN ('opening_balance_posting','financial_reversal_posting','financial_adjustment_posting','client_payment_posting','project_expense_posting','account_transfer_posting','currency_exchange_posting') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries require trusted posting.'; END IF;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE id = NEW.financial_transaction_id; SELECT * INTO ledger_row FROM app.ledger_accounts WHERE id = NEW.ledger_account_id;
  IF transaction_row.id IS NULL OR ledger_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid ledger entry.'; END IF;
  IF NEW.currency_code IS DISTINCT FROM ledger_row.currency_code THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry currency must match ledger account currency.'; END IF;
  IF NEW.reporting_currency_code IS DISTINCT FROM transaction_row.reporting_currency_code THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry reporting currency must match transaction.'; END IF;
  RETURN NEW;
END $function$;

COMMIT;
