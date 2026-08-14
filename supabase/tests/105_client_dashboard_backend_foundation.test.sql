BEGIN;
SELECT plan(52);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010501', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-a.105@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010502', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-b.105@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010503', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-a.105@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010504', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-b.105@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010501', 'owner-a.105@example.test', 'Owner A 105', decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'), 'req-105', 'corr-105');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010501', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Dashboard Contractor', 'Dashboard Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES
  ('10000000-0000-0000-0000-000000010502', '00000000-0000-0000-0000-000000010502', 'owner-b.105@example.test', 'STAFF', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('10000000-0000-0000-0000-000000010503', '00000000-0000-0000-0000-000000010503', 'client-a.105@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('10000000-0000-0000-0000-000000010504', '00000000-0000-0000-0000-000000010504', 'client-b.105@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
SELECT id, email, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')
FROM app.users
WHERE id IN ('10000000-0000-0000-0000-000000010502','10000000-0000-0000-0000-000000010503','10000000-0000-0000-0000-000000010504');

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES
  ('10000000-0000-0000-0000-000000010502', 'owner_admin', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), true),
  ('10000000-0000-0000-0000-000000010503', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), true),
  ('10000000-0000-0000-0000-000000010504', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), true);

SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010501', 'Dashboard Client A', NULL, 'client-a.105@example.test');
SELECT * FROM public.server_create_client_record('00000000-0000-0000-0000-000000010501', 'Dashboard Client B', NULL, 'client-b.105@example.test');
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.clients WHERE display_name = 'Dashboard Client A'), '10000000-0000-0000-0000-000000010503', 1);
SELECT * FROM public.server_link_client_portal_user('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.clients WHERE display_name = 'Dashboard Client B'), '10000000-0000-0000-0000-000000010504', 1);
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.clients WHERE display_name = 'Dashboard Client A'), 'Dashboard Project A1', 'USD');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.clients WHERE display_name = 'Dashboard Client A'), 'Dashboard Project A2', 'SAR');
SELECT * FROM public.server_create_project_record('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.clients WHERE display_name = 'Dashboard Client B'), 'Dashboard Project B', 'USD');
UPDATE app.projects SET created_at = TIMESTAMPTZ '2026-08-01 00:00:00+00' WHERE name = 'Dashboard Project A1';
UPDATE app.projects SET created_at = TIMESTAMPTZ '2026-08-02 00:00:00+00' WHERE name = 'Dashboard Project A2';

SELECT * FROM public.server_owner_request_project_completion_override('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), 42.25, 'safe private reason', now());
SELECT * FROM public.server_owner_approve_project_completion_override('00000000-0000-0000-0000-000000010502', (SELECT id FROM app.project_completion_overrides WHERE override_percent = 42.25));

SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), NULL, 'Older public progress', 'Older safe progress summary', 10, true);
SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.progress_updates WHERE title = 'Older public progress'), 1);
SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000010502', (SELECT id FROM app.progress_updates WHERE title = 'Older public progress'), 2);
SELECT * FROM public.server_owner_publish_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.progress_updates WHERE title = 'Older public progress'), 3);

SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A2'), NULL, 'Newer public progress', 'Newer safe progress summary', 20, true);
SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.progress_updates WHERE title = 'Newer public progress'), 1);
SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000010502', (SELECT id FROM app.progress_updates WHERE title = 'Newer public progress'), 2);
SELECT * FROM public.server_owner_publish_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.progress_updates WHERE title = 'Newer public progress'), 3);

SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), NULL, 'Private draft progress', 'private marker progress secret', 55, false);
SELECT * FROM public.server_owner_create_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project B'), NULL, 'Client B progress', 'Client B summary', 77, true);
SELECT * FROM public.server_owner_submit_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.progress_updates WHERE title = 'Client B progress'), 1);
SELECT * FROM public.server_owner_approve_progress_update('00000000-0000-0000-0000-000000010502', (SELECT id FROM app.progress_updates WHERE title = 'Client B progress'), 2);
SELECT * FROM public.server_owner_publish_progress_update('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.progress_updates WHERE title = 'Client B progress'), 3);

SELECT set_config('app.document_metadata_context', 'owner_metadata_mutation', true);
INSERT INTO app.documents (id, storage_bucket, storage_object_key, original_file_name, mime_type, file_size_bytes, sha256_hash, document_type_code, status, client_visible, notes, uploaded_at, uploaded_by)
VALUES
  ('21000000-0000-4000-8000-000000010501', 'private-bucket', 'doc-safe', 'safe-document.pdf', 'application/pdf', 100, decode('1111111111111111111111111111111111111111111111111111111111111111', 'hex'), 'GENERAL', 'ACTIVE', true, 'document private note marker', now() - interval '5 minutes', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010502', 'private-bucket', 'photo-safe', 'safe-photo.jpg', 'image/jpeg', 100, decode('2222222222222222222222222222222222222222222222222222222222222222', 'hex'), 'PROGRESS_PHOTOGRAPH', 'ACTIVE', true, 'photo private note marker', now() - interval '4 minutes', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010503', 'private-bucket', 'doc-private', 'private-document.pdf', 'application/pdf', 100, decode('3333333333333333333333333333333333333333333333333333333333333333', 'hex'), 'GENERAL', 'ACTIVE', false, 'must not appear', now() - interval '3 minutes', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010504', 'private-bucket', 'doc-superseded', 'superseded-hidden-document.pdf', 'application/pdf', 100, decode('4444444444444444444444444444444444444444444444444444444444444444', 'hex'), 'GENERAL', 'ACTIVE', true, 'superseded lifecycle fixture', now() - interval '2 minutes', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010506', 'private-bucket', 'doc-restored', 'restored-lifecycle-document.pdf', 'application/pdf', 100, decode('6666666666666666666666666666666666666666666666666666666666666666', 'hex'), 'GENERAL', 'ACTIVE', true, 'restored lifecycle fixture', now() - interval '30 seconds', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'));
SELECT set_config('app.document_metadata_context', '', true);
INSERT INTO app.document_links (document_id, project_id, created_by)
VALUES
  ('21000000-0000-4000-8000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010502', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010503', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010504', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501')),
  ('21000000-0000-4000-8000-000000010506', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'));
SELECT * FROM public.server_owner_reserve_document_upload('00000000-0000-0000-0000-000000010501', 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD', 'replacement-current-document.pdf', 'application/pdf', 'GENERAL', true, NULL, (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), NULL, NULL, 'req-105-doc-upload');
SELECT * FROM public.server_owner_complete_document_upload('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.document_uploads WHERE original_file_name = 'replacement-current-document.pdf'), 'application/pdf', 100, decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd', 'hex'), 'req-105-doc-upload');
SELECT * FROM public.server_owner_start_document_scan('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.document_uploads WHERE original_file_name = 'replacement-current-document.pdf'), 'req-105-doc-scan');
SELECT * FROM public.server_owner_record_document_scan_result('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.document_scans WHERE document_upload_id = (SELECT id FROM app.document_uploads WHERE original_file_name = 'replacement-current-document.pdf')), 'CLEAN', decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd', 'hex'), 100, 'ClamAV', 'db', NULL, NULL, 'req-105-doc-scan');
SELECT * FROM public.server_owner_prepare_clean_document_finalization('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.document_uploads WHERE original_file_name = 'replacement-current-document.pdf'), 'req-105-doc-finalize');
SELECT * FROM public.server_owner_finalize_clean_document_upload('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.document_uploads WHERE original_file_name = 'replacement-current-document.pdf'), decode('dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd', 'hex'), 100, 'req-105-doc-finalize');
SELECT * FROM public.server_owner_declare_document_replacement('00000000-0000-0000-0000-000000010501', '21000000-0000-4000-8000-000000010504', (SELECT finalized_document_id FROM app.document_uploads WHERE original_file_name = 'replacement-current-document.pdf'), 'req-105-doc-replacement');
SELECT set_config('app.document_lifecycle_context', 'owner_document_lifecycle_mutation', true);
INSERT INTO app.document_client_access_privacy (document_id, privacy_reason, created_by)
VALUES ('21000000-0000-4000-8000-000000010506', 'RESTORED_PRIVATE', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'));
SELECT set_config('app.document_lifecycle_context', '', true);

SELECT * FROM public.server_owner_create_payment_request('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), 123, 'USD', DATE '2026-08-01', DATE '2026-08-15', 'request private-ish description');
SELECT * FROM public.server_owner_send_payment_request('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.payment_requests WHERE description = 'request private-ish description'), 1);

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010501','Dashboard Bank','BANK','USD','Bank','****9999');
SELECT * FROM public.server_owner_create_client_payment('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), 50, 'USD', DATE '2026-08-02', (SELECT id FROM app.financial_accounts WHERE name = 'Dashboard Bank'), 'payment-private-ref', 'payer secret', 'ledger private note');
SELECT * FROM public.server_owner_submit_client_payment('00000000-0000-0000-0000-000000010501', (SELECT financial_event_id FROM app.client_payments WHERE payment_reference = 'payment-private-ref'), 1);
SELECT * FROM public.server_owner_approve_client_payment('00000000-0000-0000-0000-000000010502', (SELECT financial_event_id FROM app.client_payments WHERE payment_reference = 'payment-private-ref'), 2);

INSERT INTO app.activity_logs (actor_user_id, actor_auth_subject, effective_role_code, action, entity_type, entity_id, project_id, outcome, previous_values, new_values, reason, ip_address, session_identifier, request_identifier, correlation_identifier, metadata)
VALUES ((SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010501'), '00000000-0000-0000-0000-000000010501', 'owner_admin', 'raw_private_audit_action_105', 'raw_private_table_105', gen_random_uuid(), (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1'), 'success', '{"audit_marker":"fixture_105_private_data"}', '{"audit_marker":"fixture_105_new_private_data"}', 'audit_private_marker_105', '127.0.0.1', 'session_private_marker_105', 'request_private_marker_105', 'correlation_private_marker_105', '{"device":"device_private_marker_105"}');

SELECT has_function('public', 'current_client_dashboard_project_summary', ARRAY['integer','integer'], 'project summary RPC exists');
SELECT has_function('public', 'current_client_dashboard_recent_progress', ARRAY['integer','integer'], 'recent progress RPC exists');
SELECT has_function('public', 'current_client_recent_activity', ARRAY['integer','integer'], 'recent activity RPC exists');
SELECT results_eq($$ SELECT parameter_name::text COLLATE "C" AS parameter_name FROM information_schema.parameters WHERE specific_schema = 'public' AND specific_name = 'current_client_dashboard_project_summary_' || 'public.current_client_dashboard_project_summary(integer,integer)'::regprocedure::oid::text AND parameter_mode = 'OUT' ORDER BY ordinal_position $$, $$ VALUES ('project_id'::text COLLATE "C"),('project_number'::text COLLATE "C"),('project_name'::text COLLATE "C"),('lifecycle_status'::text COLLATE "C"),('official_completion_percent'::text COLLATE "C"),('reporting_currency_code'::text COLLATE "C") $$, 'project summary exact projection');
SELECT results_eq($$ SELECT parameter_name::text COLLATE "C" AS parameter_name FROM information_schema.parameters WHERE specific_schema = 'public' AND specific_name = 'current_client_dashboard_recent_progress_' || 'public.current_client_dashboard_recent_progress(integer,integer)'::regprocedure::oid::text AND parameter_mode = 'OUT' ORDER BY ordinal_position $$, $$ VALUES ('progress_update_id'::text COLLATE "C"),('project_id'::text COLLATE "C"),('project_number'::text COLLATE "C"),('project_name'::text COLLATE "C"),('title'::text COLLATE "C"),('summary'::text COLLATE "C"),('reported_completion_percent'::text COLLATE "C"),('published_at'::text COLLATE "C") $$, 'recent progress exact projection');
SELECT results_eq($$ SELECT parameter_name::text COLLATE "C" AS parameter_name FROM information_schema.parameters WHERE specific_schema = 'public' AND specific_name = 'current_client_recent_activity_' || 'public.current_client_recent_activity(integer,integer)'::regprocedure::oid::text AND parameter_mode = 'OUT' ORDER BY ordinal_position $$, $$ VALUES ('activity_type'::text COLLATE "C"),('project_id'::text COLLATE "C"),('project_number'::text COLLATE "C"),('title'::text COLLATE "C"),('message'::text COLLATE "C"),('occurred_at'::text COLLATE "C"),('related_entity_type'::text COLLATE "C"),('related_entity_id'::text COLLATE "C") $$, 'activity exact projection');
SELECT ok(has_function_privilege('authenticated','public.current_client_dashboard_project_summary(integer,integer)','EXECUTE'), 'authenticated can execute project summary');
SELECT ok(has_function_privilege('authenticated','public.current_client_dashboard_recent_progress(integer,integer)','EXECUTE'), 'authenticated can execute recent progress');
SELECT ok(has_function_privilege('authenticated','public.current_client_recent_activity(integer,integer)','EXECUTE'), 'authenticated can execute activity');
SELECT ok(NOT has_function_privilege('anon','public.current_client_recent_activity(integer,integer)','EXECUTE'), 'anonymous denied');
SELECT ok(NOT has_function_privilege('authenticated','app.current_client_recent_activity_for_authenticated_user(integer,integer)','EXECUTE'), 'private helper unavailable');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010503', true);
SELECT results_eq($$ SELECT project_name FROM public.current_client_dashboard_project_summary(20,0) ORDER BY project_name $$, $$ VALUES ('Dashboard Project A1'::text),('Dashboard Project A2'::text) $$, 'Client A sees own Projects');
SELECT is((SELECT count(*)::integer FROM public.current_client_dashboard_project_summary(20,0) WHERE project_name = 'Dashboard Project B'), 0, 'Client A cannot see Client B Project');
SELECT results_eq($$ SELECT project_name, official_completion_percent, reporting_currency_code FROM public.current_client_dashboard_project_summary(20,0) WHERE project_name = 'Dashboard Project A1' $$, $$ VALUES ('Dashboard Project A1'::text, 42.25::numeric(5,2), 'USD'::char(3)) $$, 'official completion override and currency are reused');
SELECT results_eq($$ SELECT project_name FROM public.current_client_dashboard_project_summary(1,0) $$, $$ VALUES ('Dashboard Project A2'::text) $$, 'project summary limit follows deterministic created order');
SELECT results_eq($$ SELECT project_name FROM public.current_client_dashboard_project_summary(1,1) $$, $$ VALUES ('Dashboard Project A1'::text) $$, 'project summary offset follows deterministic created order');
SELECT throws_ok($$ SELECT * FROM public.current_client_dashboard_project_summary(101,0) $$, '23514', 'Invalid pagination request.', 'project summary rejects too-large limit');
SELECT ok((SELECT pg_get_function_result('public.current_client_dashboard_project_summary(integer,integer)'::regprocedure)) NOT ILIKE '%client_id%' AND (SELECT pg_get_function_result('public.current_client_dashboard_project_summary(integer,integer)'::regprocedure)) NOT ILIKE '%created_by%' AND (SELECT pg_get_function_result('public.current_client_dashboard_project_summary(integer,integer)'::regprocedure)) NOT ILIKE '%internal%', 'project summary exposes no private project fields');

SELECT results_eq($$ SELECT title FROM public.current_client_dashboard_recent_progress(10,0) WHERE title IN ('Older public progress','Newer public progress') AND (SELECT count(DISTINCT published_at)::integer FROM app.progress_updates WHERE title IN ('Older public progress','Newer public progress')) = 1 $$, $$ SELECT title::text FROM app.progress_updates WHERE title IN ('Older public progress','Newer public progress') ORDER BY published_at DESC, id DESC $$, 'recent progress is cross-Project with deterministic id tie-break for equal publication timestamps');
SELECT is((SELECT count(*)::integer FROM public.current_client_dashboard_recent_progress(10,0) WHERE title IN ('Private draft progress','Client B progress')), 0, 'private/unpublished and other Client progress excluded');
SELECT results_eq($$ SELECT title FROM public.current_client_dashboard_recent_progress(1,1) $$, $$ SELECT title::text FROM app.progress_updates WHERE title IN ('Older public progress','Newer public progress') ORDER BY published_at DESC, id DESC LIMIT 1 OFFSET 1 $$, 'recent progress offset follows deterministic id tie-break');
SELECT throws_ok($$ SELECT * FROM public.current_client_dashboard_recent_progress(0,0) $$, '23514', 'Invalid pagination request.', 'recent progress rejects zero limit');
SELECT ok((SELECT pg_get_function_result('public.current_client_dashboard_recent_progress(integer,integer)'::regprocedure)) NOT ILIKE '%approved_by%' AND (SELECT pg_get_function_result('public.current_client_dashboard_recent_progress(integer,integer)'::regprocedure)) NOT ILIKE '%created_by%' AND (SELECT pg_get_function_result('public.current_client_dashboard_recent_progress(integer,integer)'::regprocedure)) NOT ILIKE '%archived_at%', 'recent progress exposes no approval/private/audit fields');

SELECT ok(EXISTS (SELECT 1 FROM public.current_client_recent_activity(20,0) WHERE activity_type = 'PROGRESS_UPDATE_PUBLISHED' AND title = 'Newer public progress'), 'progress activity appears');
SELECT ok(EXISTS (SELECT 1 FROM public.current_client_recent_activity(20,0) WHERE activity_type = 'DOCUMENT_AVAILABLE' AND title = 'safe-document.pdf'), 'document activity appears');
SELECT ok(EXISTS (SELECT 1 FROM public.current_client_photograph_list(50,0) WHERE id = '21000000-0000-4000-8000-000000010502') AND EXISTS (SELECT 1 FROM public.current_client_recent_activity(20,0) WHERE activity_type = 'PHOTOGRAPH_AVAILABLE' AND related_entity_type = 'PHOTOGRAPH' AND related_entity_id = '21000000-0000-4000-8000-000000010502' AND title = 'safe-photo.jpg'), 'authoritatively visible photograph activity appears');
SELECT ok(EXISTS (SELECT 1 FROM public.current_client_recent_activity(20,0) WHERE activity_type = 'PAYMENT_REQUEST_SENT'), 'payment request activity appears');
SELECT ok(EXISTS (SELECT 1 FROM public.current_client_recent_activity(20,0) WHERE activity_type = 'CLIENT_PAYMENT_POSTED'), 'posted payment activity appears');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE activity_type = 'PROJECT_STATUS_CHANGED'), 0, 'project lifecycle activity excluded');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE title IN ('Private draft progress','Client B progress','private-document.pdf')), 0, 'private progress, other Client activity, and private document excluded');
SELECT ok((SELECT d.client_visible AND d.status = 'ACTIVE' AND NOT app.document_image_is_eligible(d.id) AND dl.project_id = (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1') AND app.document_is_finalized_from_clean_scan((SELECT finalized_document_id FROM app.document_uploads WHERE original_file_name = 'replacement-current-document.pdf')) AND app.document_is_superseded(d.id) FROM app.documents d JOIN app.document_links dl ON dl.document_id = d.id WHERE d.id = '21000000-0000-4000-8000-000000010504'), 'superseded document fixture otherwise qualifies as visible non-photo Project document');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE activity_type = 'DOCUMENT_AVAILABLE' AND related_entity_id = '21000000-0000-4000-8000-000000010504'), 0, 'superseded non-photo Client document excluded from activity');
SELECT ok((SELECT d.client_visible AND d.status = 'ACTIVE' AND NOT app.document_image_is_eligible(d.id) AND dl.project_id = (SELECT id FROM app.projects WHERE name = 'Dashboard Project A1') AND app.document_is_client_lifecycle_private(d.id) FROM app.documents d JOIN app.document_links dl ON dl.document_id = d.id WHERE d.id = '21000000-0000-4000-8000-000000010506'), 'lifecycle-private document fixture otherwise qualifies as visible non-photo Project document');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE activity_type = 'DOCUMENT_AVAILABLE' AND related_entity_id = '21000000-0000-4000-8000-000000010506'), 0, 'lifecycle-private non-photo Client document excluded from activity');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE message ILIKE '%private%' OR title ILIKE '%private%' OR title ILIKE '%payer%' OR message ILIKE '%ledger%' OR message ILIKE '%bucket%' OR message ILIKE '%storage%'), 0, 'activity title/message omit private financial/storage markers');
SELECT ok((SELECT string_agg(activity_type || ' ' || title || ' ' || message || ' ' || related_entity_type, ' ') FROM public.current_client_recent_activity(50,0)) NOT ILIKE '%raw_private_audit_action_105%' AND (SELECT string_agg(activity_type || ' ' || title || ' ' || message || ' ' || related_entity_type, ' ') FROM public.current_client_recent_activity(50,0)) NOT ILIKE '%previous_private_marker_105%' AND (SELECT string_agg(activity_type || ' ' || title || ' ' || message || ' ' || related_entity_type, ' ') FROM public.current_client_recent_activity(50,0)) NOT ILIKE '%new_private_marker_105%' AND (SELECT string_agg(activity_type || ' ' || title || ' ' || message || ' ' || related_entity_type, ' ') FROM public.current_client_recent_activity(50,0)) NOT ILIKE '%audit_private_marker_105%' AND (SELECT string_agg(activity_type || ' ' || title || ' ' || message || ' ' || related_entity_type, ' ') FROM public.current_client_recent_activity(50,0)) NOT ILIKE '%session_private_marker_105%' AND (SELECT string_agg(activity_type || ' ' || title || ' ' || message || ' ' || related_entity_type, ' ') FROM public.current_client_recent_activity(50,0)) NOT ILIKE '%device_private_marker_105%', 'activity_logs private markers do not appear');
SELECT ok((SELECT pg_get_function_result('public.current_client_recent_activity(integer,integer)'::regprocedure)) NOT ILIKE '%actor%' AND (SELECT pg_get_function_result('public.current_client_recent_activity(integer,integer)'::regprocedure)) NOT ILIKE '%previous%' AND (SELECT pg_get_function_result('public.current_client_recent_activity(integer,integer)'::regprocedure)) NOT ILIKE '%ip_address%' AND (SELECT pg_get_function_result('public.current_client_recent_activity(integer,integer)'::regprocedure)) NOT ILIKE '%session%', 'activity result shape is not generic audit row shape');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE related_entity_type = 'PROJECT_EXPENSE'), 0, 'no Project Expense activity');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE activity_type = 'CLIENT_PAYMENT_POSTED' AND related_entity_id IN (SELECT cp.id FROM app.client_payments cp JOIN app.financial_events fe ON fe.id = cp.financial_event_id JOIN app.financial_transactions ft ON ft.financial_event_id = fe.id WHERE fe.status <> 'APPROVED' OR ft.status <> 'POSTED')), 0, 'unposted/unapproved payment not represented as received');
SELECT results_eq($$ SELECT occurred_at FROM public.current_client_recent_activity(2,0) $$, $$ SELECT occurred_at FROM public.current_client_recent_activity(50,0) ORDER BY occurred_at DESC, related_entity_type, related_entity_id DESC LIMIT 2 $$, 'activity combined global ordering is deterministic');
SELECT results_eq($$ SELECT related_entity_id FROM public.current_client_recent_activity(1,1) $$, $$ SELECT related_entity_id FROM public.current_client_recent_activity(50,0) ORDER BY occurred_at DESC, related_entity_type, related_entity_id DESC LIMIT 1 OFFSET 1 $$, 'activity pagination operates over combined feed');
SELECT throws_ok($$ SELECT * FROM public.current_client_recent_activity(20,-1) $$, '23514', 'Invalid pagination request.', 'activity rejects negative offset');
SELECT ok((SELECT pg_get_functiondef('app.current_client_recent_activity_for_authenticated_user(integer,integer)'::regprocedure)) NOT ILIKE '%FROM app.activity_logs%' AND (SELECT pg_get_functiondef('app.current_client_recent_activity_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%app.document_image_is_eligible%' AND (SELECT pg_get_functiondef('app.current_client_recent_activity_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%app.document_image_client_parent_visible%', 'activity does not query activity_logs and reuses photo visibility helpers');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010504', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_dashboard_project_summary(20,0) WHERE project_name LIKE 'Dashboard Project A%'), 0, 'Client B cannot see Client A summary rows');
SELECT is((SELECT count(*)::integer FROM public.current_client_dashboard_recent_progress(20,0) WHERE title LIKE '%public progress'), 0, 'Client B cannot see Client A progress rows');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(50,0) WHERE project_number IN (SELECT project_number::text FROM app.projects WHERE name LIKE 'Dashboard Project A%')), 0, 'Client B cannot see Client A activity rows');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010501', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_dashboard_project_summary(20,0)), 0, 'staff/Owner receives no Client rows');
SELECT * FROM public.server_archive_client_record('00000000-0000-0000-0000-000000010501', (SELECT id FROM app.clients WHERE display_name = 'Dashboard Client A'), (SELECT version_number FROM app.clients WHERE display_name = 'Dashboard Client A'));
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010503', true);
SELECT is((SELECT count(*)::integer FROM public.current_client_dashboard_project_summary(20,0)), 0, 'inactive Client receives no summary rows');
SELECT is((SELECT count(*)::integer FROM public.current_client_recent_activity(20,0)), 0, 'inactive Client receives no activity rows');

SELECT ok((SELECT pg_get_functiondef('app.current_client_dashboard_project_summary_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%app.current_project_official_completion%', 'project summary reuses authoritative official completion helper');
SELECT ok((SELECT pg_get_functiondef('app.current_client_dashboard_recent_progress_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%pu.status = ''APPROVED''%' AND (SELECT pg_get_functiondef('app.current_client_dashboard_recent_progress_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%pu.client_visible%' AND (SELECT pg_get_functiondef('app.current_client_dashboard_recent_progress_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%pu.archived_at IS NULL%', 'recent progress mirrors approved client-visible published semantics');
SELECT ok((SELECT pg_get_functiondef('app.current_client_recent_activity_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%fe.status = ''APPROVED''%' AND (SELECT pg_get_functiondef('app.current_client_recent_activity_for_authenticated_user(integer,integer)'::regprocedure)) ILIKE '%ft.status = ''POSTED''%', 'payment activity requires approved and posted');

SELECT * FROM finish();
ROLLBACK;
