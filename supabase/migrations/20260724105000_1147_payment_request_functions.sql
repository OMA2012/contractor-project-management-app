BEGIN;

CREATE OR REPLACE FUNCTION app.contractor_local_date()
RETURNS date
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  contractor_time_zone text;
  resolved_date date;
BEGIN
  SELECT cp.time_zone INTO contractor_time_zone
  FROM app.contractor_profiles AS cp
  WHERE cp.singleton_key = 1 AND cp.is_active;

  IF contractor_time_zone IS NULL OR btrim(contractor_time_zone) = '' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Contractor time zone is not configured.';
  END IF;

  BEGIN
    resolved_date := (now() AT TIME ZONE contractor_time_zone)::date;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Contractor time zone is invalid.';
  END;

  RETURN resolved_date;
END
$function$;

CREATE OR REPLACE FUNCTION app.payment_request_effective_status(p_status app.payment_request_status, p_due_date date)
RETURNS app.payment_request_status
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_status IN ('SENT','VIEWED') AND p_due_date IS NOT NULL AND p_due_date < app.contractor_local_date() THEN
    RETURN 'OVERDUE';
  END IF;
  RETURN p_status;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_payment_request_client_context()
RETURNS TABLE (client_id uuid, user_id uuid, auth_subject uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN QUERY
  SELECT c.id, u.id, u.auth_subject
  FROM app.users AS u
  JOIN app.clients AS c ON c.portal_user_id = u.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND EXISTS (
      SELECT 1 FROM app.user_roles AS ur
      WHERE ur.user_id = u.id AND ur.role_code = 'client' AND ur.is_active
    )
  LIMIT 1;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_create_payment_request(
  p_actor_auth_subject uuid,
  p_project_id uuid,
  p_requested_amount numeric,
  p_currency_code char(3),
  p_request_date date DEFAULT NULL,
  p_due_date date DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  project_row app.projects%ROWTYPE;
  request_date_value date := coalesce(p_request_date, app.contractor_local_date());
  description_text text := btrim(coalesce(p_description, ''));
  previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;

  SELECT * INTO project_row FROM app.projects WHERE id = p_project_id FOR UPDATE;
  IF project_row.id IS NULL
     OR project_row.archived_at IS NOT NULL
     OR p_requested_amount IS NULL
     OR p_requested_amount <= 0
     OR p_currency_code IS NULL
     OR request_date_value IS NULL
     OR description_text = ''
     OR p_due_date < request_date_value THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app.clients AS c WHERE c.id = project_row.client_id AND c.status = 'ACTIVE' AND c.is_active AND c.archived_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM app.currencies AS cur WHERE cur.code = p_currency_code AND cur.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request.';
  END IF;

  PERFORM set_config('app.payment_request_context', 'payment_request_owner_mutation', true);
  INSERT INTO app.payment_requests (project_id, client_id, requested_amount, currency_code, request_date, due_date, status, description, created_by, updated_by)
  VALUES (project_row.id, project_row.client_id, p_requested_amount::numeric(20,6), p_currency_code, request_date_value, p_due_date, 'DRAFT', description_text, actor_row.actor_user_id, actor_row.actor_user_id)
  RETURNING id, app.payment_requests.request_number::text, app.payment_requests.status, app.payment_requests.version_number
  INTO payment_request_id, request_number, status, version_number;
  PERFORM set_config('app.payment_request_context', coalesce(previous_context, ''), true);

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_created', 'payment_request', payment_request_id, NULL, 'success', '{}'::jsonb, jsonb_build_object('request_number', request_number, 'project_id', project_row.id, 'client_id', project_row.client_id, 'currency_code', p_currency_code, 'status', status::text, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.payment_request_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_update_payment_request(
  p_actor_auth_subject uuid,
  p_payment_request_id uuid,
  p_expected_version_number integer,
  p_project_id uuid,
  p_requested_amount numeric,
  p_currency_code char(3),
  p_request_date date,
  p_due_date date DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_request_identifier text DEFAULT NULL,
  p_correlation_identifier text DEFAULT NULL,
  p_session_identifier text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL
)
RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_row record;
  request_row app.payment_requests%ROWTYPE;
  project_row app.projects%ROWTYPE;
  description_text text := btrim(coalesce(p_description, ''));
  previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;

  SELECT * INTO request_row FROM app.payment_requests WHERE id = p_payment_request_id FOR UPDATE;
  SELECT * INTO project_row FROM app.projects WHERE id = p_project_id FOR UPDATE;
  IF request_row.id IS NULL OR request_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Payment request cannot be updated.'; END IF;
  IF request_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Payment request version conflict.'; END IF;
  IF project_row.id IS NULL
     OR project_row.archived_at IS NOT NULL
     OR p_requested_amount IS NULL
     OR p_requested_amount <= 0
     OR p_currency_code IS NULL
     OR p_request_date IS NULL
     OR description_text = ''
     OR p_due_date < p_request_date THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app.clients AS c WHERE c.id = project_row.client_id AND c.status = 'ACTIVE' AND c.is_active AND c.archived_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM app.currencies AS cur WHERE cur.code = p_currency_code AND cur.is_active) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid payment request.';
  END IF;

  PERFORM set_config('app.payment_request_context', 'payment_request_owner_mutation', true);
  UPDATE app.payment_requests
  SET project_id = project_row.id,
      client_id = project_row.client_id,
      requested_amount = p_requested_amount::numeric(20,6),
      currency_code = p_currency_code,
      request_date = p_request_date,
      due_date = p_due_date,
      description = description_text,
      updated_by = actor_row.actor_user_id
  WHERE id = request_row.id
  RETURNING id, app.payment_requests.request_number::text, app.payment_requests.status, app.payment_requests.version_number
  INTO payment_request_id, request_number, status, version_number;
  PERFORM set_config('app.payment_request_context', coalesce(previous_context, ''), true);

  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_updated', 'payment_request', payment_request_id, NULL, 'success', jsonb_build_object('status', request_row.status::text, 'version_number', request_row.version_number), jsonb_build_object('request_number', request_number, 'project_id', project_row.id, 'client_id', project_row.client_id, 'currency_code', p_currency_code, 'status', status::text, 'version_number', version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.payment_request_context', coalesce(previous_context, ''), true);
  RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_send_payment_request(p_actor_auth_subject uuid, p_payment_request_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; request_row app.payment_requests%ROWTYPE; previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO request_row FROM app.payment_requests WHERE id=p_payment_request_id FOR UPDATE;
  IF request_row.id IS NULL OR request_row.status <> 'DRAFT' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Payment request cannot be sent.'; END IF;
  IF request_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Payment request version conflict.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM app.projects p JOIN app.clients c ON c.id=p.client_id WHERE p.id=request_row.project_id AND p.client_id=request_row.client_id AND p.archived_at IS NULL AND c.status='ACTIVE' AND c.is_active AND c.archived_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM app.currencies WHERE code=request_row.currency_code AND is_active)
     OR request_row.requested_amount <= 0
     OR request_row.request_date IS NULL
     OR request_row.description IS NULL
     OR btrim(request_row.description) = ''
     OR request_row.due_date < request_row.request_date THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Invalid payment request.';
  END IF;
  PERFORM set_config('app.payment_request_context','payment_request_owner_mutation',true);
  UPDATE app.payment_requests SET status='SENT', sent_at=now(), updated_by=actor_row.actor_user_id WHERE id=request_row.id RETURNING id, app.payment_requests.request_number::text, app.payment_requests.status, app.payment_requests.version_number INTO payment_request_id, request_number, status, version_number;
  PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_sent', 'payment_request', payment_request_id, NULL, 'success', jsonb_build_object('status','DRAFT','version_number',request_row.version_number), jsonb_build_object('request_number',request_number,'project_id',request_row.project_id,'client_id',request_row.client_id,'currency_code',request_row.currency_code,'status',status::text,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_cancel_payment_request(p_actor_auth_subject uuid, p_payment_request_id uuid, p_expected_version_number integer, p_cancellation_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; request_row app.payment_requests%ROWTYPE; reason_text text := btrim(coalesce(p_cancellation_reason,'')); previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  SELECT * INTO request_row FROM app.payment_requests WHERE id=p_payment_request_id FOR UPDATE;
  IF request_row.id IS NULL OR request_row.status NOT IN ('DRAFT','SENT','VIEWED','OVERDUE') THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Payment request cannot be cancelled.'; END IF;
  IF request_row.version_number <> p_expected_version_number THEN RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Payment request version conflict.'; END IF;
  IF reason_text = '' THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Cancellation reason is required.'; END IF;
  PERFORM set_config('app.payment_request_context','payment_request_owner_mutation',true);
  UPDATE app.payment_requests SET status='CANCELLED', cancelled_at=now(), cancelled_by=actor_row.actor_user_id, cancellation_reason=reason_text, updated_by=actor_row.actor_user_id WHERE id=request_row.id RETURNING id, app.payment_requests.request_number::text, app.payment_requests.status, app.payment_requests.version_number INTO payment_request_id, request_number, status, version_number;
  PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
  PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_cancelled', 'payment_request', payment_request_id, NULL, 'success', jsonb_build_object('status',request_row.status::text,'version_number',request_row.version_number), jsonb_build_object('request_number',request_number,'project_id',request_row.project_id,'client_id',request_row.client_id,'currency_code',request_row.currency_code,'status',status::text,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, jsonb_build_object('reason_provided',true));
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_refresh_payment_request_overdue(p_actor_auth_subject uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_row record; request_row app.payment_requests%ROWTYPE; today_value date := app.contractor_local_date(); previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  FOR request_row IN SELECT pr.* FROM app.payment_requests AS pr WHERE pr.status IN ('SENT','VIEWED') AND pr.due_date IS NOT NULL AND pr.due_date < today_value ORDER BY pr.due_date, pr.id FOR UPDATE LOOP
    PERFORM set_config('app.payment_request_context','payment_request_overdue_refresh',true);
    UPDATE app.payment_requests SET status='OVERDUE', updated_by=actor_row.actor_user_id WHERE id=request_row.id RETURNING id, app.payment_requests.request_number::text, app.payment_requests.status, app.payment_requests.version_number INTO payment_request_id, request_number, status, version_number;
    PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
    PERFORM app.write_activity_log(actor_row.actor_user_id, actor_row.actor_auth_subject, actor_row.effective_role_code, 'payment_request_marked_overdue', 'payment_request', payment_request_id, NULL, 'success', jsonb_build_object('status',request_row.status::text,'version_number',request_row.version_number), jsonb_build_object('request_number',request_number,'project_id',request_row.project_id,'client_id',request_row.client_id,'currency_code',request_row.currency_code,'status',status::text,'version_number',version_number), NULL, p_ip_address, p_session_identifier, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
    RETURN NEXT;
  END LOOP;
  PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_payment_request_list(p_actor_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, client_id uuid, requested_amount numeric, currency_code char(3), request_date date, due_date date, status app.payment_request_status, effective_status app.payment_request_status, sent_at timestamptz, viewed_at timestamptz, cancelled_at timestamptz, version_number integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, pr.client_id, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.status, app.payment_request_effective_status(pr.status, pr.due_date), pr.sent_at, pr.viewed_at, pr.cancelled_at, pr.version_number FROM app.payment_requests pr ORDER BY pr.created_at DESC, pr.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_payment_request_detail(p_actor_auth_subject uuid, p_payment_request_id uuid)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, client_id uuid, requested_amount numeric, currency_code char(3), request_date date, due_date date, status app.payment_request_status, effective_status app.payment_request_status, description text, sent_at timestamptz, viewed_at timestamptz, cancelled_at timestamptz, cancelled_by uuid, cancellation_reason text, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer, paid_amount numeric, remaining_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.require_active_owner_admin(p_actor_auth_subject)) THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Privileged operation denied.'; END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, pr.client_id, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.status, app.payment_request_effective_status(pr.status, pr.due_date), pr.description, pr.sent_at, pr.viewed_at, pr.cancelled_at, pr.cancelled_by, pr.cancellation_reason, pr.created_at, pr.created_by, pr.updated_at, pr.updated_by, pr.version_number, 0::numeric(20,6), pr.requested_amount::numeric(20,6) FROM app.payment_requests pr WHERE pr.id=p_payment_request_id;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_payment_request_list(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, project_number text, requested_amount numeric, currency_code char(3), request_date date, due_date date, description text, sent_at timestamptz, viewed_at timestamptz, status app.payment_request_status, effective_status app.payment_request_status, paid_amount numeric, remaining_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE client_ctx record; safe_limit integer := least(greatest(coalesce(p_limit,50),1),100); safe_offset integer := greatest(coalesce(p_offset,0),0);
BEGIN
  SELECT * INTO client_ctx FROM app.current_payment_request_client_context();
  IF client_ctx.client_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, p.project_number::text, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.description, pr.sent_at, pr.viewed_at, pr.status, app.payment_request_effective_status(pr.status, pr.due_date), 0::numeric(20,6), pr.requested_amount::numeric(20,6) FROM app.payment_requests pr JOIN app.projects p ON p.id=pr.project_id WHERE pr.client_id=client_ctx.client_id AND p.client_id=client_ctx.client_id AND pr.status IN ('SENT','VIEWED','OVERDUE','CANCELLED','PARTIALLY_PAID','PAID') AND pr.sent_at IS NOT NULL ORDER BY pr.request_date DESC, pr.id DESC LIMIT safe_limit OFFSET safe_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_view_payment_request_detail(p_payment_request_id uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL)
RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, project_number text, requested_amount numeric, currency_code char(3), request_date date, due_date date, description text, sent_at timestamptz, viewed_at timestamptz, status app.payment_request_status, effective_status app.payment_request_status, paid_amount numeric, remaining_amount numeric)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE client_ctx record; request_row app.payment_requests%ROWTYPE; effective app.payment_request_status; prior_version integer; new_viewed_at timestamptz; previous_context text := current_setting('app.payment_request_context', true);
BEGIN
  SELECT * INTO client_ctx FROM app.current_payment_request_client_context();
  IF client_ctx.client_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  SELECT pr.* INTO request_row FROM app.payment_requests pr JOIN app.projects p ON p.id=pr.project_id WHERE pr.id=p_payment_request_id AND pr.client_id=client_ctx.client_id AND p.client_id=client_ctx.client_id FOR UPDATE;
  IF request_row.id IS NULL OR request_row.status = 'DRAFT' OR request_row.sent_at IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Client operation denied.'; END IF;
  effective := app.payment_request_effective_status(request_row.status, request_row.due_date);
  prior_version := request_row.version_number;
  IF request_row.viewed_at IS NULL THEN
    PERFORM set_config('app.payment_request_context','payment_request_client_view',true);
    UPDATE app.payment_requests
    SET viewed_at = now(),
        status = CASE WHEN request_row.status='SENT' AND effective <> 'OVERDUE' THEN 'VIEWED'::app.payment_request_status ELSE request_row.status END,
        updated_by = client_ctx.user_id
    WHERE id=request_row.id
    RETURNING * INTO request_row;
    PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true);
    PERFORM app.write_activity_log(client_ctx.user_id, client_ctx.auth_subject, 'client', 'payment_request_viewed', 'payment_request', request_row.id, NULL, 'success', jsonb_build_object('status', CASE WHEN effective = 'OVERDUE' THEN 'OVERDUE' ELSE 'SENT' END, 'version_number', prior_version), jsonb_build_object('request_number', request_row.request_number::text, 'project_id', request_row.project_id, 'client_id', request_row.client_id, 'currency_code', request_row.currency_code, 'status', request_row.status::text, 'version_number', request_row.version_number), NULL, NULL, NULL, p_request_identifier, p_correlation_identifier, '{}'::jsonb);
  END IF;
  RETURN QUERY SELECT pr.id, pr.request_number::text, pr.project_id, p.project_number::text, pr.requested_amount, pr.currency_code, pr.request_date, pr.due_date, pr.description, pr.sent_at, pr.viewed_at, pr.status, app.payment_request_effective_status(pr.status, pr.due_date), 0::numeric(20,6), pr.requested_amount::numeric(20,6) FROM app.payment_requests pr JOIN app.projects p ON p.id=pr.project_id WHERE pr.id=request_row.id;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.payment_request_context',coalesce(previous_context,''),true); RAISE;
