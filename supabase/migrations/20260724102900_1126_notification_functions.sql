BEGIN;

CREATE OR REPLACE FUNCTION app.current_notification_recipient_context()
RETURNS TABLE (
  actor_user_id uuid,
  actor_auth_subject uuid,
  effective_role_code varchar(40)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  user_row app.users%ROWTYPE;
  owner_role_count integer;
  client_role_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO user_row
  FROM app.users AS u
  WHERE u.auth_subject = auth.uid()
    AND u.status = 'ACTIVE'
    AND u.is_active;

  IF user_row.id IS NULL THEN
    RETURN;
  END IF;

  SELECT count(*)::integer INTO owner_role_count
  FROM app.user_roles AS ur
  WHERE ur.user_id = user_row.id
    AND ur.role_code = 'owner_admin'
    AND ur.is_active;

  SELECT count(*)::integer INTO client_role_count
  FROM app.user_roles AS ur
  WHERE ur.user_id = user_row.id
    AND ur.role_code = 'client'
    AND ur.is_active
    AND NOT EXISTS (
      SELECT 1
      FROM app.user_roles AS staff_ur
      INNER JOIN app.roles AS r ON r.code = staff_ur.role_code
      WHERE staff_ur.user_id = user_row.id
        AND staff_ur.is_active
        AND r.is_staff_role
    );

  IF owner_role_count + client_role_count <> 1 THEN
    RETURN;
  END IF;

  actor_user_id := user_row.id;
  actor_auth_subject := user_row.auth_subject;
  effective_role_code := CASE WHEN owner_role_count = 1 THEN 'owner_admin' ELSE 'client' END;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.create_progress_update_published_notification(p_progress_update_id uuid)
RETURNS TABLE (notification_id uuid, created boolean)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  progress_row app.progress_updates%ROWTYPE;
  client_row app.clients%ROWTYPE;
  portal_user_row app.users%ROWTYPE;
  inserted_id uuid;
BEGIN
  IF current_setting('app.notification_creation_context', true) IS DISTINCT FROM 'progress_update_publication' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Notifications require trusted creation context.';
  END IF;

  SELECT * INTO progress_row
  FROM app.progress_updates AS pu
  WHERE pu.id = p_progress_update_id
  FOR UPDATE;

  IF progress_row.id IS NULL
     OR progress_row.status <> 'APPROVED'
     OR NOT progress_row.client_visible
     OR progress_row.published_at IS NULL
     OR progress_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update notification source is not available.';
  END IF;

  SELECT c.* INTO client_row
  FROM app.projects AS p
  INNER JOIN app.clients AS c ON c.id = p.client_id
  WHERE p.id = progress_row.project_id;

  IF client_row.id IS NULL
     OR client_row.portal_user_id IS NULL
     OR client_row.status <> 'ACTIVE'
     OR NOT client_row.is_active
     OR client_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update notification recipient is not available.';
  END IF;

  SELECT * INTO portal_user_row
  FROM app.users AS u
  WHERE u.id = client_row.portal_user_id
    AND u.user_type = 'CLIENT'
    AND u.status = 'ACTIVE'
    AND u.is_active;

  IF portal_user_row.id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM app.user_roles AS ur
       WHERE ur.user_id = portal_user_row.id
         AND ur.role_code = 'client'
         AND ur.is_active
     )
     OR EXISTS (
       SELECT 1
       FROM app.user_roles AS ur
       INNER JOIN app.roles AS r ON r.code = ur.role_code
       WHERE ur.user_id = portal_user_row.id
         AND ur.is_active
         AND r.is_staff_role
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update notification recipient is not available.';
  END IF;

  INSERT INTO app.notifications (
    recipient_user_id,
    project_id,
    notification_type,
    title,
    body,
    related_entity_type,
    related_entity_id
  )
  VALUES (
    portal_user_row.id,
    progress_row.project_id,
    'PROGRESS_UPDATE_PUBLISHED',
    'New project progress update',
    'A new progress update is available for your project.',
    'progress_update',
    progress_row.id
  )
  ON CONFLICT (recipient_user_id, notification_type, related_entity_type, related_entity_id)
    WHERE related_entity_type IS NOT NULL
      AND related_entity_id IS NOT NULL
  DO NOTHING
  RETURNING id INTO inserted_id;

  IF inserted_id IS NOT NULL THEN
    notification_id := inserted_id;
    created := true;
  ELSE
    SELECT n.id INTO notification_id
    FROM app.notifications AS n
    WHERE n.recipient_user_id = portal_user_row.id
      AND n.notification_type = 'PROGRESS_UPDATE_PUBLISHED'
      AND n.related_entity_type = 'progress_update'
      AND n.related_entity_id = progress_row.id;
    created := false;
  END IF;

  IF notification_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update notification could not be created.';
  END IF;

  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION app.owner_publish_progress_update(p_actor_auth_subject uuid, p_progress_update_id uuid, p_expected_version_number integer, p_request_identifier text DEFAULT NULL, p_correlation_identifier text DEFAULT NULL, p_session_identifier text DEFAULT NULL, p_ip_address inet DEFAULT NULL)
RETURNS TABLE (progress_update_id uuid, project_id uuid, published_at timestamptz, version_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  actor_row record;
  existing_row app.progress_updates%ROWTYPE;
  workflow_at timestamptz := transaction_timestamp();
  notification_row record;
BEGIN
  SELECT * INTO actor_row FROM app.require_active_owner_admin(p_actor_auth_subject);
  IF actor_row.actor_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Privileged operation denied.'; END IF;

  SELECT * INTO existing_row FROM app.progress_updates AS pu WHERE pu.id = p_progress_update_id FOR UPDATE;
  IF existing_row.id IS NULL OR existing_row.status <> 'APPROVED' OR NOT existing_row.client_visible OR existing_row.approved_at IS NULL OR existing_row.approved_by IS NULL OR existing_row.published_at IS NOT NULL OR existing_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Progress update cannot be published.';
  END IF;
  IF existing_row.version_number <> p_expected_version_number THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'Progress update version conflict.';
  END IF;

  PERFORM app.assert_project_client_readable_for_progress(existing_row.project_id);
  PERFORM set_config('app.allow_progress_update_mutation', 'on', true);
  UPDATE app.progress_updates AS pu
  SET published_at = workflow_at, updated_by = actor_row.actor_user_id
  WHERE pu.id = p_progress_update_id
  RETURNING pu.id, pu.project_id, pu.published_at, pu.version_number
  INTO progress_update_id, project_id, published_at, version_number;
  PERFORM set_config('app.allow_progress_update_mutation', 'off', true);

  PERFORM set_config('app.notification_creation_context', 'progress_update_publication', true);
  SELECT * INTO notification_row
  FROM app.create_progress_update_published_notification(progress_update_id);

  PERFORM app.write_activity_log(
    actor_row.actor_user_id,
    actor_row.actor_auth_subject,
    actor_row.effective_role_code,
    'progress_update_published',
    'progress_update',
    progress_update_id,
    project_id,
    'success',
    jsonb_build_object('published', false, 'version_number', existing_row.version_number),
    jsonb_build_object('published', true, 'version_number', version_number),
    NULL,
    p_ip_address,
    p_session_identifier,
    p_request_identifier,
    p_correlation_identifier,
    jsonb_build_object(
      'notification_id', notification_row.notification_id,
      'notification_created', notification_row.created
    )
  );
  RETURN NEXT;
END $function$;

CREATE OR REPLACE FUNCTION app.current_notification_list_for_authenticated_user(
  p_status app.notification_status DEFAULT NULL,
  p_include_archived boolean DEFAULT false,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  notification_type text,
  title text,
  body text,
  status app.notification_status,
  related_entity_type text,
  related_entity_id uuid,
  created_at timestamptz,
  read_at timestamptz,
  archived_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  recipient_row record;
BEGIN
  SELECT * INTO recipient_row FROM app.current_notification_recipient_context();
  IF recipient_row.actor_user_id IS NULL THEN
    RETURN;
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid pagination request.';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.project_id,
    n.notification_type::text,
    n.title::text,
    n.body,
    n.status,
    n.related_entity_type::text,
    n.related_entity_id,
    n.created_at,
    n.read_at,
    n.archived_at
  FROM app.notifications AS n
  WHERE n.recipient_user_id = recipient_row.actor_user_id
    AND (
      (p_status = 'ARCHIVED' AND n.status = 'ARCHIVED')
      OR (p_status IN ('UNREAD', 'READ') AND n.status = p_status)
      OR (p_status IS NULL AND p_include_archived AND n.status IN ('UNREAD', 'READ', 'ARCHIVED'))
      OR (p_status IS NULL AND NOT p_include_archived AND n.status IN ('UNREAD', 'READ'))
    )
  ORDER BY n.created_at DESC, n.id DESC
  LIMIT p_limit
  OFFSET p_offset;
END
$function$;

CREATE OR REPLACE FUNCTION app.current_notification_detail_for_authenticated_user(p_notification_id uuid)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  notification_type text,
  title text,
  body text,
  status app.notification_status,
  related_entity_type text,
  related_entity_id uuid,
  created_at timestamptz,
  read_at timestamptz,
  archived_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT n.id, n.project_id, n.notification_type, n.title, n.body, n.status, n.related_entity_type, n.related_entity_id, n.created_at, n.read_at, n.archived_at
  FROM app.notifications AS n
  INNER JOIN app.current_notification_recipient_context() AS ctx ON ctx.actor_user_id = n.recipient_user_id
  WHERE n.id = p_notification_id;
$function$;

CREATE OR REPLACE FUNCTION app.notification_safe_row(p_notification_id uuid)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  notification_type text,
  title text,
  body text,
  status app.notification_status,
  related_entity_type text,
  related_entity_id uuid,
  created_at timestamptz,
  read_at timestamptz,
  archived_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT n.id, n.project_id, n.notification_type, n.title, n.body, n.status, n.related_entity_type, n.related_entity_id, n.created_at, n.read_at, n.archived_at
  FROM app.notifications AS n
  WHERE n.id = p_notification_id;
$function$;

CREATE OR REPLACE FUNCTION app.current_mark_notification_read_for_authenticated_user(p_notification_id uuid)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  notification_type text,
  title text,
  body text,
  status app.notification_status,
  related_entity_type text,
  related_entity_id uuid,
  created_at timestamptz,
  read_at timestamptz,
  archived_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  recipient_row record;
  existing_row app.notifications%ROWTYPE;
  new_row app.notifications%ROWTYPE;
  workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO recipient_row FROM app.current_notification_recipient_context();
  IF recipient_row.actor_user_id IS NULL THEN RETURN; END IF;

  SELECT * INTO existing_row
  FROM app.notifications AS n
  WHERE n.id = p_notification_id
    AND n.recipient_user_id = recipient_row.actor_user_id
  FOR UPDATE;
  IF existing_row.id IS NULL THEN RETURN; END IF;
  IF existing_row.status = 'ARCHIVED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Archived notification cannot be changed.'; END IF;

  IF existing_row.status = 'READ' THEN
    RETURN QUERY SELECT * FROM app.notification_safe_row(existing_row.id);
    RETURN;
  END IF;

  PERFORM set_config('app.notification_state_context', 'current_recipient_state_change', true);
  UPDATE app.notifications AS n
  SET status = 'READ',
      read_at = coalesce(n.read_at, workflow_at)
  WHERE n.id = existing_row.id
  RETURNING * INTO new_row;

  PERFORM app.write_activity_log(recipient_row.actor_user_id, recipient_row.actor_auth_subject, recipient_row.effective_role_code, 'notification_marked_read', 'notification', new_row.id, new_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', new_row.status::text), NULL, NULL, NULL, NULL, NULL, jsonb_build_object('notification_id', new_row.id, 'notification_type', new_row.notification_type, 'previous_status', existing_row.status::text, 'new_status', new_row.status::text));
  RETURN QUERY SELECT * FROM app.notification_safe_row(new_row.id);
END
$function$;

CREATE OR REPLACE FUNCTION app.current_mark_notification_unread_for_authenticated_user(p_notification_id uuid)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  notification_type text,
  title text,
  body text,
  status app.notification_status,
  related_entity_type text,
  related_entity_id uuid,
  created_at timestamptz,
  read_at timestamptz,
  archived_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  recipient_row record;
  existing_row app.notifications%ROWTYPE;
  new_row app.notifications%ROWTYPE;
BEGIN
  SELECT * INTO recipient_row FROM app.current_notification_recipient_context();
  IF recipient_row.actor_user_id IS NULL THEN RETURN; END IF;

  SELECT * INTO existing_row
  FROM app.notifications AS n
  WHERE n.id = p_notification_id
    AND n.recipient_user_id = recipient_row.actor_user_id
  FOR UPDATE;
  IF existing_row.id IS NULL THEN RETURN; END IF;
  IF existing_row.status = 'ARCHIVED' THEN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Archived notification cannot be changed.'; END IF;

  IF existing_row.status = 'UNREAD' THEN
    RETURN QUERY SELECT * FROM app.notification_safe_row(existing_row.id);
    RETURN;
  END IF;

  PERFORM set_config('app.notification_state_context', 'current_recipient_state_change', true);
  UPDATE app.notifications AS n
  SET status = 'UNREAD'
  WHERE n.id = existing_row.id
  RETURNING * INTO new_row;

  PERFORM app.write_activity_log(recipient_row.actor_user_id, recipient_row.actor_auth_subject, recipient_row.effective_role_code, 'notification_marked_unread', 'notification', new_row.id, new_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', new_row.status::text), NULL, NULL, NULL, NULL, NULL, jsonb_build_object('notification_id', new_row.id, 'notification_type', new_row.notification_type, 'previous_status', existing_row.status::text, 'new_status', new_row.status::text));
  RETURN QUERY SELECT * FROM app.notification_safe_row(new_row.id);
END
$function$;

CREATE OR REPLACE FUNCTION app.current_archive_notification_for_authenticated_user(p_notification_id uuid)
RETURNS TABLE (
  id uuid,
  project_id uuid,
  notification_type text,
  title text,
  body text,
  status app.notification_status,
  related_entity_type text,
  related_entity_id uuid,
  created_at timestamptz,
  read_at timestamptz,
  archived_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  recipient_row record;
  existing_row app.notifications%ROWTYPE;
  new_row app.notifications%ROWTYPE;
  workflow_at timestamptz := transaction_timestamp();
BEGIN
  SELECT * INTO recipient_row FROM app.current_notification_recipient_context();
  IF recipient_row.actor_user_id IS NULL THEN RETURN; END IF;

  SELECT * INTO existing_row
  FROM app.notifications AS n
  WHERE n.id = p_notification_id
    AND n.recipient_user_id = recipient_row.actor_user_id
  FOR UPDATE;
  IF existing_row.id IS NULL THEN RETURN; END IF;
  IF existing_row.status = 'ARCHIVED' THEN
    RETURN QUERY SELECT * FROM app.notification_safe_row(existing_row.id);
    RETURN;
  END IF;

  PERFORM set_config('app.notification_state_context', 'current_recipient_state_change', true);
  UPDATE app.notifications AS n
  SET status = 'ARCHIVED',
      archived_at = workflow_at
  WHERE n.id = existing_row.id
  RETURNING * INTO new_row;

  PERFORM app.write_activity_log(recipient_row.actor_user_id, recipient_row.actor_auth_subject, recipient_row.effective_role_code, 'notification_archived', 'notification', new_row.id, new_row.project_id, 'success', jsonb_build_object('status', existing_row.status::text), jsonb_build_object('status', new_row.status::text), NULL, NULL, NULL, NULL, NULL, jsonb_build_object('notification_id', new_row.id, 'notification_type', new_row.notification_type, 'previous_status', existing_row.status::text, 'new_status', new_row.status::text));
  RETURN QUERY SELECT * FROM app.notification_safe_row(new_row.id);
END
$function$;

CREATE OR REPLACE FUNCTION public.current_notification_list(p_status app.notification_status DEFAULT NULL, p_include_archived boolean DEFAULT false, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, project_id uuid, notification_type text, title text, body text, status app.notification_status, related_entity_type text, related_entity_id uuid, created_at timestamptz, read_at timestamptz, archived_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_notification_list_for_authenticated_user(p_status, p_include_archived, p_limit, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.current_notification_detail(p_notification_id uuid)
RETURNS TABLE (id uuid, project_id uuid, notification_type text, title text, body text, status app.notification_status, related_entity_type text, related_entity_id uuid, created_at timestamptz, read_at timestamptz, archived_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_notification_detail_for_authenticated_user(p_notification_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_mark_notification_read(p_notification_id uuid)
RETURNS TABLE (id uuid, project_id uuid, notification_type text, title text, body text, status app.notification_status, related_entity_type text, related_entity_id uuid, created_at timestamptz, read_at timestamptz, archived_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_mark_notification_read_for_authenticated_user(p_notification_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_mark_notification_unread(p_notification_id uuid)
RETURNS TABLE (id uuid, project_id uuid, notification_type text, title text, body text, status app.notification_status, related_entity_type text, related_entity_id uuid, created_at timestamptz, read_at timestamptz, archived_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_mark_notification_unread_for_authenticated_user(p_notification_id);
$function$;

CREATE OR REPLACE FUNCTION public.current_archive_notification(p_notification_id uuid)
RETURNS TABLE (id uuid, project_id uuid, notification_type text, title text, body text, status app.notification_status, related_entity_type text, related_entity_id uuid, created_at timestamptz, read_at timestamptz, archived_at timestamptz)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT * FROM app.current_archive_notification_for_authenticated_user(p_notification_id);
$function$;

COMMIT;
