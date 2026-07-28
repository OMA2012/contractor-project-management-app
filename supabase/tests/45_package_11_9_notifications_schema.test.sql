BEGIN;
SELECT plan(31);

SELECT has_type('app', 'notification_status', 'notification status enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'app' AND t.typname = 'notification_status' ORDER BY enumsortorder $$,
  $$ VALUES ('UNREAD'::name), ('READ'::name), ('ARCHIVED'::name) $$,
  'notification enum values are exact'
);
SELECT has_table('app', 'notifications', 'notifications table exists');
SELECT columns_are('app', 'notifications', ARRAY[
  'id','recipient_user_id','project_id','notification_type','title','body','status',
  'related_entity_type','related_entity_id','created_at','read_at','archived_at'
], 'notifications have exact 12 columns');
SELECT hasnt_column('app', 'notifications', 'delivery_status', 'delivery status absent');
SELECT hasnt_column('app', 'notifications', 'delivery_channel', 'delivery channel absent');
SELECT hasnt_column('app', 'notifications', 'email_address', 'email absent');
SELECT hasnt_column('app', 'notifications', 'phone_number', 'phone absent');
SELECT hasnt_column('app', 'notifications', 'link_url', 'URL absent');
SELECT hasnt_column('app', 'notifications', 'payload', 'payload absent');
SELECT hasnt_column('app', 'notifications', 'metadata', 'metadata absent');
SELECT hasnt_column('app', 'notifications', 'version_number', 'version absent');
SELECT hasnt_column('app', 'notifications', 'updated_at', 'updated timestamp absent');
SELECT col_type_is('app', 'notifications', 'notification_type', 'character varying(60)', 'notification type length exact');
SELECT col_type_is('app', 'notifications', 'title', 'character varying(200)', 'title length exact');
SELECT col_type_is('app', 'notifications', 'status', 'app.notification_status', 'status type exact');
SELECT is((SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum WHERE a.attrelid = 'app.notifications'::regclass AND a.attname = 'status'), '''UNREAD''::app.notification_status', 'status defaults to unread');
SELECT fk_ok('app', 'notifications', 'recipient_user_id', 'app', 'users', 'id', 'recipient foreign key exists');
SELECT fk_ok('app', 'notifications', 'project_id', 'app', 'projects', 'id', 'Project foreign key exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_related_pair_ck'), 'related entity pair constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_state_ck'), 'state consistency constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_timestamp_order_ck'), 'timestamp ordering constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'notifications' AND indexname = 'notifications_recipient_inbox_idx'), 'recipient inbox index exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'notifications' AND indexname = 'notifications_recipient_unread_idx'), 'unread inbox index exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'notifications' AND indexname = 'notifications_project_context_idx'), 'Project context index exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'notifications' AND indexname = 'notifications_related_unique_idx'), 'duplicate suppression unique index exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.notifications'::regclass), 'notifications RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.notifications'::regclass), 'notifications RLS forced');
SELECT throws_ok($$ INSERT INTO app.notifications DEFAULT VALUES $$, '23514', 'Notifications require trusted creation context.', 'direct insert denied by trusted context');
SELECT throws_ok($$ TRUNCATE app.notifications $$, '23514', 'Notifications cannot be truncated.', 'truncate prevented');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('notification_preferences','notification_delivery_attempts','documents','financial_transactions','ledger_entries')), 'delivery preference, document and finance objects remain absent');

SELECT * FROM finish();
ROLLBACK;
