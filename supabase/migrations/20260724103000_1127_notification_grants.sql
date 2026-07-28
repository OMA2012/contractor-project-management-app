BEGIN;

REVOKE ALL ON app.notifications FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION app.current_notification_recipient_context() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.create_progress_update_published_notification(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_notification_list_for_authenticated_user(app.notification_status, boolean, integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_notification_detail_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.notification_safe_row(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_mark_notification_read_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_mark_notification_unread_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app.current_archive_notification_for_authenticated_user(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_notification_list(app.notification_status, boolean, integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_notification_detail(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_mark_notification_read(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_mark_notification_unread(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.current_archive_notification(uuid) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.current_notification_list(app.notification_status, boolean, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_notification_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_mark_notification_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_mark_notification_unread(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_archive_notification(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.server_owner_publish_progress_update(uuid, uuid, integer, text, text, text, inet) TO service_role;

COMMIT;
