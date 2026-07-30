BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_project_expense_vendor_reference(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT upper(NULLIF(btrim(p_value), ''));
$function$;

CREATE OR REPLACE FUNCTION app.project_expense_duplicate_fingerprint(p_project_id uuid, p_currency_code char(3), p_expense_date date, p_amount numeric, p_vendor_reference text, p_expense_number text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT 'PROJECT_EXPENSE|project=' || p_project_id::text || '|currency=' || p_currency_code::text || '|date=' || p_expense_date::text || '|amount=' || p_amount::numeric(20,6)::text || CASE WHEN app.normalize_project_expense_vendor_reference(p_vendor_reference) IS NULL THEN '|expense_number=' || p_expense_number ELSE '|vendor_reference=' || app.normalize_project_expense_vendor_reference(p_vendor_reference) END;
$function$;

CREATE OR REPLACE FUNCTION app.ensure_project_expense_control_ledger_account(p_currency_code char(3))
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE ledger_account_id uuid; previous_context text := current_setting('app.ledger_account_sync_context', true);
BEGIN
  IF p_currency_code IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code = p_currency_code AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Valid project expense currency is required.';
  END IF;
  PERFORM set_config('app.ledger_account_sync_context', 'financial_account_sync', true);
  INSERT INTO app.ledger_accounts (code, name, account_kind, financial_account_id, currency_code, normal_side, is_system, is_active)
  VALUES ('CTRL-PROJECT-EXPENSE-' || p_currency_code::text, 'Project Expense Control - ' || p_currency_code::text, 'CONTROL', NULL, p_currency_code, 'DEBIT', true, true)
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, currency_code = EXCLUDED.currency_code, is_system = true, is_active = true
  RETURNING id INTO ledger_account_id;
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RETURN ledger_account_id;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.ledger_account_sync_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_expense_category(p_actor_auth_subject uuid, p_code text, p_name text, p_description text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (expense_category_id uuid, code text, name text, is_active boolean, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; previous_context text := current_setting('app.expense_category_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  IF NULLIF(btrim(p_code),'') IS NULL OR NULLIF(btrim(p_name),'') IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid expense category.'; END IF;
  PERFORM set_config('app.expense_category_context','expense_category_owner_mutation',true);
  INSERT INTO app.expense_categories (code, name, description, created_by, updated_by)
  VALUES (upper(btrim(p_code)), btrim(p_name), app.normalize_financial_optional_text(p_description), actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id, app.expense_categories.code::text, app.expense_categories.name::text, app.expense_categories.is_active, app.expense_categories.version_number INTO expense_category_id, code, name, is_active, version_number;
  PERFORM set_config('app.expense_category_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'expense_category_created', 'expense_category', expense_category_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('code', code, 'is_active', is_active, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.expense_category_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate expense category.';
WHEN OTHERS THEN PERFORM set_config('app.expense_category_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_expense_category(p_actor_auth_subject uuid, p_expense_category_id uuid, p_expected_version_number integer, p_name text, p_description text DEFAULT NULL, p_is_active boolean DEFAULT true, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (expense_category_id uuid, code text, name text, is_active boolean, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; category_row app.expense_categories%ROWTYPE; previous_context text := current_setting('app.expense_category_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO category_row FROM app.expense_categories WHERE id=p_expense_category_id FOR UPDATE;
  IF category_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Expense category not found.'; END IF;
  IF category_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Expense category version conflict.'; END IF;
  IF NULLIF(btrim(p_name),'') IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid expense category.'; END IF;
  PERFORM set_config('app.expense_category_context','expense_category_owner_mutation',true);
  UPDATE app.expense_categories SET name=btrim(p_name), description=app.normalize_financial_optional_text(p_description), is_active=coalesce(p_is_active,true), updated_by=actor_row.actor_user_id WHERE id=category_row.id
  RETURNING id, app.expense_categories.code::text, app.expense_categories.name::text, app.expense_categories.is_active, app.expense_categories.version_number INTO expense_category_id, code, name, is_active, version_number;
  PERFORM set_config('app.expense_category_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'expense_category_updated', 'expense_category', expense_category_id, NULL, 'success', jsonb_build_object('code', category_row.code, 'version_number', category_row.version_number), jsonb_build_object('code', code, 'is_active', is_active, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.expense_category_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate expense category.';
WHEN OTHERS THEN PERFORM set_config('app.expense_category_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_project_expense(p_actor_auth_subject uuid, p_project_id uuid, p_expense_category_id uuid, p_amount numeric, p_currency_code char(3), p_paid_from_account_id uuid, p_expense_date date, p_vendor_name text DEFAULT NULL, p_vendor_reference text DEFAULT NULL, p_description text DEFAULT NULL, p_private_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_expense_id uuid, expense_number text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; project_row app.projects%ROWTYPE; category_row app.expense_categories%ROWTYPE; account_row app.financial_accounts%ROWTYPE; normalized_reference text := app.normalize_project_expense_vendor_reference(p_vendor_reference); generated_number text := 'EXP-' || lpad(nextval('app.project_expense_number_seq')::text, 6, '0'); fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO project_row FROM app.projects WHERE id=p_project_id FOR UPDATE;
  SELECT * INTO category_row FROM app.expense_categories WHERE id=p_expense_category_id FOR UPDATE;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=p_paid_from_account_id FOR UPDATE;
  IF project_row.id IS NULL OR project_row.archived_at IS NOT NULL OR category_row.id IS NULL OR NOT category_row.is_active OR account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR p_amount IS NULL OR p_amount <= 0 OR p_currency_code IS NULL OR p_expense_date IS NULL OR NULLIF(btrim(p_description),'') IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid project expense.'; END IF;
  IF account_row.currency_code IS DISTINCT FROM p_currency_code OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=p_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid project expense.'; END IF;
  IF normalized_reference IS NOT NULL AND EXISTS (SELECT 1 FROM app.project_expenses pe JOIN app.financial_events fe ON fe.id=pe.financial_event_id WHERE pe.project_id=project_row.id AND pe.expense_date=p_expense_date AND pe.currency_code=p_currency_code AND pe.amount=p_amount::numeric(20,6) AND pe.vendor_reference=normalized_reference AND fe.status <> 'REJECTED') THEN RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate project expense.'; END IF;
  fp := app.project_expense_duplicate_fingerprint(project_row.id,p_currency_code,p_expense_date,p_amount,normalized_reference,generated_number);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  INSERT INTO app.financial_events (event_type, project_id, client_id, event_date, status, description, duplicate_fingerprint, created_by, updated_by)
  VALUES ('PROJECT_EXPENSE', project_row.id, project_row.client_id, p_expense_date, 'DRAFT', btrim(p_description), fp, actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id, app.financial_events.event_number, app.financial_events.version_number INTO financial_event_id, event_number, version_number;
  INSERT INTO app.financial_transactions (financial_event_id, transaction_date, status, reporting_currency_code, description, created_by)
  VALUES (financial_event_id, p_expense_date, 'DRAFT', project_row.reporting_currency_code, btrim(p_description), actor_row.actor_user_id)
  RETURNING id, app.financial_transactions.transaction_number INTO financial_transaction_id, transaction_number;
  INSERT INTO app.project_expenses (financial_event_id, project_id, expense_number, expense_category_id, amount, currency_code, paid_from_account_id, expense_date, vendor_name, vendor_reference, description, private_notes)
  VALUES (financial_event_id, project_row.id, generated_number, category_row.id, p_amount::numeric(20,6), p_currency_code, account_row.id, p_expense_date, NULLIF(btrim(p_vendor_name), '')::varchar(200), normalized_reference::varchar(120), btrim(p_description), app.normalize_financial_optional_text(p_private_notes))
  RETURNING id, app.project_expenses.expense_number::text INTO project_expense_id, expense_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_expense_created', 'financial_event', financial_event_id, project_row.id, 'success', '{}'::jsonb, jsonb_build_object('expense_number', expense_number, 'status','DRAFT','project_id',project_row.id,'currency_code',p_currency_code,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate project expense.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_project_expense(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_project_id uuid, p_expense_category_id uuid, p_amount numeric, p_currency_code char(3), p_paid_from_account_id uuid, p_expense_date date, p_vendor_name text DEFAULT NULL, p_vendor_reference text DEFAULT NULL, p_description text DEFAULT NULL, p_private_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, project_expense_id uuid, expense_number text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; expense_row app.project_expenses%ROWTYPE; project_row app.projects%ROWTYPE; category_row app.expense_categories%ROWTYPE; account_row app.financial_accounts%ROWTYPE; normalized_reference text := app.normalize_project_expense_vendor_reference(p_vendor_reference); fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions AS ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO expense_row FROM app.project_expenses AS pe WHERE pe.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO project_row FROM app.projects WHERE id=p_project_id FOR UPDATE;
  SELECT * INTO category_row FROM app.expense_categories WHERE id=p_expense_category_id FOR UPDATE;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=p_paid_from_account_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR expense_row.id IS NULL OR event_row.event_type <> 'PROJECT_EXPENSE' OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Project expense cannot be updated.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Project expense version conflict.'; END IF;
  IF project_row.id IS NULL OR project_row.archived_at IS NOT NULL OR category_row.id IS NULL OR NOT category_row.is_active OR account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR p_amount IS NULL OR p_amount <= 0 OR p_currency_code IS NULL OR p_expense_date IS NULL OR NULLIF(btrim(p_description),'') IS NULL OR account_row.currency_code IS DISTINCT FROM p_currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid project expense.'; END IF;
  IF normalized_reference IS NOT NULL AND EXISTS (SELECT 1 FROM app.project_expenses pe JOIN app.financial_events fe ON fe.id=pe.financial_event_id WHERE pe.id <> expense_row.id AND pe.project_id=project_row.id AND pe.expense_date=p_expense_date AND pe.currency_code=p_currency_code AND pe.amount=p_amount::numeric(20,6) AND pe.vendor_reference=normalized_reference AND fe.status <> 'REJECTED') THEN RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate project expense.'; END IF;
  fp := app.project_expense_duplicate_fingerprint(project_row.id,p_currency_code,p_expense_date,p_amount,normalized_reference,expense_row.expense_number);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET project_id=project_row.id, client_id=project_row.client_id, event_date=p_expense_date, description=btrim(p_description), duplicate_fingerprint=fp, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.version_number INTO financial_event_id, version_number;
  UPDATE app.financial_transactions SET transaction_date=p_expense_date, reporting_currency_code=project_row.reporting_currency_code, description=btrim(p_description) WHERE id=transaction_row.id RETURNING id INTO financial_transaction_id;
  UPDATE app.project_expenses SET project_id=project_row.id, expense_category_id=category_row.id, amount=p_amount::numeric(20,6), currency_code=p_currency_code, paid_from_account_id=account_row.id, expense_date=p_expense_date, vendor_name=NULLIF(btrim(p_vendor_name),'')::varchar(200), vendor_reference=normalized_reference::varchar(120), description=btrim(p_description), private_notes=app.normalize_financial_optional_text(p_private_notes) WHERE id=expense_row.id RETURNING id, app.project_expenses.expense_number::text INTO project_expense_id, expense_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_expense_updated', 'financial_event', financial_event_id, project_row.id, 'success', jsonb_build_object('version_number',event_row.version_number), jsonb_build_object('expense_number',expense_number,'version_number',version_number,'project_id',project_row.id,'currency_code',p_currency_code), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate project expense.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_submit_project_expense(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; expense_row app.project_expenses%ROWTYPE; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE; SELECT * INTO expense_row FROM app.project_expenses AS pe WHERE pe.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR expense_row.id IS NULL OR event_row.event_type <> 'PROJECT_EXPENSE' OR event_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Project expense cannot be submitted.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Project expense version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='SUBMITTED', submitted_at=now(), submitted_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='SUBMITTED' WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_expense_submitted', 'financial_event', financial_event_id, expense_row.project_id, 'success', jsonb_build_object('status','DRAFT','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number,'expense_number',expense_row.expense_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_reject_project_expense(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; expense_row app.project_expenses%ROWTYPE; reason_text text := btrim(coalesce(p_rejection_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  IF reason_text='' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Rejection reason is required.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE; SELECT * INTO expense_row FROM app.project_expenses AS pe WHERE pe.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR expense_row.id IS NULL OR event_row.event_type <> 'PROJECT_EXPENSE' OR event_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Project expense cannot be rejected.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Project expense version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_expense_rejected', 'financial_event', financial_event_id, expense_row.project_id, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',status,'version_number',version_number,'expense_number',expense_row.expense_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided',true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_approve_project_expense(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; expense_row app.project_expenses%ROWTYPE; account_row app.financial_accounts%ROWTYPE; asset_ledger_row app.ledger_accounts%ROWTYPE; control_ledger_row app.ledger_accounts%ROWTYPE; control_ledger_id uuid; chosen_rate app.exchange_rates%ROWTYPE; converted_amount numeric; rounded_amount numeric; rounding_delta numeric; reporting_digits integer; previous_financial_context text := current_setting('app.financial_transaction_context', true); previous_posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE; SELECT * INTO transaction_row FROM app.financial_transactions AS ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE; SELECT * INTO expense_row FROM app.project_expenses AS pe WHERE pe.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR expense_row.id IS NULL OR event_row.event_type <> 'PROJECT_EXPENSE' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Project expense cannot be approved.'; END IF;
  IF event_row.status='APPROVED' AND transaction_row.status='POSTED' THEN financial_event_id:=event_row.id; financial_transaction_id:=transaction_row.id; event_status:=event_row.status::text; transaction_status:=transaction_row.status::text; ledger_entry_count:=(SELECT count(*)::integer FROM app.ledger_entries WHERE app.ledger_entries.financial_transaction_id=transaction_row.id); version_number:=event_row.version_number; RETURN NEXT; RETURN; END IF;
  IF event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Project expense cannot be approved.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Project expense version conflict.'; END IF;
  IF event_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Project expense requires different Owner approval.'; END IF;
  SELECT * INTO account_row FROM app.financial_accounts WHERE id=expense_row.paid_from_account_id FOR UPDATE; SELECT * INTO asset_ledger_row FROM app.ledger_accounts WHERE financial_account_id=account_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE;
  IF account_row.id IS NULL OR NOT account_row.is_active OR account_row.archived_at IS NOT NULL OR asset_ledger_row.id IS NULL OR NOT asset_ledger_row.is_active OR expense_row.amount <= 0 OR expense_row.currency_code IS DISTINCT FROM account_row.currency_code OR expense_row.currency_code IS DISTINCT FROM asset_ledger_row.currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid project expense.'; END IF;
  SELECT decimal_digits INTO reporting_digits FROM app.currencies WHERE code=transaction_row.reporting_currency_code; IF reporting_digits IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid project expense.'; END IF;
  IF expense_row.currency_code = transaction_row.reporting_currency_code THEN converted_amount:=expense_row.amount; rounded_amount:=round(converted_amount, reporting_digits); rounding_delta:=abs(converted_amount-rounded_amount); ELSE SELECT * INTO chosen_rate FROM app.exchange_rates er WHERE er.rate_date=transaction_row.transaction_date AND ((er.base_currency_code=expense_row.currency_code AND er.quote_currency_code=transaction_row.reporting_currency_code) OR (er.quote_currency_code=expense_row.currency_code AND er.base_currency_code=transaction_row.reporting_currency_code)) ORDER BY er.created_at DESC, er.id DESC LIMIT 1; IF chosen_rate.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Transaction-date exchange rate is required.'; END IF; converted_amount:=app.convert_amount_with_exchange_rate(expense_row.amount,expense_row.currency_code,transaction_row.reporting_currency_code,chosen_rate.base_currency_code,chosen_rate.quote_currency_code,chosen_rate.rate_value); rounded_amount:=round(converted_amount, reporting_digits); rounding_delta:=abs(converted_amount-rounded_amount); END IF;
  control_ledger_id := app.ensure_project_expense_control_ledger_account(expense_row.currency_code); SELECT * INTO control_ledger_row FROM app.ledger_accounts WHERE id=control_ledger_id FOR UPDATE;
  PERFORM set_config('app.ledger_posting_context','project_expense_posting',true);
  INSERT INTO app.ledger_entries (financial_transaction_id,line_no,ledger_account_id,project_id,client_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,exchange_rate_id,rate_base_currency_code,rate_quote_currency_code,rate_value,rate_source,rounding_adjustment,memo,created_by)
  VALUES (transaction_row.id,1,control_ledger_row.id,expense_row.project_id,event_row.client_id,expense_row.currency_code,expense_row.amount,0,transaction_row.reporting_currency_code,rounded_amount,0,chosen_rate.id,chosen_rate.base_currency_code,chosen_rate.quote_currency_code,chosen_rate.rate_value,chosen_rate.source,rounding_delta,'Project expense debit',actor_row.actor_user_id),
         (transaction_row.id,2,asset_ledger_row.id,expense_row.project_id,event_row.client_id,expense_row.currency_code,0,expense_row.amount,transaction_row.reporting_currency_code,0,rounded_amount,chosen_rate.id,chosen_rate.base_currency_code,chosen_rate.quote_currency_code,chosen_rate.rate_value,chosen_rate.source,rounding_delta,'Project expense credit',actor_row.actor_user_id);
  PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_transactions SET status='POSTED', approved_at=now(), approved_by=actor_row.actor_user_id, posted_at=now(), posted_by=actor_row.actor_user_id WHERE id=transaction_row.id RETURNING id, app.financial_transactions.status::text INTO financial_transaction_id, transaction_status;
  UPDATE app.financial_events SET status='APPROVED', approved_at=now(), approved_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=event_row.id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, event_status, version_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'project_expense_approved', 'financial_event', financial_event_id, expense_row.project_id, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('status',event_status,'version_number',version_number,'expense_number',expense_row.expense_number,'ledger_entry_count',2), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  ledger_entry_count:=2; RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true); PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_project_expense_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (project_expense_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, expense_number text, project_id uuid, expense_category_id uuid, amount numeric, currency_code char(3), paid_from_account_id uuid, expense_date date, vendor_reference text, event_status text, transaction_status text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pe.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, pe.expense_number::text, pe.project_id, pe.expense_category_id, pe.amount, pe.currency_code, pe.paid_from_account_id, pe.expense_date, pe.vendor_reference::text, fe.status::text, ft.status::text, fe.version_number FROM app.project_expenses pe JOIN app.financial_events fe ON fe.id=pe.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id ORDER BY fe.created_at DESC, fe.id DESC LIMIT safe_limit OFFSET safe_offset;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_project_expense_detail(p_actor_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (project_expense_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, expense_number text, project_id uuid, expense_category_id uuid, amount numeric, currency_code char(3), paid_from_account_id uuid, expense_date date, vendor_name text, vendor_reference text, description text, private_notes text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pe.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, pe.expense_number::text, pe.project_id, pe.expense_category_id, pe.amount, pe.currency_code, pe.paid_from_account_id, pe.expense_date, pe.vendor_name::text, pe.vendor_reference::text, pe.description, pe.private_notes, ft.reporting_currency_code, fe.status::text, ft.status::text, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number FROM app.project_expenses pe JOIN app.financial_events fe ON fe.id=pe.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.id=p_financial_event_id AND fe.event_type='PROJECT_EXPENSE';
END $function$;

CREATE OR REPLACE FUNCTION app.owner_project_expense_totals(p_actor_auth_subject uuid, p_project_id uuid)
RETURNS TABLE (project_id uuid, currency_code char(3), total_expensed numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT le.project_id, le.currency_code, coalesce(sum(le.debit_amount),0)::numeric FROM app.ledger_entries le JOIN app.financial_transactions ft ON ft.id=le.financial_transaction_id AND ft.status='POSTED' JOIN app.financial_events fe ON fe.id=ft.financial_event_id AND fe.event_type='PROJECT_EXPENSE' JOIN app.ledger_accounts la ON la.id=le.ledger_account_id AND la.code='CTRL-PROJECT-EXPENSE-' || le.currency_code::text WHERE le.project_id=p_project_id AND le.debit_amount > 0 GROUP BY le.project_id, le.currency_code ORDER BY le.currency_code;
END $function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_expense_category(p_verified_owner_auth_subject uuid, p_code text, p_name text, p_description text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (expense_category_id uuid, code text, name text, is_active boolean, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_expense_category(p_verified_owner_auth_subject,p_code,p_name,p_description,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_expense_category(p_verified_owner_auth_subject uuid, p_expense_category_id uuid, p_expected_version_number integer, p_name text, p_description text DEFAULT NULL, p_is_active boolean DEFAULT true, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (expense_category_id uuid, code text, name text, is_active boolean, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_expense_category(p_verified_owner_auth_subject,p_expense_category_id,p_expected_version_number,p_name,p_description,p_is_active,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_create_project_expense(p_verified_owner_auth_subject uuid, p_project_id uuid, p_expense_category_id uuid, p_amount numeric, p_currency_code char(3), p_paid_from_account_id uuid, p_expense_date date, p_vendor_name text DEFAULT NULL, p_vendor_reference text DEFAULT NULL, p_description text DEFAULT NULL, p_private_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, project_expense_id uuid, expense_number text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_project_expense(p_verified_owner_auth_subject,p_project_id,p_expense_category_id,p_amount,p_currency_code,p_paid_from_account_id,p_expense_date,p_vendor_name,p_vendor_reference,p_description,p_private_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_project_expense(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_project_id uuid, p_expense_category_id uuid, p_amount numeric, p_currency_code char(3), p_paid_from_account_id uuid, p_expense_date date, p_vendor_name text DEFAULT NULL, p_vendor_reference text DEFAULT NULL, p_description text DEFAULT NULL, p_private_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, project_expense_id uuid, expense_number text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_project_expense(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_project_id,p_expense_category_id,p_amount,p_currency_code,p_paid_from_account_id,p_expense_date,p_vendor_name,p_vendor_reference,p_description,p_private_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_submit_project_expense(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_project_expense(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_project_expense(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_project_expense(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_project_expense(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_project_expense(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_project_expense_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (project_expense_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, expense_number text, project_id uuid, expense_category_id uuid, amount numeric, currency_code char(3), paid_from_account_id uuid, expense_date date, vendor_reference text, event_status text, transaction_status text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_project_expense_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_project_expense_detail(p_verified_owner_auth_subject uuid, p_financial_event_id uuid) RETURNS TABLE (project_expense_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, expense_number text, project_id uuid, expense_category_id uuid, amount numeric, currency_code char(3), paid_from_account_id uuid, expense_date date, vendor_name text, vendor_reference text, description text, private_notes text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_project_expense_detail(p_verified_owner_auth_subject,p_financial_event_id); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_project_expense_totals(p_verified_owner_auth_subject uuid, p_project_id uuid) RETURNS TABLE (project_id uuid, currency_code char(3), total_expensed numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_project_expense_totals(p_verified_owner_auth_subject,p_project_id); $function$;

CREATE OR REPLACE FUNCTION app.ledger_entries_trusted_insert_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE transaction_row app.financial_transactions%ROWTYPE; ledger_row app.ledger_accounts%ROWTYPE; posting_context text := coalesce(current_setting('app.ledger_posting_context', true), '');
BEGIN
  IF posting_context NOT IN ('opening_balance_posting','financial_reversal_posting','financial_adjustment_posting','client_payment_posting','project_expense_posting') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries require trusted posting.'; END IF;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE id = NEW.financial_transaction_id; SELECT * INTO ledger_row FROM app.ledger_accounts WHERE id = NEW.ledger_account_id;
  IF transaction_row.id IS NULL OR ledger_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid ledger entry.'; END IF;
  IF NEW.currency_code IS DISTINCT FROM ledger_row.currency_code THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry currency must match ledger account currency.'; END IF;
  IF NEW.reporting_currency_code IS DISTINCT FROM transaction_row.reporting_currency_code THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry reporting currency must match transaction.'; END IF;
  RETURN NEW;
END $function$;

COMMIT;
