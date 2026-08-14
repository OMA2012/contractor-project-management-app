BEGIN;

CREATE OR REPLACE FUNCTION app.current_client_dashboard_project_summary_for_authenticated_user(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  project_id uuid,
  project_number text,
  project_name text,
  lifecycle_status text,
  official_completion_percent numeric(5,2),
  reporting_currency_code char(3)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.project_number::text,
    p.name::text,
    p.status::text,
    official.official_completion_percent,
    p.reporting_currency_code
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  CROSS JOIN LATERAL app.current_project_official_completion(p.id) AS official
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      WHERE ur.user_id = u.id
        AND ur.role_code = 'client'
        AND ur.is_active
    )
    AND NOT EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      INNER JOIN app.roles AS r ON r.code = ur.role_code
      WHERE ur.user_id = u.id
        AND ur.is_active
        AND r.is_staff_role
    )
  ORDER BY p.created_at DESC, p.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_dashboard_recent_progress_for_authenticated_user(
  p_limit integer DEFAULT 10,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  progress_update_id uuid,
  project_id uuid,
  project_number text,
  project_name text,
  title text,
  summary text,
  reported_completion_percent numeric(5,2),
  published_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;

  RETURN QUERY
  SELECT
    pu.id,
    pu.project_id,
    p.project_number::text,
    p.name::text,
    pu.title::text,
    pu.summary,
    pu.reported_completion_percent,
    pu.published_at
  FROM app.users AS u
  INNER JOIN app.clients AS c ON c.portal_user_id = u.id
  INNER JOIN app.projects AS p ON p.client_id = c.id
  INNER JOIN app.progress_updates AS pu ON pu.project_id = p.id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND pu.status = 'APPROVED'
    AND pu.client_visible
    AND pu.published_at IS NOT NULL
    AND pu.archived_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      WHERE ur.user_id = u.id
        AND ur.role_code = 'client'
        AND ur.is_active
    )
    AND NOT EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      INNER JOIN app.roles AS r ON r.code = ur.role_code
      WHERE ur.user_id = u.id
        AND ur.is_active
        AND r.is_staff_role
    )
  ORDER BY pu.published_at DESC, pu.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_client_recent_activity_for_authenticated_user(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  activity_type text,
  project_id uuid,
  project_number text,
  title text,
  message text,
  occurred_at timestamptz,
  related_entity_type text,
  related_entity_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  client_row app.clients%ROWTYPE;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;

  SELECT c.* INTO client_row
  FROM app.clients AS c
  INNER JOIN app.users AS u ON u.id = c.portal_user_id
  WHERE u.auth_subject = auth.uid()
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND c.status = 'ACTIVE'
    AND c.is_active
    AND c.archived_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      WHERE ur.user_id = u.id
        AND ur.role_code = 'client'
        AND ur.is_active
    )
    AND NOT EXISTS (
      SELECT 1
      FROM app.user_roles AS ur
      INNER JOIN app.roles AS r ON r.code = ur.role_code
      WHERE ur.user_id = u.id
        AND ur.is_active
        AND r.is_staff_role
    );

  IF client_row.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH activity AS (
    SELECT
      'PROGRESS_UPDATE_PUBLISHED'::text AS activity_type,
      p.id AS project_id,
      p.project_number::text AS project_number,
      pu.title::text AS title,
      'Progress update published.'::text AS message,
      pu.published_at AS occurred_at,
      'PROGRESS_UPDATE'::text AS related_entity_type,
      pu.id AS related_entity_id
    FROM app.projects AS p
    INNER JOIN app.progress_updates AS pu ON pu.project_id = p.id
    WHERE p.client_id = client_row.id
      AND pu.status = 'APPROVED'
      AND pu.client_visible
      AND pu.published_at IS NOT NULL
      AND pu.archived_at IS NULL

    UNION ALL

    SELECT DISTINCT
      'DOCUMENT_AVAILABLE'::text,
      COALESCE(p.id, tp.id, pp.id, cp.project_id, pr.project_id),
      COALESCE(p.project_number, tp.project_number, pp.project_number, cpp.project_number, prp.project_number)::text,
      d.original_file_name::text,
      'Document available.'::text,
      d.uploaded_at,
      'DOCUMENT'::text,
      d.id
    FROM app.documents AS d
    INNER JOIN app.document_links AS dl ON dl.document_id = d.id
    LEFT JOIN app.projects AS p ON p.id = dl.project_id
    LEFT JOIN app.tasks AS t ON t.id = dl.task_id
    LEFT JOIN app.projects AS tp ON tp.id = t.project_id
    LEFT JOIN app.progress_updates AS pu ON pu.id = dl.progress_update_id
    LEFT JOIN app.projects AS pp ON pp.id = pu.project_id
    LEFT JOIN app.client_payments AS cp ON cp.id = dl.client_payment_id
    LEFT JOIN app.projects AS cpp ON cpp.id = cp.project_id
    LEFT JOIN app.payment_requests AS pr ON pr.id = dl.payment_request_id
    LEFT JOIN app.projects AS prp ON prp.id = pr.project_id
    WHERE d.status = 'ACTIVE'
      AND d.client_visible
      AND NOT app.document_is_superseded(d.id)
      AND NOT app.document_is_client_lifecycle_private(d.id)
      AND dl.project_expense_id IS NULL
      AND dl.currency_exchange_id IS NULL
      AND NOT app.document_image_is_eligible(d.id)
      AND (
        dl.client_id = client_row.id
        OR p.client_id = client_row.id
        OR tp.client_id = client_row.id
        OR pp.client_id = client_row.id
        OR cp.client_id = client_row.id
        OR pr.client_id = client_row.id
      )
      AND COALESCE(p.id, tp.id, pp.id, cp.project_id, pr.project_id) IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM app.document_links AS other_dl
        LEFT JOIN app.projects AS other_p ON other_p.id = other_dl.project_id
        LEFT JOIN app.tasks AS other_t ON other_t.id = other_dl.task_id
        LEFT JOIN app.projects AS other_tp ON other_tp.id = other_t.project_id
        LEFT JOIN app.progress_updates AS other_pu ON other_pu.id = other_dl.progress_update_id
        LEFT JOIN app.projects AS other_pp ON other_pp.id = other_pu.project_id
        LEFT JOIN app.client_payments AS other_cp ON other_cp.id = other_dl.client_payment_id
        LEFT JOIN app.payment_requests AS other_pr ON other_pr.id = other_dl.payment_request_id
        WHERE other_dl.document_id = d.id
          AND COALESCE(other_dl.client_id, other_p.client_id, other_tp.client_id, other_pp.client_id, other_cp.client_id, other_pr.client_id) IS DISTINCT FROM client_row.id
      )

    UNION ALL

    SELECT DISTINCT
      'PHOTOGRAPH_AVAILABLE'::text,
      COALESCE(p.id, tp.id, pp.id),
      COALESCE(p.project_number, tp.project_number, pp.project_number)::text,
      d.original_file_name::text,
      'Photograph available.'::text,
      d.uploaded_at,
      'PHOTOGRAPH'::text,
      d.id
    FROM app.documents AS d
    INNER JOIN app.document_links AS dl ON dl.document_id = d.id
    LEFT JOIN app.projects AS p ON p.id = dl.project_id
    LEFT JOIN app.tasks AS t ON t.id = dl.task_id
    LEFT JOIN app.projects AS tp ON tp.id = t.project_id
    LEFT JOIN app.progress_updates AS pu ON pu.id = dl.progress_update_id
    LEFT JOIN app.projects AS pp ON pp.id = pu.project_id
    WHERE d.status = 'ACTIVE'
      AND d.client_visible
      AND NOT app.document_is_superseded(d.id)
      AND NOT app.document_is_client_lifecycle_private(d.id)
      AND app.document_image_is_eligible(d.id)
      AND app.document_image_client_parent_visible(d.id, client_row.id)
      AND (
        p.client_id = client_row.id
        OR tp.client_id = client_row.id
        OR pp.client_id = client_row.id
      )
      AND COALESCE(p.id, tp.id, pp.id) IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM app.document_links AS other_dl
        LEFT JOIN app.projects AS other_p ON other_p.id = other_dl.project_id
        LEFT JOIN app.tasks AS other_t ON other_t.id = other_dl.task_id
        LEFT JOIN app.projects AS other_tp ON other_tp.id = other_t.project_id
        LEFT JOIN app.progress_updates AS other_pu ON other_pu.id = other_dl.progress_update_id
        LEFT JOIN app.projects AS other_pp ON other_pp.id = other_pu.project_id
        WHERE other_dl.document_id = d.id
          AND COALESCE(other_dl.client_id, other_p.client_id, other_tp.client_id, other_pp.client_id) IS DISTINCT FROM client_row.id
      )

    UNION ALL

    SELECT
      'PAYMENT_REQUEST_SENT'::text,
      p.id,
      p.project_number::text,
      pr.request_number::text,
      'Payment request sent.'::text,
      pr.sent_at,
      'PAYMENT_REQUEST'::text,
      pr.id
    FROM app.payment_requests AS pr
    INNER JOIN app.projects AS p ON p.id = pr.project_id
    WHERE pr.client_id = client_row.id
      AND p.client_id = client_row.id
      AND pr.status IN ('SENT','VIEWED','OVERDUE','CANCELLED','PARTIALLY_PAID','PAID')
      AND pr.sent_at IS NOT NULL

    UNION ALL

    SELECT
      'CLIENT_PAYMENT_POSTED'::text,
      p.id,
      p.project_number::text,
      'Payment received.'::text,
      'Client payment posted.'::text,
      fe.approved_at,
      'CLIENT_PAYMENT'::text,
      cp.id
    FROM app.client_payments AS cp
    INNER JOIN app.projects AS p ON p.id = cp.project_id
    INNER JOIN app.financial_events AS fe ON fe.id = cp.financial_event_id
    INNER JOIN app.financial_transactions AS ft ON ft.financial_event_id = fe.id
    WHERE cp.client_id = client_row.id
      AND p.client_id = client_row.id
      AND fe.status = 'APPROVED'
      AND ft.status = 'POSTED'
      AND fe.approved_at IS NOT NULL
  )
  SELECT
    activity.activity_type,
    activity.project_id,
    activity.project_number,
    activity.title,
    activity.message,
    activity.occurred_at,
    activity.related_entity_type,
    activity.related_entity_id
  FROM activity
  ORDER BY activity.occurred_at DESC, activity.related_entity_type, activity.related_entity_id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION public.current_client_dashboard_project_summary(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  project_id uuid,
  project_number text,
  project_name text,
  lifecycle_status text,
  official_completion_percent numeric(5,2),
  reporting_currency_code char(3)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_dashboard_project_summary_for_authenticated_user(p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_dashboard_recent_progress(
  p_limit integer DEFAULT 10,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  progress_update_id uuid,
  project_id uuid,
  project_number text,
  project_name text,
  title text,
  summary text,
  reported_completion_percent numeric(5,2),
  published_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_dashboard_recent_progress_for_authenticated_user(p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.current_client_recent_activity(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  activity_type text,
  project_id uuid,
  project_number text,
  title text,
  message text,
  occurred_at timestamptz,
  related_entity_type text,
  related_entity_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT * FROM app.current_client_recent_activity_for_authenticated_user(p_limit, p_offset);
$function$;

REVOKE ALL ON FUNCTION app.current_client_dashboard_project_summary_for_authenticated_user(integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_dashboard_recent_progress_for_authenticated_user(integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_client_recent_activity_for_authenticated_user(integer, integer) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_client_dashboard_project_summary(integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_dashboard_recent_progress(integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_client_recent_activity(integer, integer) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.current_client_dashboard_project_summary(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_dashboard_recent_progress(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_client_recent_activity(integer, integer) TO authenticated;

COMMIT;
