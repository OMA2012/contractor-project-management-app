BEGIN;
SELECT plan(15);

SELECT ok(EXISTS (SELECT 1 FROM pg_type WHERE typnamespace='app'::regnamespace AND typname='storage_reconciliation_classification'), 'classification enum exists');
SELECT is((SELECT string_agg(enumlabel::text, ',' ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid='app.storage_reconciliation_classification'::regtype), 'OK,REVIEW,INVALIDATION_CANDIDATE,ORPHAN_TEMPORARY_CANDIDATE,MISSING_OBJECT,UNEXPECTED_OBJECT,QUARANTINED,PROCESSING_INCOMPLETE,DERIVATIVE_MISMATCH', 'classification enum is controlled');
SELECT ok(EXISTS (SELECT 1 FROM pg_type WHERE typnamespace='app'::regnamespace AND typname='storage_reconciliation_recommended_action'), 'recommended action enum exists');
SELECT is((SELECT string_agg(enumlabel::text, ',' ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid='app.storage_reconciliation_recommended_action'::regtype), 'NONE,MANUAL_REVIEW,INVALIDATE_RESERVATION,RETRY_EXISTING_WORKFLOW,POLICY_DECISION_REQUIRED', 'recommended action enum excludes executable delete');
SELECT ok(EXISTS (SELECT 1 FROM pg_proc WHERE oid='app.storage_reconciliation_report()'::regprocedure), 'app report function exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.server_storage_reconciliation_report()'::regprocedure), 'server report wrapper exists');
SELECT is((SELECT provolatile FROM pg_proc WHERE oid='app.storage_reconciliation_report()'::regprocedure), 's', 'app report is stable');
SELECT is((SELECT provolatile FROM pg_proc WHERE oid='public.server_storage_reconciliation_report()'::regprocedure), 's', 'server report is stable');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid='app.storage_reconciliation_report()'::regprocedure), 'app report is security definer');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid='public.server_storage_reconciliation_report()'::regprocedure), 'server report is security definer');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) ILIKE '%storage.objects%', 'computed report inspects storage.objects');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) ILIKE '%app.document_uploads%', 'computed report inspects upload reservations');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) ILIKE '%app.documents%', 'computed report inspects finalized documents');
SELECT ok((SELECT pg_get_functiondef('app.storage_reconciliation_report()'::regprocedure)) ILIKE '%app.document_image_derivatives%', 'computed report inspects photograph derivatives');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name ILIKE '%reconciliation%'), 'findings are computed, not persisted');

SELECT * FROM finish();
ROLLBACK;
