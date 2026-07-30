BEGIN;
SELECT plan(43);

SELECT has_type('app', 'payment_match_status', 'payment match status enum exists');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum WHERE enumtypid = 'app.payment_match_status'::regtype ORDER BY enumsortorder $$, $$ VALUES ('DRAFT'::name),('APPROVED'::name),('VOIDED'::name) $$, 'payment match enum has exact approved values and order');

SELECT has_table('app', 'payment_matches', 'payment matches table exists');
SELECT columns_are('app', 'payment_matches', ARRAY[
  'id',
  'client_payment_id',
  'payment_request_id',
  'matched_amount',
  'currency_code',
  'matched_at',
  'status',
  'approved_at',
  'approved_by',
  'voided_at',
  'voided_by',
  'void_reason',
  'matched_by',
  'is_active'
], 'payment_matches has exactly the approved 14 columns');

SELECT col_type_is('app', 'payment_matches', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'payment_matches', 'client_payment_id', 'uuid', 'client payment id is uuid');
SELECT col_type_is('app', 'payment_matches', 'payment_request_id', 'uuid', 'payment request id is uuid');
SELECT col_type_is('app', 'payment_matches', 'matched_amount', 'numeric(20,6)', 'matched amount is numeric(20,6)');
SELECT col_type_is('app', 'payment_matches', 'currency_code', 'character(3)', 'currency is char(3)');
SELECT col_type_is('app', 'payment_matches', 'matched_at', 'timestamp with time zone', 'matched at is timestamptz');
SELECT col_type_is('app', 'payment_matches', 'status', 'app.payment_match_status', 'status uses approved enum');
SELECT col_type_is('app', 'payment_matches', 'approved_at', 'timestamp with time zone', 'approved at is timestamptz');
SELECT col_type_is('app', 'payment_matches', 'approved_by', 'uuid', 'approved by is uuid');
SELECT col_type_is('app', 'payment_matches', 'voided_at', 'timestamp with time zone', 'voided at is timestamptz');
SELECT col_type_is('app', 'payment_matches', 'voided_by', 'uuid', 'voided by is uuid');
SELECT col_type_is('app', 'payment_matches', 'void_reason', 'text', 'void reason is text');
SELECT col_type_is('app', 'payment_matches', 'matched_by', 'uuid', 'matched by is uuid');
SELECT col_type_is('app', 'payment_matches', 'is_active', 'boolean', 'is active is boolean');

SELECT col_has_default('app', 'payment_matches', 'id', 'id defaults');
SELECT col_has_default('app', 'payment_matches', 'matched_at', 'matched_at defaults');
SELECT col_has_default('app', 'payment_matches', 'status', 'status defaults to DRAFT');
SELECT col_has_default('app', 'payment_matches', 'is_active', 'is_active defaults');
SELECT col_not_null('app', 'payment_matches', 'client_payment_id', 'client payment is required');
SELECT col_not_null('app', 'payment_matches', 'payment_request_id', 'payment request is required');
SELECT col_not_null('app', 'payment_matches', 'matched_amount', 'amount is required');
SELECT col_not_null('app', 'payment_matches', 'currency_code', 'currency is required');
SELECT col_not_null('app', 'payment_matches', 'matched_at', 'matched at is required');
SELECT col_not_null('app', 'payment_matches', 'status', 'status is required');
SELECT col_not_null('app', 'payment_matches', 'matched_by', 'matched by is required');
SELECT col_not_null('app', 'payment_matches', 'is_active', 'is active is required');

SELECT has_pk('app', 'payment_matches', 'payment matches primary key exists');
SELECT has_index('app', 'payment_matches', 'payment_matches_pair_uk', 'unique payment/request pair exists');
SELECT has_index('app', 'payment_matches', 'payment_matches_request_approved_active_idx', 'approved request aggregate index exists');
SELECT has_index('app', 'payment_matches', 'payment_matches_payment_approved_active_idx', 'approved payment aggregate index exists');
SELECT fk_ok('app', 'payment_matches', 'client_payment_id', 'app', 'client_payments', 'id', 'client payment FK');
SELECT fk_ok('app', 'payment_matches', 'payment_request_id', 'app', 'payment_requests', 'id', 'payment request FK');
SELECT fk_ok('app', 'payment_matches', 'currency_code', 'app', 'currencies', 'code', 'currency FK');
SELECT fk_ok('app', 'payment_matches', 'approved_by', 'app', 'users', 'id', 'approved by FK');
SELECT fk_ok('app', 'payment_matches', 'voided_by', 'app', 'users', 'id', 'voided by FK');
SELECT fk_ok('app', 'payment_matches', 'matched_by', 'app', 'users', 'id', 'matched by FK');

SELECT isnt_empty($$ SELECT 1 FROM pg_trigger WHERE tgrelid='app.payment_matches'::regclass AND tgname IN ('payment_matches_trusted_insert','payment_matches_trusted_update','payment_matches_no_delete','payment_matches_no_truncate') GROUP BY 1 HAVING count(*)=4 $$, 'trusted and immutability triggers exist');
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='app.payment_matches'::regclass), 'RLS is enabled and forced');
SELECT is_empty($$ SELECT column_name FROM information_schema.columns WHERE table_schema='app' AND table_name='payment_matches' AND column_name IN ('project_id','client_id','version_number','created_at','updated_at','financial_event_id','financial_transaction_id','ledger_entry_id','exchange_rate_id','document_id','notification_id') $$, 'forbidden payment match columns are absent');

SELECT * FROM finish();
ROLLBACK;
