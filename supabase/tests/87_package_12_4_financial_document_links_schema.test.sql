BEGIN;
SELECT plan(23);

SELECT ok(NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_finance_targets_disabled_ck'), 'finance disabled constraint removed');
SELECT has_column('app', 'document_links', 'client_payment_id', 'client payment link column preserved');
SELECT has_column('app', 'document_links', 'payment_request_id', 'payment request link column preserved');
SELECT has_column('app', 'document_links', 'project_expense_id', 'project expense link column preserved');
SELECT has_column('app', 'document_links', 'currency_exchange_id', 'currency exchange link column preserved');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_client_payment_fk'), 'client payment FK exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_payment_request_fk'), 'payment request FK exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_project_expense_fk'), 'project expense FK exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_currency_exchange_fk'), 'currency exchange FK exists');
SELECT results_eq($$ SELECT confdeltype FROM pg_constraint WHERE conname IN ('document_links_client_payment_fk','document_links_payment_request_fk','document_links_project_expense_fk','document_links_currency_exchange_fk') ORDER BY conname $$, $$ VALUES ('r'::"char"),('r'::"char"),('r'::"char"),('r'::"char") $$, 'finance FKs use ON DELETE RESTRICT');
SELECT has_column('app', 'document_uploads', 'client_payment_id', 'upload client payment target added');
SELECT has_column('app', 'document_uploads', 'payment_request_id', 'upload payment request target added');
SELECT has_column('app', 'document_uploads', 'project_expense_id', 'upload project expense target added');
SELECT has_column('app', 'document_uploads', 'currency_exchange_id', 'upload currency exchange target added');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_links_exactly_one_target_ck'), 'document link exactly-one target preserved');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='document_uploads_one_target_ck'), 'upload exactly-one target spans finance targets');
SELECT results_eq($$ SELECT code, name, default_client_visible, is_active FROM app.document_types WHERE code IN ('PAYMENT_RECEIPT','BANK_TRANSFER_EVIDENCE','SUPPLIER_INVOICE','EXPENSE_RECEIPT') ORDER BY code $$, $$ VALUES ('BANK_TRANSFER_EVIDENCE'::varchar,'Bank Transfer Evidence'::varchar,false,true),('EXPENSE_RECEIPT'::varchar,'Expense Receipt'::varchar,false,true),('PAYMENT_RECEIPT'::varchar,'Payment Receipt'::varchar,false,true),('SUPPLIER_INVOICE'::varchar,'Supplier Invoice'::varchar,false,true) $$, 'controlled finance document types seeded');
SELECT has_function('app', 'document_finance_target_scope', ARRAY['uuid','uuid','uuid','uuid'], 'finance scope helper exists');
SELECT has_function('public', 'current_client_reserve_transfer_evidence_upload', ARRAY['uuid','text','text','text','uuid','text'], 'narrow Client reserve service RPC exists');
SELECT has_function('public', 'current_client_complete_transfer_evidence_upload', ARRAY['uuid','uuid','text','bigint','bytea','text'], 'narrow Client complete service RPC exists');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='app' AND table_name='document_links' AND column_name IN ('refund_id','reversal_id','adjustment_id')), 'no excluded correction/refund document targets added');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='app' AND table_name='documents' AND column_name ILIKE '%storage_url%'), 'documents do not expose storage URLs');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT ILIKE '%document%', 'public.current_account unchanged by document package');

SELECT * FROM finish();
ROLLBACK;
