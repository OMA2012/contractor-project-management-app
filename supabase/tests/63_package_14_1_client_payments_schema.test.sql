BEGIN;
SELECT plan(42);

SELECT has_table('app', 'client_payments', 'client payments table exists');
SELECT columns_are('app', 'client_payments', ARRAY[
  'id',
  'financial_event_id',
  'project_id',
  'client_id',
  'amount',
  'currency_code',
  'received_account_id',
  'received_date',
  'payment_reference',
  'payer_name',
  'is_client_submitted',
  'submitted_by_client_user_id',
  'notes'
], 'client payments has exactly the approved 13 columns');

SELECT col_type_is('app', 'client_payments', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'client_payments', 'financial_event_id', 'uuid', 'financial_event_id is uuid');
SELECT col_type_is('app', 'client_payments', 'project_id', 'uuid', 'project_id is uuid');
SELECT col_type_is('app', 'client_payments', 'client_id', 'uuid', 'client_id is uuid');
SELECT col_type_is('app', 'client_payments', 'amount', 'numeric(20,6)', 'amount is numeric(20,6)');
SELECT col_type_is('app', 'client_payments', 'currency_code', 'character(3)', 'currency code is char(3)');
SELECT col_type_is('app', 'client_payments', 'received_account_id', 'uuid', 'received account is uuid');
SELECT col_type_is('app', 'client_payments', 'received_date', 'date', 'received date is date');
SELECT col_type_is('app', 'client_payments', 'payment_reference', 'character varying(120)', 'payment reference size is approved');
SELECT col_type_is('app', 'client_payments', 'payer_name', 'character varying(200)', 'payer name size is approved');
SELECT col_type_is('app', 'client_payments', 'is_client_submitted', 'boolean', 'client submitted flag is boolean');
SELECT col_type_is('app', 'client_payments', 'submitted_by_client_user_id', 'uuid', 'client submitter is uuid');
SELECT col_type_is('app', 'client_payments', 'notes', 'text', 'notes is text');

SELECT col_has_default('app', 'client_payments', 'id', 'id has database default');
SELECT col_has_default('app', 'client_payments', 'is_client_submitted', 'client flag defaults');
SELECT col_not_null('app', 'client_payments', 'financial_event_id', 'financial event required');
SELECT col_not_null('app', 'client_payments', 'project_id', 'project required');
SELECT col_not_null('app', 'client_payments', 'client_id', 'client required');
SELECT col_not_null('app', 'client_payments', 'amount', 'amount required');
SELECT col_not_null('app', 'client_payments', 'currency_code', 'currency required');
SELECT col_not_null('app', 'client_payments', 'received_date', 'received date required');
SELECT col_not_null('app', 'client_payments', 'is_client_submitted', 'client flag required');
SELECT col_is_null('app', 'client_payments', 'received_account_id', 'received account nullable for draft/client submission');
SELECT col_is_null('app', 'client_payments', 'payment_reference', 'payment reference optional');
SELECT col_is_null('app', 'client_payments', 'payer_name', 'payer name optional');
SELECT col_is_null('app', 'client_payments', 'submitted_by_client_user_id', 'submitter nullable for Owner drafts');
SELECT col_is_null('app', 'client_payments', 'notes', 'notes optional');

SELECT has_pk('app', 'client_payments', 'client payments primary key exists');
SELECT has_index('app', 'client_payments', 'client_payments_event_uk', 'one subtype row per event unique index');
SELECT fk_ok('app', 'client_payments', 'financial_event_id', 'app', 'financial_events', 'id', 'financial event FK');
SELECT fk_ok('app', 'client_payments', 'project_id', 'app', 'projects', 'id', 'project FK');
SELECT fk_ok('app', 'client_payments', 'client_id', 'app', 'clients', 'id', 'client FK');
SELECT fk_ok('app', 'client_payments', 'currency_code', 'app', 'currencies', 'code', 'currency FK');
SELECT fk_ok('app', 'client_payments', 'received_account_id', 'app', 'financial_accounts', 'id', 'received account FK');
SELECT fk_ok('app', 'client_payments', 'submitted_by_client_user_id', 'app', 'users', 'id', 'client submitter FK');

SELECT isnt_empty($$ SELECT 1 FROM pg_trigger WHERE tgrelid = 'app.client_payments'::regclass AND tgname IN ('client_payments_trusted_insert','client_payments_trusted_update','client_payments_no_delete','client_payments_no_truncate') GROUP BY 1 HAVING count(*) = 4 $$, 'trusted and immutability triggers exist');
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='app.client_payments'::regclass), 'RLS is enabled and forced');
SELECT ok((SELECT pg_get_functiondef('app.ledger_entries_trusted_insert_guard()'::regprocedure)) LIKE '%client_payment_posting%', 'ledger trusted context includes client payment posting');
SELECT ok((SELECT pg_get_functiondef('app.ledger_entries_trusted_insert_guard()'::regprocedure)) LIKE '%opening_balance_posting%' AND (SELECT pg_get_functiondef('app.ledger_entries_trusted_insert_guard()'::regprocedure)) LIKE '%financial_reversal_posting%' AND (SELECT pg_get_functiondef('app.ledger_entries_trusted_insert_guard()'::regprocedure)) LIKE '%financial_adjustment_posting%', 'Stage 13 posting contexts are preserved');

SELECT is_empty($$ SELECT column_name FROM information_schema.columns WHERE table_schema='app' AND table_name='client_payments' AND column_name IN ('payment_number','payment_method','status','approved_at','approved_by','created_at','updated_at','version_number','archived_at','converted_amount','exchange_rate_id','document_id','payment_request_id') $$, 'forbidden client payment columns are absent');

SELECT * FROM finish();
ROLLBACK;
