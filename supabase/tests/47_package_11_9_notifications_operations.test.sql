BEGIN;
SELECT plan(42);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000004701', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.47a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004702', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.47b@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004703', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.47a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000004704', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.47b@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000004701', 'owner.47a@example.test', 'Owner Forty Seven A', decode('4747474747474747474747474747474747474747474747474747474747474747', 'hex'), 'req-47', 'corr-47');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004701', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Notification Operations Contractor', 'Notification Operations Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004702', '00000000-0000-0000-0000-000000004702', 'owner.47b@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701')),
  ('10000000-0000-0000-0000-000000004703', '00000000-0000-0000-0000-000000004703', 'client.47a@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701')),
  ('10000000-0000-0000-0000-000000004704', '00000000-0000-0000-0000-000000004704', 'client.47b@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000004702', 'Owner Forty Seven B', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701')),
  ('10000000-0000-0000-0000-000000004703', 'Client Forty Seven A', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701')),
  ('10000000-0000-0000-0000-000000004704', 'Client Forty Seven B', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000004702', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), true),
  ('10000000-0000-0000-0000-000000004703', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), true),
  ('10000000-0000-0000-0000-000000004704', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000004701'), true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000004701', 'Notification Client A', NULL, 'notification.client.a@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000004701', 'Notification Client B', NULL, 'notification.client.b@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.clients WHERE display_name = 'Notification Client A'), '10000000-0000-0000-0000-000000004703', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.clients WHERE display_name = 'Notification Client B'), '10000000-0000-0000-0000-000000004704', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.clients WHERE display_name = 'Notification Client A'), 'Notification Project A', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.clients WHERE display_name = 'Notification Client B'), 'Notification Project B', 'USD');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.projects WHERE name = 'Notification Project A'), 1, 'QUOTATION');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.projects WHERE name = 'Notification Project A'), 2, 'APPROVED');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.projects WHERE name = 'Notification Project B'), 1, 'QUOTATION');
SELECT * FROM public.server_change_project_status('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.projects WHERE name = 'Notification Project B'), 2, 'APPROVED');

SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.projects WHERE name = 'Notification Project A'), NULL, 'Notification source A', 'Safe source summary A', 20, true);
SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.progress_updates WHERE title = 'Notification source A'), 1);
SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000004702', (SELECT id FROM app.progress_updates WHERE title = 'Notification source A'), 2);

