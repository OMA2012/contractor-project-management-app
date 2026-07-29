BEGIN;
SELECT plan(63);

SELECT has_type('app', 'payment_request_status', 'payment request status enum exists');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum WHERE enumtypid = 'app.payment_request_status'::regtype ORDER BY enumsortorder $$, $$ VALUES ('DRAFT'::name),('SENT'::name),('VIEWED'::name),('PARTIALLY_PAID'::name),('PAID'::name),('OVERDUE'::name),('CANCELLED'::name) $$, 'payment request enum has exact approved values and order');
-- Coverage markers: PREQ-000001 current_client_view_payment_request_detail

SELECT has_sequence('app', 'payment_request_number_seq', 'payment request number sequence exists');
SELECT has_table('app', 'payment_requests', 'payment requests table exists');
SELECT columns_are('app', 'payment_requests', ARRAY[
  'id',
  'request_number',
  'project_id',
  'client_id',
  'requested_amount',
  'currency_code',
  'request_date',
  'due_date',
  'status',
  'description',
  'sent_at',
  'viewed_at',
  'cancelled_at',
  'cancelled_by',
  'cancellation_reason',
  'created_at',
  'created_by',
  'updated_at',
  'updated_by',
  'version_number'
], 'payment_requests has exactly the approved 20 columns');

SELECT col_type_is('app', 'payment_requests', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'payment_requests', 'request_number', 'character varying(60)', 'request number type is approved');
SELECT col_type_is('app', 'payment_requests', 'project_id', 'uuid', 'project is uuid');
SELECT col_type_is('app', 'payment_requests', 'client_id', 'uuid', 'client is uuid');
SELECT col_type_is('app', 'payment_requests', 'requested_amount', 'numeric(20,6)', 'amount is numeric(20,6)');
SELECT col_type_is('app', 'payment_requests', 'currency_code', 'character(3)', 'currency is char(3)');
SELECT col_type_is('app', 'payment_requests', 'request_date', 'date', 'request date is date');
SELECT col_type_is('app', 'payment_requests', 'due_date', 'date', 'due date is date');
SELECT col_type_is('app', 'payment_requests', 'status', 'app.payment_request_status', 'status uses approved enum');
SELECT col_type_is('app', 'payment_requests', 'description', 'text', 'description is text');
SELECT col_type_is('app', 'payment_requests', 'sent_at', 'timestamp with time zone', 'sent_at is timestamptz');
SELECT col_type_is('app', 'payment_requests', 'viewed_at', 'timestamp with time zone', 'viewed_at is timestamptz');
SELECT col_type_is('app', 'payment_requests', 'cancelled_at', 'timestamp with time zone', 'cancelled_at is timestamptz');
SELECT col_type_is('app', 'payment_requests', 'cancelled_by', 'uuid', 'cancelled_by is uuid');
SELECT col_type_is('app', 'payment_requests', 'cancellation_reason', 'text', 'cancellation reason is text');
SELECT col_type_is('app', 'payment_requests', 'created_at', 'timestamp with time zone', 'created_at is timestamptz');
SELECT col_type_is('app', 'payment_requests', 'created_by', 'uuid', 'created_by is uuid');
SELECT col_type_is('app', 'payment_requests', 'updated_at', 'timestamp with time zone', 'updated_at is timestamptz');
SELECT col_type_is('app', 'payment_requests', 'updated_by', 'uuid', 'updated_by is uuid');
SELECT col_type_is('app', 'payment_requests', 'version_number', 'integer', 'version is integer');

SELECT col_has_default('app', 'payment_requests', 'id', 'id defaults');
SELECT col_has_default('app', 'payment_requests', 'request_number', 'request number defaults');
SELECT col_has_default('app', 'payment_requests', 'status', 'status defaults');
SELECT col_has_default('app', 'payment_requests', 'created_at', 'created_at defaults');
SELECT col_has_default('app', 'payment_requests', 'updated_at', 'updated_at defaults');
SELECT col_has_default('app', 'payment_requests', 'version_number', 'version defaults');