END
$function$;

CREATE OR REPLACE FUNCTION public.server_owner_create_payment_request(p_verified_owner_auth_subject uuid, p_project_id uuid, p_requested_amount numeric, p_currency_code char(3), p_request_date date DEFAULT NULL, p_due_date date DEFAULT NULL, p_description text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_create_payment_request(p_verified_owner_auth_subject,p_project_id,p_requested_amount,p_currency_code,p_request_date,p_due_date,p_description,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_update_payment_request(p_verified_owner_auth_subject uuid, p_payment_request_id uuid, p_expected_version_number integer, p_project_id uuid, p_requested_amount numeric, p_currency_code char(3), p_request_date date, p_due_date date DEFAULT NULL, p_description text DEFAULT NULL, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_update_payment_request(p_verified_owner_auth_subject,p_payment_request_id,p_expected_version_number,p_project_id,p_requested_amount,p_currency_code,p_request_date,p_due_date,p_description,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_send_payment_request(p_verified_owner_auth_subject uuid, p_payment_request_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_send_payment_request(p_verified_owner_auth_subject,p_payment_request_id,p_expected_version_number,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_cancel_payment_request(p_verified_owner_auth_subject uuid, p_payment_request_id uuid, p_expected_version_number integer, p_cancellation_reason text, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_cancel_payment_request(p_verified_owner_auth_subject,p_payment_request_id,p_expected_version_number,p_cancellation_reason,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_payment_request_list(p_verified_owner_auth_subject uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, client_id uuid, requested_amount numeric, currency_code char(3), request_date date, due_date date, status app.payment_request_status, effective_status app.payment_request_status, sent_at timestamptz, viewed_at timestamptz, cancelled_at timestamptz, version_number integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_payment_request_list(p_verified_owner_auth_subject,p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_payment_request_detail(p_verified_owner_auth_subject uuid, p_payment_request_id uuid) RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, client_id uuid, requested_amount numeric, currency_code char(3), request_date date, due_date date, status app.payment_request_status, effective_status app.payment_request_status, description text, sent_at timestamptz, viewed_at timestamptz, cancelled_at timestamptz, cancelled_by uuid, cancellation_reason text, created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, version_number integer, paid_amount numeric, remaining_amount numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_payment_request_detail(p_verified_owner_auth_subject,p_payment_request_id); $function$;
CREATE OR REPLACE FUNCTION public.server_owner_refresh_payment_request_overdue(p_verified_owner_auth_subject uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL) RETURNS TABLE (payment_request_id uuid, request_number text, status app.payment_request_status, version_number integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.owner_refresh_payment_request_overdue(p_verified_owner_auth_subject,p_request_identifier,p_correlation_identifier,p_session_identifier,p_ip_address); $function$;
CREATE OR REPLACE FUNCTION public.current_client_payment_request_list(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, project_number text, requested_amount numeric, currency_code char(3), request_date date, due_date date, description text, sent_at timestamptz, viewed_at timestamptz, status app.payment_request_status, effective_status app.payment_request_status, paid_amount numeric, remaining_amount numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.current_client_payment_request_list(p_limit,p_offset); $function$;
CREATE OR REPLACE FUNCTION public.current_client_view_payment_request_detail(p_payment_request_id uuid, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL) RETURNS TABLE (payment_request_id uuid, request_number text, project_id uuid, project_number text, requested_amount numeric, currency_code char(3), request_date date, due_date date, description text, sent_at timestamptz, viewed_at timestamptz, status app.payment_request_status, effective_status app.payment_request_status, paid_amount numeric, remaining_amount numeric) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$ SELECT * FROM app.current_client_view_payment_request_detail(p_payment_request_id,p_request_identifier,p_correlation_identifier); $function$;

COMMIT;
