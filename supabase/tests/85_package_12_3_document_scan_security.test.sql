BEGIN;
SELECT plan(24);

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='app.document_scans'::regclass), 'document_scans RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid='app.document_scans'::regclass), 'document_scans RLS forced');
SELECT ok(NOT has_table_privilege('anon','app.document_scans','SELECT,INSERT,UPDATE,DELETE'), 'anon has no scan table access');
SELECT ok(NOT has_table_privilege('authenticated','app.document_scans','SELECT,INSERT,UPDATE,DELETE'), 'authenticated has no scan table access');
SELECT ok(NOT has_table_privilege('service_role','app.document_scans','SELECT,INSERT,UPDATE,DELETE'), 'service role has no direct scan table access');
SELECT ok(has_function_privilege('service_role','public.server_owner_start_document_scan(uuid,uuid,text)','EXECUTE'), 'service role can start scan through gateway');
SELECT ok(has_function_privilege('service_role','public.server_owner_record_document_scan_result(uuid,uuid,app.document_scan_status,bytea,bigint,text,text,text,text,text)','EXECUTE'), 'service role can record scan through gateway');
SELECT ok(has_function_privilege('service_role','public.server_owner_prepare_clean_document_finalization(uuid,uuid,text)','EXECUTE'), 'service role can prepare finalization');
SELECT ok(has_function_privilege('service_role','public.server_owner_finalize_clean_document_upload(uuid,uuid,bytea,bigint,text)','EXECUTE'), 'service role can commit finalization');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_start_document_scan(uuid,uuid,text)','EXECUTE'), 'authenticated cannot execute scan start gateway');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_record_document_scan_result(uuid,uuid,app.document_scan_status,bytea,bigint,text,text,text,text,text)','EXECUTE'), 'authenticated cannot forge scan result');
SELECT ok(NOT has_function_privilege('anon','public.server_owner_finalize_clean_document_upload(uuid,uuid,bytea,bigint,text)','EXECUTE'), 'anon cannot finalize documents');
SELECT ok((SELECT pg_get_functiondef('app.owner_start_document_scan(uuid,uuid,text)'::regprocedure)) ILIKE '%require_active_owner_admin%', 'scan request requires active Owner/Admin');
SELECT ok((SELECT pg_get_functiondef('app.owner_start_document_scan(uuid,uuid,text)'::regprocedure)) NOT ILIKE '%authorized_by <> actor_row.actor_user_id%', 'Package 12.4 allows Owner/Admin scan processing for Client evidence uploads');
SELECT ok((SELECT pg_get_functiondef('app.owner_record_document_scan_result(uuid,uuid,app.document_scan_status,bytea,bigint,text,text,text,text,text)'::regprocedure)) ILIKE '%hash_mismatch%', 'scan result binds exact hash and size');
SELECT ok((SELECT pg_get_functiondef('app.owner_record_document_scan_result(uuid,uuid,app.document_scan_status,bytea,bigint,text,text,text,text,text)'::regprocedure)) ILIKE '%SCAN_FAILED%', 'scanner errors fail closed');
SELECT ok((SELECT pg_get_functiondef('app.owner_record_document_scan_result(uuid,uuid,app.document_scan_status,bytea,bigint,text,text,text,text,text)'::regprocedure)) ILIKE '%QUARANTINED%', 'malicious result quarantines');
SELECT ok((SELECT pg_get_functiondef('app.owner_finalize_clean_document_upload(uuid,uuid,bytea,bigint,text)'::regprocedure)) ILIKE '%p_verified_final_sha256_hash%', 'finalization requires verified final hash');
SELECT ok((SELECT pg_get_functiondef('app.owner_finalize_clean_document_upload(uuid,uuid,bytea,bigint,text)'::regprocedure)) NOT ILIKE '%DOCUMENT_SCANNER_TOKEN%', 'scanner token absent from database functions');
SELECT ok((SELECT pg_get_functiondef('app.owner_record_document_scan_result(uuid,uuid,app.document_scan_status,bytea,bigint,text,text,text,text,text)'::regprocedure)) NOT ILIKE '%raw%', 'raw scanner output is not stored');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%project_manager%access_allowed%true%', 'Project Manager remains default-denied');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%accountant%access_allowed%true%', 'Accountant remains default-denied');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%site_supervisor%access_allowed%true%', 'Site Supervisor remains default-denied');
SELECT ok(EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name='current_client_reserve_transfer_evidence_upload'), 'Package 12.4 adds only the narrow Client evidence upload gateway');

SELECT * FROM finish();
ROLLBACK;