SELECT col_not_null('app', 'payment_requests', 'id', 'id required');
SELECT col_not_null('app', 'payment_requests', 'request_number', 'request number required');
SELECT col_not_null('app', 'payment_requests', 'project_id', 'project required');
SELECT col_not_null('app', 'payment_requests', 'client_id', 'client required');
SELECT col_not_null('app', 'payment_requests', 'requested_amount', 'amount required');
SELECT col_not_null('app', 'payment_requests', 'currency_code', 'currency required');
SELECT col_not_null('app', 'payment_requests', 'request_date', 'request date required');
SELECT col_not_null('app', 'payment_requests', 'status', 'status required');
SELECT col_not_null('app', 'payment_requests', 'description', 'description required');
SELECT col_not_null('app', 'payment_requests', 'created_by', 'created_by required');
SELECT col_not_null('app', 'payment_requests', 'updated_by', 'updated_by required');
SELECT col_not_null('app', 'payment_requests', 'version_number', 'version required');
SELECT col_is_null('app', 'payment_requests', 'due_date', 'due date optional');
SELECT col_is_null('app', 'payment_requests', 'sent_at', 'sent_at nullable');
SELECT col_is_null('app', 'payment_requests', 'viewed_at', 'viewed_at nullable');
SELECT col_is_null('app', 'payment_requests', 'cancelled_at', 'cancelled_at nullable');
SELECT col_is_null('app', 'payment_requests', 'cancelled_by', 'cancelled_by nullable');
SELECT col_is_null('app', 'payment_requests', 'cancellation_reason', 'cancellation reason nullable');

SELECT has_pk('app', 'payment_requests', 'payment requests primary key exists');
SELECT has_index('app', 'payment_requests', 'payment_requests_request_number_uk', 'request number unique index exists');
SELECT has_index('app', 'payment_requests', 'payment_requests_project_status_due_idx', 'project status due index exists');
SELECT has_index('app', 'payment_requests', 'payment_requests_client_status_due_idx', 'client status due index exists');
SELECT has_index('app', 'payment_requests', 'payment_requests_outstanding_due_idx', 'outstanding due partial index exists');
SELECT fk_ok('app', 'payment_requests', 'project_id', 'app', 'projects', 'id', 'project FK');
SELECT fk_ok('app', 'payment_requests', 'client_id', 'app', 'clients', 'id', 'client FK');
SELECT fk_ok('app', 'payment_requests', 'currency_code', 'app', 'currencies', 'code', 'currency FK');
SELECT fk_ok('app', 'payment_requests', 'cancelled_by', 'app', 'users', 'id', 'cancelled_by FK');
SELECT fk_ok('app', 'payment_requests', 'created_by', 'app', 'users', 'id', 'created_by FK');
SELECT fk_ok('app', 'payment_requests', 'updated_by', 'app', 'users', 'id', 'updated_by FK');

SELECT isnt_empty($$ SELECT 1 FROM pg_trigger WHERE tgrelid='app.payment_requests'::regclass AND tgname IN ('payment_requests_trusted_insert','payment_requests_trusted_update','payment_requests_no_delete','payment_requests_no_truncate') GROUP BY 1 HAVING count(*)=4 $$, 'trusted and immutability triggers exist');
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='app.payment_requests'::regclass), 'RLS is enabled and forced');
SELECT is_empty($$ SELECT column_name FROM information_schema.columns WHERE table_schema='app' AND table_name='payment_requests' AND column_name IN ('paid_amount','remaining_amount','matched_amount','payment_id','client_payment_id','financial_event_id','financial_transaction_id','ledger_entry_id','reporting_currency_code','exchange_rate_id','document_id','milestone_id','phase_id','client_comment','notification_id','archived_at','deleted_at') $$, 'forbidden payment request columns are absent');

SELECT * FROM finish();
ROLLBACK;