SELECT lives_ok($$ SELECT * FROM public.server_owner_publish_progress_update('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.progress_updates WHERE title = 'Notification source A'), 3) $$, 'valid publication succeeds');
SELECT is((SELECT count(*)::integer FROM app.notifications), 1, 'valid publication creates exactly one notification');
SELECT results_eq($$ SELECT notification_type, related_entity_type, title::text, body FROM app.notifications $$, $$ VALUES ('PROGRESS_UPDATE_PUBLISHED'::varchar, 'progress_update'::varchar, 'New project progress update'::text, 'A new progress update is available for your project.'::text) $$, 'notification type, entity and safe text are exact');
SELECT results_eq($$ SELECT recipient_user_id, project_id, related_entity_id, status::text, read_at, archived_at FROM app.notifications $$, $$ SELECT '10000000-0000-0000-0000-000000004703'::uuid, (SELECT id FROM app.projects WHERE name = 'Notification Project A'), (SELECT id FROM app.progress_updates WHERE title = 'Notification source A'), 'UNREAD'::text, NULL::timestamptz, NULL::timestamptz $$, 'recipient, references and initial unread state exact');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'progress_update_published' AND metadata ? 'notification_id' AND metadata ? 'notification_created'), 'publication activity includes notification metadata');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'notification_created'), 0, 'no separate notification-created activity');
SELECT set_config('app.notification_creation_context', '', true);
SELECT throws_ok($$ SELECT * FROM app.create_progress_update_published_notification((SELECT id FROM app.progress_updates WHERE title = 'Notification source A')) $$, '23514', 'Notifications require trusted creation context.', 'helper without trusted context is denied');
SELECT set_config('app.notification_creation_context', 'progress_update_publication', true);
SELECT results_eq($$ SELECT created FROM app.create_progress_update_published_notification((SELECT id FROM app.progress_updates WHERE title = 'Notification source A')) $$, $$ VALUES (false) $$, 'duplicate helper retry returns existing row');
SELECT set_config('app.notification_creation_context', '', true);
SELECT is((SELECT count(*)::integer FROM app.notifications), 1, 'duplicate retry creates no duplicate notification');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004703', true);
SELECT results_eq($$ SELECT notification_type, status::text FROM public.current_notification_list(NULL, false, 50, 0) $$, $$ VALUES ('PROGRESS_UPDATE_PUBLISHED'::text, 'UNREAD'::text) $$, 'recipient Client sees own notification');
SELECT ok(pg_get_function_result('public.current_notification_list(app.notification_status, boolean, integer, integer)'::regprocedure) NOT LIKE '%recipient_user_id%', 'recipient id is not exposed in inbox RPC result');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004704', true);
SELECT is_empty($$ SELECT * FROM public.current_notification_detail((SELECT id FROM app.notifications LIMIT 1)) $$, 'another Client copied notification ID reveals no row');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004701', true);
SELECT is_empty($$ SELECT * FROM public.current_notification_list(NULL, false, 50, 0) $$, 'Owner sees no Client notification');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004703', true);
SELECT lives_ok($$ SELECT * FROM public.current_mark_notification_read((SELECT id FROM app.notifications LIMIT 1)) $$, 'mark read succeeds');
SELECT ok((SELECT status = 'READ' AND read_at IS NOT NULL FROM app.notifications LIMIT 1), 'first read sets read_at');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'notification_marked_read'), 1, 'read mutation logs once');
SELECT lives_ok($$ SELECT * FROM public.current_mark_notification_read((SELECT id FROM app.notifications LIMIT 1)) $$, 'repeated mark read is idempotent');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'notification_marked_read'), 1, 'idempotent read creates no duplicate activity');
SELECT lives_ok($$ SELECT * FROM public.current_mark_notification_unread((SELECT id FROM app.notifications LIMIT 1)) $$, 'mark unread succeeds');
SELECT ok((SELECT status = 'UNREAD' AND read_at IS NOT NULL FROM app.notifications LIMIT 1), 'mark unread retains first read timestamp');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'notification_marked_unread'), 1, 'unread mutation logs once');
SELECT lives_ok($$ SELECT * FROM public.current_archive_notification((SELECT id FROM app.notifications LIMIT 1)) $$, 'archive succeeds');
SELECT ok((SELECT status = 'ARCHIVED' AND read_at IS NOT NULL AND archived_at IS NOT NULL FROM app.notifications LIMIT 1), 'archive retains first read timestamp');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'notification_archived'), 1, 'archive mutation logs once');
SELECT throws_ok($$ SELECT * FROM public.current_mark_notification_read((SELECT id FROM app.notifications LIMIT 1)) $$, '23514', 'Archived notification cannot be changed.', 'archived notification cannot be read');
SELECT throws_ok($$ SELECT * FROM public.current_mark_notification_unread((SELECT id FROM app.notifications LIMIT 1)) $$, '23514', 'Archived notification cannot be changed.', 'archived notification cannot be unread');
SELECT lives_ok($$ SELECT * FROM public.current_archive_notification((SELECT id FROM app.notifications LIMIT 1)) $$, 'repeated archive is idempotent');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'notification_archived'), 1, 'idempotent archive creates no duplicate activity');
SELECT is_empty($$ SELECT * FROM public.current_notification_list(NULL, false, 50, 0) $$, 'default list excludes archived');
SELECT results_eq($$ SELECT status::text FROM public.current_notification_list('ARCHIVED', false, 50, 0) $$, $$ VALUES ('ARCHIVED'::text) $$, 'archived status filter returns archived rows');
SELECT results_eq($$ SELECT status::text FROM public.current_notification_list(NULL, true, 50, 0) $$, $$ VALUES ('ARCHIVED'::text) $$, 'include archived returns all statuses');
SELECT results_eq($$ SELECT related_entity_type, related_entity_id IS NOT NULL, title NOT LIKE '%Safe source summary%' FROM public.current_notification_detail((SELECT id FROM app.notifications LIMIT 1)) $$, $$ VALUES ('progress_update'::text, true, true) $$, 'notification detail retains hint but no progress summary content');
SELECT results_eq($$ SELECT title FROM public.current_client_progress_update_detail((SELECT related_entity_id FROM app.notifications LIMIT 1)) $$, $$ VALUES ('Notification source A'::text) $$, 'related progress detail independently authorizes for recipient');
SELECT * FROM public.server_owner_archive_progress_update('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.progress_updates WHERE title = 'Notification source A'), 4);
SELECT is_empty($$ SELECT * FROM public.current_client_progress_update_detail((SELECT related_entity_id FROM app.notifications LIMIT 1)) $$, 'archived related progress cannot be reopened through notification');
SELECT results_eq($$ SELECT count(*)::integer FROM public.current_notification_detail((SELECT id FROM app.notifications LIMIT 1)) $$, $$ VALUES (1) $$, 'notification history remains readable after related progress archive');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004701', true);
SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.projects WHERE name = 'Notification Project B'), NULL, 'Notification source B', 'Safe source summary B', 20, true);
SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.progress_updates WHERE title = 'Notification source B'), 1);
SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000004702', (SELECT id FROM app.progress_updates WHERE title = 'Notification source B'), 2);
SELECT * FROM public.server_suspend_client_account('00000000-0000-0000-0000-000000004701', '10000000-0000-0000-0000-000000004704', 'Rollback fixture');
SELECT throws_ok($$ SELECT * FROM public.server_owner_publish_progress_update('00000000-0000-0000-0000-000000004701', (SELECT id FROM app.progress_updates WHERE title = 'Notification source B'), 3) $$, '23514', 'Progress update cannot be published for this Project Client.', 'inactive portal user blocks publication');
SELECT results_eq($$ SELECT published_at, version_number FROM app.progress_updates WHERE title = 'Notification source B' $$, $$ VALUES (NULL::timestamptz, 3) $$, 'failed publication rolls back published timestamp and version');
SELECT is((SELECT count(*)::integer FROM app.notifications WHERE related_entity_id = (SELECT id FROM app.progress_updates WHERE title = 'Notification source B')), 0, 'failed publication creates no notification');

SELECT set_config('app.notification_state_context', '', true);
SELECT throws_ok($$ UPDATE app.notifications SET title = 'Changed' $$, '23514', 'Notifications require trusted state functions.', 'direct update denied');
SELECT throws_ok($$ DELETE FROM app.notifications $$, '23514', 'Notifications cannot be deleted.', 'direct delete denied');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('notification_delivery_attempts','notification_preferences','notification_retry_queue','financial_transactions','ledger_entries')), 'delivery queues, preferences and finance absent');
SELECT is_empty($$ SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN ('current_project_manager_notifications','current_site_supervisor_notifications','current_assigned_notifications','server_create_notification') $$, 'reserved-role and arbitrary creation gateways absent');

SELECT * FROM finish();
ROLLBACK;
