BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_client_payment_reference(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT upper(NULLIF(btrim(p_value), ''));
$function$;

CREATE OR REPLACE FUNCTION app.client_payment_duplicate_fingerprint(p_client_id uuid, p_project_id uuid, p_currency_code char(3), p_received_date date, p_amount numeric, p_payment_reference text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT 'CLIENT_PAYMENT|client=' || p_client_id::text || '|project=' || p_project_id::text || '|currency=' || p_currency_code::text || '|date=' || p_received_date::text || '|amount=' || p_amount::numeric(20,6)::text || '|reference=' || coalesce(app.normalize_client_payment_reference(p_payment_reference), '<NULL>');
$function$;

CREATE OR REPLACE FUNCTION app.ensure_client_payment_control_ledger_account(p_currency_code char(3))
RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE ledger_account_id uuid; previous_context text := current_setting('app.ledger_account_sync_context', true);
BEGIN
  IF p_currency_code IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = p_currency_code AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Valid client payment currency is required.';
  END IF;
  PERFORM set_config('app.ledger_account_sync_context', 'financial_account_sync', true);
  INSERT INTO app.ledger_accounts (code, name, account_kind, financial_account_id, currency_code, normal_side, is_system, is_active)
  VALUES ('CTRL-CLIENT-PAYMENT-' || p_currency_code::text, 'Client Payment Control - ' || p_currency_code::text, 'CONTROL', NULL, p_currency_code, 'CREDIT', true, true)
  ON CONFLICT (code) DO UPDATE
  SET name = EXCLUDED.name, currency_code = EXCLUDED.currency_code, is_system = true, is_active = true
  RETURNING id INTO ledger_account_id;
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RETURN ledger_account_id;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_client_payment(p_actor_auth_subject uuid, p_project_id uuid, p_amount numeric, p_currency_code char(3), p_received_date date, p_received_account_id uuid DEFAULT NULL, p_payment_reference text DEFAULT NULL, p_payer_name text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, client_payment_id uuid, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; project_row app.projects%ROWTYPE; account_row app.financial_accounts%ROWTYPE; fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO project_row FROM app.projects WHERE id=p_project_id FOR UPDATE;
  IF project_row.id IS NULL OR project_row.archived_at IS NOT NULL OR p_amount IS NULL OR p_amount <= 0 OR p_currency_code IS NULL OR p_received_date IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid client payment.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM app.clients WHERE id=project_row.client_id AND is_active AND archived_at IS NULL) OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=p_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid client payment.'; END IF;
  IF p_received_account_id IS NOT NULL THEN SELECT * INTO account_row FROM app.financial_accounts WHERE id=p_received_account_id FOR UPDATE; IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR account_row.currency_code IS DISTINCT FROM p_currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid receiving account.'; END IF; END IF;
  fp := app.client_payment_duplicate_fingerprint(project_row.client_id, project_row.id, p_currency_code, p_received_date, p_amount, p_payment_reference);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  INSERT INTO app.financial_events (event_type, project_id, client_id, event_date, status, description, duplicate_fingerprint, created_by, updated_by)
  VALUES ('CLIENT_PAYMENT', project_row.id, project_row.client_id, p_received_date, 'DRAFT', app.normalize_financial_optional_text(p_payment_reference), fp, actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id, app.financial_events.event_number, app.financial_events.version_number INTO financial_event_id, event_number, version_number;
  INSERT INTO app.financial_transactions (financial_event_id, transaction_date, status, reporting_currency_code, description, created_by)
  VALUES (financial_event_id, p_received_date, 'DRAFT', project_row.reporting_currency_code, app.normalize_financial_optional_text(p_payment_reference), actor_row.actor_user_id)
  RETURNING id, app.financial_transactions.transaction_number INTO financial_transaction_id, transaction_number;
  INSERT INTO app.client_payments (financial_event_id, project_id, client_id, amount, currency_code, received_account_id, received_date, payment_reference, payer_name, is_client_submitted, submitted_by_client_user_id, notes)
  VALUES (financial_event_id, project_row.id, project_row.client_id, p_amount::numeric(20,6), p_currency_code, p_received_account_id, p_received_date, NULLIF(btrim(p_payment_reference),'')::varchar(120), NULLIF(btrim(p_payer_name),'')::varchar(200), false, NULL, app.normalize_financial_optional_text(p_notes))
  RETURNING id INTO client_payment_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'client_payment_created', 'financial_event', financial_event_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('status','DRAFT','project_id',project_row.id,'client_id',project_row.client_id,'currency_code',p_currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate client payment.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_client_payment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_amount numeric, p_currency_code char(3), p_received_date date, p_received_account_id uuid DEFAULT NULL, p_payment_reference text DEFAULT NULL, p_payer_name text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, client_payment_id uuid, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; payment_row app.client_payments%ROWTYPE; project_row app.projects%ROWTYPE; account_row app.financial_accounts%ROWTYPE; fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO payment_row FROM app.client_payments cp WHERE cp.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO project_row FROM app.projects WHERE id=payment_row.project_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR payment_row.id IS NULL OR project_row.id IS NULL OR event_row.event_type <> 'CLIENT_PAYMENT' OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' OR payment_row.is_client_submitted THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Client payment cannot be updated.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Client payment version conflict.'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_currency_code IS NULL OR p_received_date IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=p_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid client payment.'; END IF;
  IF p_received_account_id IS NOT NULL THEN SELECT * INTO account_row FROM app.financial_accounts WHERE id=p_received_account_id FOR UPDATE; IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR account_row.currency_code IS DISTINCT FROM p_currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid receiving account.'; END IF; END IF;
  fp := app.client_payment_duplicate_fingerprint(payment_row.client_id, payment_row.project_id, p_currency_code, p_received_date, p_amount, p_payment_reference);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET event_date=p_received_date, description=app.normalize_financial_optional_text(p_payment_reference), duplicate_fingerprint=fp, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.version_number INTO financial_event_id, version_number;
  UPDATE app.financial_transactions SET transaction_date=p_received_date, reporting_currency_code=project_row.reporting_currency_code, description=app.normalize_financial_optional_text(p_payment_reference) WHERE id=transaction_row.id RETURNING id INTO financial_transaction_id;
  UPDATE app.client_payments SET amount=p_amount::numeric(20,6), currency_code=p_currency_code, received_account_id=p_received_account_id, received_date=p_received_date, payment_reference=NULLIF(btrim(p_payment_reference),'')::varchar(120), payer_name=NULLIF(btrim(p_payer_name),'')::varchar(200), notes=app.normalize_financial_optional_text(p_notes) WHERE id=payment_row.id RETURNING id INTO client_payment_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'client_payment_updated', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('version_number',event_row.version_number), jsonb_build_object('version_number',version_number,'project_id',payment_row.project_id,'client_id',payment_row.client_id,'currency_code',p_currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate client payment.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_verify_client_submitted_payment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_received_account_id uuid, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, client_payment_id uuid, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; payment_row app.client_payments%ROWTYPE; account_row app.financial_accounts%ROWTYPE; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO payment_row FROM app.client_payments cp WHERE cp.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=p_received_account_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR payment_row.id IS NULL OR event_row.event_type <> 'CLIENT_PAYMENT' OR event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' OR NOT payment_row.is_client_submitted THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Client-submitted payment cannot be verified.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Client payment version conflict.'; END IF;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR account_row.currency_code IS DISTINCT FROM payment_row.currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid receiving account.'; END IF;
  PERFORM set_config('app.financial_transaction_context','client_payment_owner_verification',true);
  UPDATE app.client_payments SET received_account_id=account_row.id, notes=app.normalize_financial_optional_text(p_notes) WHERE id=payment_row.id RETURNING id INTO client_payment_id;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET updated_by=actor_row.actor_user_id WHERE id=event_row.id RETURNING id, app.financial_events.version_number INTO financial_event_id, version_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'client_payment_verified', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('version_number',event_row.version_number), jsonb_build_object('version_number',version_number,'project_id',payment_row.project_id,'client_id',payment_row.client_id,'currency_code',payment_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_submit_client_payment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; payment_row app.client_payments%ROWTYPE; account_row app.financial_accounts%ROWTYPE; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO payment_row FROM app.client_payments cp WHERE cp.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=payment_row.received_account_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR payment_row.id IS NULL OR event_row.event_type <> 'CLIENT_PAYMENT' OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' OR payment_row.is_client_submitted THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Client payment cannot be submitted.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Client payment version conflict.'; END IF;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR account_row.currency_code IS DISTINCT FROM payment_row.currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid receiving account.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='SUBMITTED', submitted_at=now(), submitted_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='SUBMITTED' WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'client_payment_submitted', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','DRAFT','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number,'project_id',payment_row.project_id,'client_id',payment_row.client_id,'currency_code',payment_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_reject_client_payment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; reason_text text := btrim(coalesce(p_rejection_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  IF reason_text='' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Rejection reason is required.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.event_type <> 'CLIENT_PAYMENT' OR event_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Client payment cannot be rejected.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Client payment version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'client_payment_rejected', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided',true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_approve_client_payment(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; payment_row app.client_payments%ROWTYPE; project_row app.projects%ROWTYPE; client_row app.clients%ROWTYPE; account_row app.financial_accounts%ROWTYPE; asset_row app.ledger_accounts%ROWTYPE; control_id uuid; control_row app.ledger_accounts%ROWTYPE; snap record; previous_financial_context text := current_setting('app.financial_transaction_context', true); previous_posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO payment_row FROM app.client_payments cp WHERE cp.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR payment_row.id IS NULL OR event_row.event_type <> 'CLIENT_PAYMENT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Client payment cannot be approved.'; END IF;
  IF event_row.status='APPROVED' AND transaction_row.status='POSTED' THEN financial_event_id:=event_row.id; financial_transaction_id:=transaction_row.id; event_status:=event_row.status::text; transaction_status:=transaction_row.status::text; ledger_entry_count:=(SELECT count(*)::integer FROM app.ledger_entries WHERE app.ledger_entries.financial_transaction_id=transaction_row.id); version_number:=event_row.version_number; RETURN NEXT; RETURN; END IF;
  IF event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Client payment cannot be approved.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Client payment version conflict.'; END IF;
  IF event_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client payment requires different Owner approval.'; END IF;
  SELECT * INTO project_row FROM app.projects WHERE id=payment_row.project_id FOR UPDATE;
  SELECT * INTO client_row FROM app.clients WHERE id=payment_row.client_id FOR UPDATE;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=payment_row.received_account_id FOR UPDATE;
  SELECT * INTO asset_row FROM app.ledger_accounts WHERE financial_account_id=account_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE;
  IF project_row.id IS NULL OR client_row.id IS NULL OR project_row.client_id IS DISTINCT FROM client_row.id OR event_row.project_id IS DISTINCT FROM project_row.id OR event_row.client_id IS DISTINCT FROM client_row.id THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid client payment.'; END IF;
  IF payment_row.amount <= 0 OR payment_row.received_account_id IS NULL OR account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR account_row.currency_code IS DISTINCT FROM payment_row.currency_code OR asset_row.id IS NULL OR NOT asset_row.is_active OR asset_row.currency_code IS DISTINCT FROM payment_row.currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid client payment.'; END IF;
  IF payment_row.received_date IS DISTINCT FROM event_row.event_date OR event_row.event_date IS DISTINCT FROM transaction_row.transaction_date OR transaction_row.reporting_currency_code IS DISTINCT FROM project_row.reporting_currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid client payment.'; END IF;
  SELECT * INTO snap FROM app.financial_transaction_reporting_snapshot(payment_row.amount, payment_row.currency_code, transaction_row.reporting_currency_code, transaction_row.transaction_date);
  control_id := app.ensure_client_payment_control_ledger_account(payment_row.currency_code);
  SELECT * INTO control_row FROM app.ledger_accounts WHERE id=control_id FOR UPDATE;
  PERFORM set_config('app.ledger_posting_context','client_payment_posting',true);
  INSERT INTO app.ledger_entries (financial_transaction_id,line_no,ledger_account_id,project_id,client_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,exchange_rate_id,rate_base_currency_code,rate_quote_currency_code,rate_value,rate_source,rounding_adjustment,memo,created_by)
  VALUES (transaction_row.id,1,asset_row.id,project_row.id,client_row.id,payment_row.currency_code,payment_row.amount,0,transaction_row.reporting_currency_code,snap.reporting_amount,0,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Client payment debit',actor_row.actor_user_id),
         (transaction_row.id,2,control_row.id,project_row.id,client_row.id,payment_row.currency_code,0,payment_row.amount,transaction_row.reporting_currency_code,0,snap.reporting_amount,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Client payment credit',actor_row.actor_user_id);
  PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true);
  IF EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY le.currency_code HAVING sum(le.debit_amount)<>sum(le.credit_amount)) OR EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY le.reporting_currency_code HAVING sum(le.reporting_debit_amount)<>sum(le.reporting_credit_amount)) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Ledger entries do not balance.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_transactions SET status='POSTED', approved_at=now(), approved_by=actor_row.actor_user_id, posted_at=now(), posted_by=actor_row.actor_user_id WHERE id=transaction_row.id RETURNING id, app.financial_transactions.status::text INTO financial_transaction_id, transaction_status;
  UPDATE app.financial_events SET status='APPROVED', approved_at=now(), approved_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=event_row.id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, event_status, version_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true);
  ledger_entry_count := 2;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'client_payment_approved', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',event_status,'version_number',version_number,'project_id',project_row.id,'client_id',client_row.id,'currency_code',payment_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'client_payment_transaction_posted', 'financial_transaction', financial_transaction_id, NULL, 'success', jsonb_build_object('status','SUBMITTED'), jsonb_build_object('status',transaction_status,'ledger_entry_count',2,'project_id',project_row.id,'client_id',client_row.id,'currency_code',payment_row.currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true); PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_submit_payment(p_project_id uuid, p_amount numeric, p_currency_code char(3), p_received_date date, p_payment_reference text DEFAULT NULL, p_payer_name text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, client_payment_id uuid)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE client_ctx record; project_row app.projects%ROWTYPE; fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT c.id AS client_id, c.portal_user_id AS user_id INTO client_ctx FROM app.users u JOIN app.clients c ON c.portal_user_id=u.id WHERE u.auth_subject=auth.uid() AND u.user_type='CLIENT' AND u.status='ACTIVE' AND u.is_active AND c.status='ACTIVE' AND c.is_active AND c.archived_at IS NULL AND EXISTS (SELECT 1 FROM app.user_roles ur WHERE ur.user_id=u.id AND ur.role_code='client' AND ur.is_active) LIMIT 1;
  IF client_ctx.client_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  SELECT * INTO project_row FROM app.projects WHERE id=p_project_id FOR UPDATE;
  IF project_row.id IS NULL OR project_row.client_id IS DISTINCT FROM client_ctx.client_id OR project_row.archived_at IS NOT NULL OR p_amount IS NULL OR p_amount <= 0 OR p_currency_code IS NULL OR p_received_date IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=p_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid client payment.'; END IF;
  fp := app.client_payment_duplicate_fingerprint(client_ctx.client_id, project_row.id, p_currency_code, p_received_date, p_amount, p_payment_reference);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  INSERT INTO app.financial_events (event_type, project_id, client_id, event_date, status, description, submitted_at, submitted_by, duplicate_fingerprint, created_by, updated_by)
  VALUES ('CLIENT_PAYMENT', project_row.id, client_ctx.client_id, p_received_date, 'SUBMITTED', app.normalize_financial_optional_text(p_payment_reference), now(), client_ctx.user_id, fp, client_ctx.user_id, client_ctx.user_id)
  RETURNING id, app.financial_events.event_number INTO financial_event_id, event_number;
  INSERT INTO app.financial_transactions (financial_event_id, transaction_date, status, reporting_currency_code, description, created_by)
  VALUES (financial_event_id, p_received_date, 'SUBMITTED', project_row.reporting_currency_code, app.normalize_financial_optional_text(p_payment_reference), client_ctx.user_id)
  RETURNING id, app.financial_transactions.transaction_number INTO financial_transaction_id, transaction_number;
  PERFORM set_config('app.financial_transaction_context','client_payment_client_submission',true);
  INSERT INTO app.client_payments (financial_event_id, project_id, client_id, amount, currency_code, received_account_id, received_date, payment_reference, payer_name, is_client_submitted, submitted_by_client_user_id, notes)
  VALUES (financial_event_id, project_row.id, client_ctx.client_id, p_amount::numeric(20,6), p_currency_code, NULL, p_received_date, NULLIF(btrim(p_payment_reference),'')::varchar(120), NULLIF(btrim(p_payer_name),'')::varchar(200), true, client_ctx.user_id, NULL)
  RETURNING id INTO client_payment_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(client_ctx.user_id, auth.uid(), 'client', 'client_payment_client_submitted', 'financial_event', financial_event_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('status','SUBMITTED','project_id',project_row.id,'client_id',client_ctx.client_id,'currency_code',p_currency_code), NULL, NULL, NULL, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate client payment.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_client_payment_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (client_payment_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, amount numeric, currency_code char(3), received_date date, event_status text, transaction_status text, is_client_submitted boolean, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT cp.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, cp.project_id, cp.client_id, cp.amount, cp.currency_code, cp.received_date, fe.status::text, ft.status::text, cp.is_client_submitted, fe.version_number FROM app.client_payments cp JOIN app.financial_events fe ON fe.id=cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id ORDER BY fe.created_at DESC, fe.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_client_payment_detail(p_actor_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (client_payment_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, amount numeric, currency_code char(3), received_account_id uuid, received_date date, payment_reference text, payer_name text, is_client_submitted boolean, submitted_by_client_user_id uuid, notes text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT cp.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, cp.project_id, cp.client_id, cp.amount, cp.currency_code, cp.received_account_id, cp.received_date, cp.payment_reference::text, cp.payer_name::text, cp.is_client_submitted, cp.submitted_by_client_user_id, cp.notes, ft.reporting_currency_code, fe.status::text, ft.status::text, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number FROM app.client_payments cp JOIN app.financial_events fe ON fe.id=cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.id=p_financial_event_id AND fe.event_type='CLIENT_PAYMENT';
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_project_client_payment_totals(p_actor_auth_subject uuid, p_project_id uuid)
RETURNS TABLE (project_id uuid, currency_code char(3), total_received numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT le.project_id, le.currency_code, coalesce(sum(le.debit_amount),0)::numeric FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id AND ft.status='POSTED' JOIN app.financial_events fe ON fe.id=ft.financial_event_id AND fe.event_type='CLIENT_PAYMENT' WHERE le.project_id=p_project_id AND le.debit_amount > 0 GROUP BY le.project_id, le.currency_code ORDER BY le.currency_code;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_approved_payment_list(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (client_payment_id uuid, project_id uuid, project_number text, amount numeric, currency_code char(3), received_date date, payment_reference text, approved_at timestamptz, event_status text, transaction_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE client_id_value uuid; safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  SELECT c.id INTO client_id_value FROM app.users u JOIN app.clients c ON c.portal_user_id=u.id WHERE u.auth_subject=auth.uid() AND u.user_type='CLIENT' AND u.status='ACTIVE' AND u.is_active AND c.status='ACTIVE' AND c.is_active AND c.archived_at IS NULL AND EXISTS (SELECT 1 FROM app.user_roles ur WHERE ur.user_id=u.id AND ur.role_code='client' AND ur.is_active) LIMIT 1;
  IF client_id_value IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  RETURN QUERY SELECT cp.id, cp.project_id, p.project_number::text, cp.amount, cp.currency_code, cp.received_date, cp.payment_reference::text, fe.approved_at, fe.status::text, ft.status::text FROM app.client_payments cp JOIN app.projects p ON p.id=cp.project_id JOIN app.financial_events fe ON fe.id=cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE cp.client_id=client_id_value AND p.client_id=client_id_value AND fe.status='APPROVED' AND ft.status='POSTED' ORDER BY cp.received_date DESC, cp.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_approved_payment_detail(p_client_payment_id uuid)
RETURNS TABLE (client_payment_id uuid, project_id uuid, project_number text, amount numeric, currency_code char(3), received_date date, payment_reference text, approved_at timestamptz, event_status text, transaction_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE client_id_value uuid;
BEGIN
  SELECT c.id INTO client_id_value FROM app.users u JOIN app.clients c ON c.portal_user_id=u.id WHERE u.auth_subject=auth.uid() AND u.user_type='CLIENT' AND u.status='ACTIVE' AND u.is_active AND c.status='ACTIVE' AND c.is_active AND c.archived_at IS NULL AND EXISTS (SELECT 1 FROM app.user_roles ur WHERE ur.user_id=u.id AND ur.role_code='client' AND ur.is_active) LIMIT 1;
  IF client_id_value IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  RETURN QUERY SELECT cp.id, cp.project_id, p.project_number::text, cp.amount, cp.currency_code, cp.received_date, cp.payment_reference::text, fe.approved_at, fe.status::text, ft.status::text FROM app.client_payments cp JOIN app.projects p ON p.id=cp.project_id JOIN app.financial_events fe ON fe.id=cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE cp.id=p_client_payment_id AND cp.client_id=client_id_value AND p.client_id=client_id_value AND fe.status='APPROVED' AND ft.status='POSTED';
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_client_payment(p_verified_owner_auth_subject uuid, p_project_id uuid, p_amount numeric, p_currency_code char(3), p_received_date date, p_received_account_id uuid DEFAULT NULL, p_payment_reference text DEFAULT NULL, p_payer_name text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, client_payment_id uuid, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_client_payment(p_verified_owner_auth_subject,p_project_id,p_amount,p_currency_code,p_received_date,p_received_account_id,p_payment_reference,p_payer_name,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_client_payment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_amount numeric, p_currency_code char(3), p_received_date date, p_received_account_id uuid DEFAULT NULL, p_payment_reference text DEFAULT NULL, p_payer_name text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, client_payment_id uuid, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_client_payment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_amount,p_currency_code,p_received_date,p_received_account_id,p_payment_reference,p_payer_name,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_verify_client_submitted_payment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_received_account_id uuid, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, client_payment_id uuid, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_verify_client_submitted_payment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_received_account_id,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_submit_client_payment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_client_payment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_client_payment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_client_payment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_client_payment(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_client_payment(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_client_payment_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (client_payment_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, amount numeric, currency_code char(3), received_date date, event_status text, transaction_status text, is_client_submitted boolean, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_client_payment_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_client_payment_detail(p_verified_owner_auth_subject uuid, p_financial_event_id uuid) RETURNS TABLE (client_payment_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_id uuid, client_id uuid, amount numeric, currency_code char(3), received_account_id uuid, received_date date, payment_reference text, payer_name text, is_client_submitted boolean, submitted_by_client_user_id uuid, notes text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_client_payment_detail(p_verified_owner_auth_subject,p_financial_event_id); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_project_client_payment_totals(p_verified_owner_auth_subject uuid, p_project_id uuid) RETURNS TABLE (project_id uuid, currency_code char(3), total_received numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_project_client_payment_totals(p_verified_owner_auth_subject,p_project_id); $function$;
CREATE OR REPLACE FUNCTION public.current_client_submit_payment(p_project_id uuid, p_amount numeric, p_currency_code char(3), p_received_date date, p_payment_reference text DEFAULT NULL, p_payer_name text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, client_payment_id uuid) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.current_client_submit_payment(p_project_id,p_amount,p_currency_code,p_received_date,p_payment_reference,p_payer_name,p_request_identifier,p_correlation_identifier); $function$;
CREATE OR REPLACE FUNCTION public.current_client_approved_payment_list(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (client_payment_id uuid, project_id uuid, project_number text, amount numeric, currency_code char(3), received_date date, payment_reference text, approved_at timestamptz, event_status text, transaction_status text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.current_client_approved_payment_list(p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.current_client_approved_payment_detail(p_client_payment_id uuid) RETURNS TABLE (client_payment_id uuid, project_id uuid, project_number text, amount numeric, currency_code char(3), received_date date, payment_reference text, approved_at timestamptz, event_status text, transaction_status text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.current_client_approved_payment_detail(p_client_payment_id); $function$;

COMMIT;
