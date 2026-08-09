BEGIN;
SELECT plan(23);

SELECT ok(has_function_privilege('service_role','public.server_storage_reconciliation_report()','EXECUTE'), 'service role can execute reconciliation gateway');
SELECT ok(NOT has_function_privilege('anon','public.server_storage_reconciliation_report()','EXECUTE'), 'anon cannot execute reconciliation gateway');
SELECT ok(NOT has_function_privilege('authenticated','public.server_storage_reconciliation_report()','EXECUTE'), 'authenticated cannot execute reconciliation gateway');
SELECT ok(NOT has_function_privilege('service_role','app.storage_reconciliation_report()','EXECUTE'), 'service role cannot execute private report directly');
SELECT ok(NOT has_function_privilege('authenticated','app.storage_reconciliation_report()','EXECUTE'), 'authenticated cannot execute private report directly');
SELECT ok(NOT has_function_privilege('anon','app.storage_reconciliation_report()','EXECUTE'), 'anon cannot execute private report directly');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%client%reconciliation%'), 'no Client reconciliation gateway exists');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%project_manager%reconciliation%'), 'no Project Manager reconciliation gateway exists');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%accountant%reconciliation%'), 'no Accountant reconciliation gateway exists');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name ILIKE '%site_supervisor%reconciliation%'), 'no Site Supervisor reconciliation gateway exists');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%reconciliation%', 'public.current_account unchanged by reconciliation');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%DELETE FROM%', 'report function has no hard delete');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%UPDATE app.%', 'report function has no business update');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%INSERT INTO app.%', 'report function has no business insert');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%storage.delete%', 'report function has no storage delete marker');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%removeobject%', 'report function has no remove object marker');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%cron%', 'report function has no cron/scheduler behavior');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%timeout%', 'report function does not invent stale timeout policy');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%server_owner_invalidate_expired_document_upload%', 'report does not invoke invalidation');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%owner_start_document_scan%', 'report does not retry scans');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) NOT ILIKE '%owner_prepare_document_image_processing%', 'report does not retry image processing');
SELECT ok((SELECT pg_get_functiondef('public.server_owner_invalidate_expired_document_upload(uuid,uuid,text)'::regprocedure)) NOT ILIKE '%storage.objects%', 'existing invalidation does not delete storage objects');
SELECT ok((SELECT pg_get_functiondef('app.prevent_document_delete()'::regprocedure)) ILIKE '%Documents cannot be deleted%', 'finalized document hard-delete protection remains');

SELECT * FROM finish();
ROLLBACK;
