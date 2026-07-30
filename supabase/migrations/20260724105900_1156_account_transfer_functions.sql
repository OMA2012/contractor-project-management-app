BEGIN;

CREATE OR REPLACE FUNCTION app.normalize_account_transfer_reference(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT upper(NULLIF(btrim(p_value), ''));
$function$;

CREATE OR REPLACE FUNCTION app.account_transfer_duplicate_fingerprint(p_source_account_id uuid, p_destination_account_id uuid, p_currency_code char(3), p_transfer_date date, p_amount numeric, p_reference text, p_event_number text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT 'ACCOUNT_TRANSFER|source=' || p_source_account_id::text || '|destination=' || p_destination_account_id::text || '|currency=' || p_currency_code::text || '|date=' || p_transfer_date::text || '|amount=' || p_amount::numeric(20,6)::text || CASE WHEN app.normalize_account_transfer_reference(p_reference) IS NULL THEN '|event_number=' || p_event_number ELSE '|reference=' || app.normalize_account_transfer_reference(p_reference) END;
$function$;

CREATE OR REPLACE FUNCTION app.account_transfer_validate_accounts(p_source_account_id uuid, p_destination_account_id uuid, p_currency_code char(3), p_require_asset_ledgers boolean DEFAULT false)
RETURNS TABLE (source_account_id uuid, destination_account_id uuid, source_ledger_account_id uuid, destination_ledger_account_id uuid)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE source_row app.financial_accounts%ROWTYPE; destination_row app.financial_accounts%ROWTYPE; source_ledger app.ledger_accounts%ROWTYPE; destination_ledger app.ledger_accounts%ROWTYPE;
BEGIN
  IF p_source_account_id IS NULL OR p_destination_account_id IS NULL OR p_source_account_id = p_destination_account_id OR p_currency_code IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  SELECT * INTO source_row FROM app.financial_accounts WHERE id=p_source_account_id FOR UPDATE;
  SELECT * INTO destination_row FROM app.financial_accounts WHERE id=p_destination_account_id FOR UPDATE;
  IF source_row.id IS NULL OR destination_row.id IS NULL OR NOT source_row.is_active OR source_row.archived_at IS NOT NULL OR NOT destination_row.is_active OR destination_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  IF source_row.currency_code IS DISTINCT FROM p_currency_code OR destination_row.currency_code IS DISTINCT FROM p_currency_code OR source_row.currency_code IS DISTINCT FROM destination_row.currency_code OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=p_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  IF p_require_asset_ledgers THEN
    SELECT * INTO source_ledger FROM app.ledger_accounts WHERE financial_account_id=source_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE;
    SELECT * INTO destination_ledger FROM app.ledger_accounts WHERE financial_account_id=destination_row.id AND account_kind='FINANCIAL_ASSET' FOR UPDATE;
    IF source_ledger.id IS NULL OR destination_ledger.id IS NULL OR NOT source_ledger.is_active OR NOT destination_ledger.is_active OR source_ledger.currency_code IS DISTINCT FROM p_currency_code OR destination_ledger.currency_code IS DISTINCT FROM p_currency_code THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  END IF;
  source_account_id := source_row.id; destination_account_id := destination_row.id; source_ledger_account_id := source_ledger.id; destination_ledger_account_id := destination_ledger.id; RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_create_account_transfer(p_actor_auth_subject uuid, p_source_account_id uuid, p_destination_account_id uuid, p_amount numeric, p_currency_code char(3), p_transfer_date date, p_reference text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; contractor_row app.contractor_profiles%ROWTYPE; account_pair record; normalized_reference text := app.normalize_account_transfer_reference(p_reference); generated_event_number text := 'FE-' || lpad(nextval('app.financial_event_number_seq')::text, 6, '0'); fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO contractor_row FROM app.contractor_profiles ORDER BY created_at, id LIMIT 1 FOR UPDATE;
  IF contractor_row.id IS NULL OR contractor_row.default_reporting_currency_code IS NULL OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=contractor_row.default_reporting_currency_code AND is_active) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Valid contractor reporting currency is required.'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_transfer_date IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  SELECT * INTO account_pair FROM app.account_transfer_validate_accounts(p_source_account_id,p_destination_account_id,p_currency_code,false);
  fp := app.account_transfer_duplicate_fingerprint(account_pair.source_account_id,account_pair.destination_account_id,p_currency_code,p_transfer_date,p_amount,normalized_reference,generated_event_number);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  INSERT INTO app.financial_events (event_number, event_type, project_id, client_id, event_date, status, description, duplicate_fingerprint, created_by, updated_by)
  VALUES (generated_event_number, 'ACCOUNT_TRANSFER', NULL, NULL, p_transfer_date, 'DRAFT', normalized_reference, fp, actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id, app.financial_events.event_number, app.financial_events.version_number INTO financial_event_id, event_number, version_number;
  INSERT INTO app.financial_transactions (financial_event_id, transaction_date, status, reporting_currency_code, description, created_by)
  VALUES (financial_event_id, p_transfer_date, 'DRAFT', contractor_row.default_reporting_currency_code, normalized_reference, actor_row.actor_user_id)
  RETURNING id, app.financial_transactions.transaction_number INTO financial_transaction_id, transaction_number;
  INSERT INTO app.account_transfers (financial_event_id, source_account_id, destination_account_id, amount, currency_code, transfer_date, reference, notes)
  VALUES (financial_event_id, account_pair.source_account_id, account_pair.destination_account_id, p_amount::numeric(20,6), p_currency_code, p_transfer_date, normalized_reference::varchar(120), app.normalize_financial_optional_text(p_notes))
  RETURNING id INTO account_transfer_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'account_transfer_created', 'financial_event', financial_event_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('account_transfer_id',account_transfer_id,'event_number',event_number,'transaction_number',transaction_number,'source_account_id',account_pair.source_account_id,'destination_account_id',account_pair.destination_account_id,'currency_code',p_currency_code,'amount',p_amount::numeric(20,6),'status','DRAFT','version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate account transfer.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_update_account_transfer(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_source_account_id uuid, p_destination_account_id uuid, p_amount numeric, p_currency_code char(3), p_transfer_date date, p_reference text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, financial_transaction_id uuid, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; transfer_row app.account_transfers%ROWTYPE; account_pair record; normalized_reference text := app.normalize_account_transfer_reference(p_reference); fp text; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transfer_row FROM app.account_transfers at WHERE at.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR transfer_row.id IS NULL OR event_row.event_type <> 'ACCOUNT_TRANSFER' OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Account transfer cannot be updated.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Account transfer version conflict.'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_transfer_date IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  SELECT * INTO account_pair FROM app.account_transfer_validate_accounts(p_source_account_id,p_destination_account_id,p_currency_code,false);
  fp := app.account_transfer_duplicate_fingerprint(account_pair.source_account_id,account_pair.destination_account_id,p_currency_code,p_transfer_date,p_amount,normalized_reference,event_row.event_number::text);
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET event_date=p_transfer_date, description=normalized_reference, duplicate_fingerprint=fp, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.version_number INTO financial_event_id, version_number;
  UPDATE app.financial_transactions SET transaction_date=p_transfer_date, description=normalized_reference WHERE id=transaction_row.id RETURNING id INTO financial_transaction_id;
  UPDATE app.account_transfers SET source_account_id=account_pair.source_account_id, destination_account_id=account_pair.destination_account_id, amount=p_amount::numeric(20,6), currency_code=p_currency_code, transfer_date=p_transfer_date, reference=normalized_reference::varchar(120), notes=app.normalize_financial_optional_text(p_notes) WHERE id=transfer_row.id RETURNING id INTO account_transfer_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'account_transfer_updated', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('version_number',event_row.version_number), jsonb_build_object('account_transfer_id',account_transfer_id,'version_number',version_number,'source_account_id',account_pair.source_account_id,'destination_account_id',account_pair.destination_account_id,'currency_code',p_currency_code,'amount',p_amount::numeric(20,6)), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate account transfer.';
WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_submit_account_transfer(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; transfer_row app.account_transfers%ROWTYPE; previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transfer_row FROM app.account_transfers at WHERE at.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR transfer_row.id IS NULL OR event_row.event_type <> 'ACCOUNT_TRANSFER' OR event_row.status <> 'DRAFT' OR transaction_row.status <> 'DRAFT' OR event_row.project_id IS NOT NULL OR event_row.client_id IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Account transfer cannot be submitted.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Account transfer version conflict.'; END IF;
  PERFORM app.account_transfer_validate_accounts(transfer_row.source_account_id,transfer_row.destination_account_id,transfer_row.currency_code,true);
  IF transfer_row.transfer_date IS DISTINCT FROM event_row.event_date OR event_row.event_date IS DISTINCT FROM transaction_row.transaction_date THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='SUBMITTED', submitted_at=now(), submitted_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='SUBMITTED' WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'account_transfer_submitted', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','DRAFT','version_number',event_row.version_number), jsonb_build_object('account_transfer_id',transfer_row.id,'status',status,'version_number',version_number,'source_account_id',transfer_row.source_account_id,'destination_account_id',transfer_row.destination_account_id,'currency_code',transfer_row.currency_code,'amount',transfer_row.amount), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_reject_account_transfer(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, status text, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transfer_row app.account_transfers%ROWTYPE; reason_text text := btrim(coalesce(p_rejection_reason,'')); previous_context text := current_setting('app.financial_transaction_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Rejection reason is required.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transfer_row FROM app.account_transfers at WHERE at.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transfer_row.id IS NULL OR event_row.event_type <> 'ACCOUNT_TRANSFER' OR event_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Account transfer cannot be rejected.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Account transfer version conflict.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_events SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text, updated_by=actor_row.actor_user_id WHERE id=p_financial_event_id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, status, version_number;
  UPDATE app.financial_transactions SET status='REJECTED', rejected_at=now(), rejected_by=actor_row.actor_user_id, rejection_reason=reason_text WHERE app.financial_transactions.financial_event_id=p_financial_event_id;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'account_transfer_rejected', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('account_transfer_id',transfer_row.id,'status',status,'version_number',version_number,'source_account_id',transfer_row.source_account_id,'destination_account_id',transfer_row.destination_account_id,'currency_code',transfer_row.currency_code,'amount',transfer_row.amount), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided',true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.financial_transaction_context',coalesce(previous_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_approve_account_transfer(p_actor_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor_row record; event_row app.financial_events%ROWTYPE; transaction_row app.financial_transactions%ROWTYPE; transfer_row app.account_transfers%ROWTYPE; account_pair record; snap record; previous_financial_context text := current_setting('app.financial_transaction_context', true); previous_posting_context text := current_setting('app.ledger_posting_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject); IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO event_row FROM app.financial_events WHERE id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transaction_row FROM app.financial_transactions ft WHERE ft.financial_event_id=p_financial_event_id FOR UPDATE;
  SELECT * INTO transfer_row FROM app.account_transfers at WHERE at.financial_event_id=p_financial_event_id FOR UPDATE;
  IF event_row.id IS NULL OR transaction_row.id IS NULL OR transfer_row.id IS NULL OR event_row.event_type <> 'ACCOUNT_TRANSFER' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Account transfer cannot be approved.'; END IF;
  IF event_row.status='APPROVED' AND transaction_row.status='POSTED' THEN financial_event_id:=event_row.id; financial_transaction_id:=transaction_row.id; event_status:=event_row.status::text; transaction_status:=transaction_row.status::text; ledger_entry_count:=(SELECT count(*)::integer FROM app.ledger_entries WHERE app.ledger_entries.financial_transaction_id=transaction_row.id); version_number:=event_row.version_number; RETURN NEXT; RETURN; END IF;
  IF event_row.status <> 'SUBMITTED' OR transaction_row.status <> 'SUBMITTED' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Account transfer cannot be approved.'; END IF;
  IF event_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Account transfer version conflict.'; END IF;
  IF event_row.created_by = actor_row.actor_user_id THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Account transfer requires different Owner approval.'; END IF;
  IF event_row.project_id IS NOT NULL OR event_row.client_id IS NOT NULL OR transfer_row.transfer_date IS DISTINCT FROM event_row.event_date OR event_row.event_date IS DISTINCT FROM transaction_row.transaction_date THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid account transfer.'; END IF;
  SELECT * INTO account_pair FROM app.account_transfer_validate_accounts(transfer_row.source_account_id,transfer_row.destination_account_id,transfer_row.currency_code,true);
  SELECT * INTO snap FROM app.financial_transaction_reporting_snapshot(transfer_row.amount,transfer_row.currency_code,transaction_row.reporting_currency_code,transaction_row.transaction_date);
  PERFORM set_config('app.ledger_posting_context','account_transfer_posting',true);
  INSERT INTO app.ledger_entries (financial_transaction_id,line_no,ledger_account_id,project_id,client_id,currency_code,debit_amount,credit_amount,reporting_currency_code,reporting_debit_amount,reporting_credit_amount,exchange_rate_id,rate_base_currency_code,rate_quote_currency_code,rate_value,rate_source,rounding_adjustment,memo,created_by)
  VALUES (transaction_row.id,1,account_pair.destination_ledger_account_id,NULL,NULL,transfer_row.currency_code,transfer_row.amount,0,transaction_row.reporting_currency_code,snap.reporting_amount,0,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Account transfer destination debit',actor_row.actor_user_id),
         (transaction_row.id,2,account_pair.source_ledger_account_id,NULL,NULL,transfer_row.currency_code,0,transfer_row.amount,transaction_row.reporting_currency_code,0,snap.reporting_amount,snap.exchange_rate_id,snap.rate_base_currency_code,snap.rate_quote_currency_code,snap.rate_value,snap.rate_source,snap.rounding_adjustment,'Account transfer source credit',actor_row.actor_user_id);
  PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true);
  IF EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY currency_code HAVING sum(debit_amount)<>sum(credit_amount)) OR EXISTS (SELECT 1 FROM app.ledger_entries le WHERE le.financial_transaction_id=transaction_row.id GROUP BY reporting_currency_code HAVING sum(reporting_debit_amount)<>sum(reporting_credit_amount)) THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Ledger entries do not balance.'; END IF;
  PERFORM set_config('app.financial_transaction_context','owner_financial_mutation',true);
  UPDATE app.financial_transactions SET status='POSTED', approved_at=now(), approved_by=actor_row.actor_user_id, posted_at=now(), posted_by=actor_row.actor_user_id WHERE id=transaction_row.id RETURNING id, app.financial_transactions.status::text INTO financial_transaction_id, transaction_status;
  UPDATE app.financial_events SET status='APPROVED', approved_at=now(), approved_by=actor_row.actor_user_id, updated_by=actor_row.actor_user_id WHERE id=event_row.id RETURNING id, app.financial_events.status::text, app.financial_events.version_number INTO financial_event_id, event_status, version_number;
  PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true);
  ledger_entry_count := 2;
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'account_transfer_approved', 'financial_event', financial_event_id, NULL, 'success', jsonb_build_object('status','SUBMITTED','version_number',event_row.version_number), jsonb_build_object('account_transfer_id',transfer_row.id,'status',event_status,'version_number',version_number,'source_account_id',transfer_row.source_account_id,'destination_account_id',transfer_row.destination_account_id,'currency_code',transfer_row.currency_code,'amount',transfer_row.amount,'ledger_entry_count',2), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'account_transfer_transaction_posted', 'financial_transaction', financial_transaction_id, NULL, 'success', jsonb_build_object('status','SUBMITTED'), jsonb_build_object('account_transfer_id',transfer_row.id,'status',transaction_status,'ledger_entry_count',2,'source_account_id',transfer_row.source_account_id,'destination_account_id',transfer_row.destination_account_id,'currency_code',transfer_row.currency_code,'amount',transfer_row.amount), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN unique_violation THEN PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true); PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true); RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Duplicate account transfer posting.';
WHEN OTHERS THEN PERFORM set_config('app.ledger_posting_context',coalesce(previous_posting_context,''),true); PERFORM set_config('app.financial_transaction_context',coalesce(previous_financial_context,''),true); RAISE;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_account_transfer_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, source_account_id uuid, destination_account_id uuid, amount numeric, currency_code char(3), transfer_date date, event_status text, transaction_status text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT at.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, at.source_account_id, at.destination_account_id, at.amount, at.currency_code, at.transfer_date, fe.status::text, ft.status::text, fe.version_number FROM app.account_transfers at JOIN app.financial_events fe ON fe.id=at.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.event_type='ACCOUNT_TRANSFER' ORDER BY fe.created_at DESC, fe.id DESC LIMIT safe_limit OFFSET safe_offset;
END $function$;

CREATE OR REPLACE FUNCTION app.owner_account_transfer_detail(p_actor_auth_subject uuid, p_financial_event_id uuid)
RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, source_account_id uuid, destination_account_id uuid, amount numeric, currency_code char(3), transfer_date date, reference text, notes text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT at.id, fe.id, fe.event_number::text, ft.id, ft.transaction_number::text, at.source_account_id, at.destination_account_id, at.amount, at.currency_code, at.transfer_date, at.reference::text, at.notes, ft.reporting_currency_code, fe.status::text, ft.status::text, fe.submitted_at, fe.approved_at, fe.rejected_at, fe.rejection_reason, fe.version_number FROM app.account_transfers at JOIN app.financial_events fe ON fe.id=at.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id=fe.id WHERE fe.id=p_financial_event_id AND fe.event_type='ACCOUNT_TRANSFER';
END $function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_account_transfer(p_verified_owner_auth_subject uuid, p_source_account_id uuid, p_destination_account_id uuid, p_amount numeric, p_currency_code char(3), p_transfer_date date, p_reference text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_account_transfer(p_verified_owner_auth_subject,p_source_account_id,p_destination_account_id,p_amount,p_currency_code,p_transfer_date,p_reference,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_account_transfer(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_source_account_id uuid, p_destination_account_id uuid, p_amount numeric, p_currency_code char(3), p_transfer_date date, p_reference text DEFAULT NULL, p_notes text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, financial_transaction_id uuid, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_account_transfer(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_source_account_id,p_destination_account_id,p_amount,p_currency_code,p_transfer_date,p_reference,p_notes,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_submit_account_transfer(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_submit_account_transfer(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_reject_account_transfer(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_rejection_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, status text, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_reject_account_transfer(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_rejection_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_approve_account_transfer(p_verified_owner_auth_subject uuid, p_financial_event_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (financial_event_id uuid, financial_transaction_id uuid, event_status text, transaction_status text, ledger_entry_count integer, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_approve_account_transfer(p_verified_owner_auth_subject,p_financial_event_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_account_transfer_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, source_account_id uuid, destination_account_id uuid, amount numeric, currency_code char(3), transfer_date date, event_status text, transaction_status text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_account_transfer_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_account_transfer_detail(p_verified_owner_auth_subject uuid, p_financial_event_id uuid) RETURNS TABLE (account_transfer_id uuid, financial_event_id uuid, event_number text, financial_transaction_id uuid, transaction_number text, source_account_id uuid, destination_account_id uuid, amount numeric, currency_code char(3), transfer_date date, reference text, notes text, reporting_currency_code char(3), event_status text, transaction_status text, submitted_at timestamptz, approved_at timestamptz, rejected_at timestamptz, rejection_reason text, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_account_transfer_detail(p_verified_owner_auth_subject,p_financial_event_id); $function$;

CREATE OR REPLACE FUNCTION app.ledger_entries_trusted_insert_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE transaction_row app.financial_transactions%ROWTYPE; ledger_row app.ledger_accounts%ROWTYPE; posting_context text := coalesce(current_setting('app.ledger_posting_context', true), '');
BEGIN
  IF posting_context NOT IN ('opening_balance_posting','financial_reversal_posting','financial_adjustment_posting','client_payment_posting','project_expense_posting','account_transfer_posting') THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entries require trusted posting.'; END IF;
  SELECT * INTO transaction_row FROM app.financial_transactions WHERE id = NEW.financial_transaction_id; SELECT * INTO ledger_row FROM app.ledger_accounts WHERE id = NEW.ledger_account_id;
  IF transaction_row.id IS NULL OR ledger_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid ledger entry.'; END IF;
  IF NEW.currency_code IS DISTINCT FROM ledger_row.currency_code THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry currency must match ledger account currency.'; END IF;
  IF NEW.reporting_currency_code IS DISTINCT FROM transaction_row.reporting_currency_code THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ledger entry reporting currency must match transaction.'; END IF;
  RETURN NEW;
END $function$;

COMMIT;
