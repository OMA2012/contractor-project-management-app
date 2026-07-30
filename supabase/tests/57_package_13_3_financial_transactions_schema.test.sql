BEGIN;
SELECT plan(70);

SELECT has_type('app', 'financial_event_type', 'financial event type enum exists');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='financial_event_type' ORDER BY enumsortorder $$, $$ VALUES ('OPENING_BALANCE'::name),('CLIENT_PAYMENT'::name),('PROJECT_EXPENSE'::name),('ACCOUNT_TRANSFER'::name),('CURRENCY_EXCHANGE'::name),('REFUND'::name),('REVERSAL'::name),('ADJUSTMENT'::name) $$, 'financial event type values are exact');
SELECT has_type('app', 'financial_event_status', 'financial event status enum exists');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='financial_event_status' ORDER BY enumsortorder $$, $$ VALUES ('DRAFT'::name),('SUBMITTED'::name),('APPROVED'::name),('REJECTED'::name) $$, 'financial event status values are exact');
SELECT has_type('app', 'financial_transaction_status', 'financial transaction status enum exists');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='financial_transaction_status' ORDER BY enumsortorder $$, $$ VALUES ('DRAFT'::name),('SUBMITTED'::name),('APPROVED'::name),('POSTED'::name),('REJECTED'::name) $$, 'financial transaction status values are exact');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND enumlabel IN ('EXCHANGE_FEE','REVERSED')), 'forbidden enum values absent');

SELECT has_table('app', 'financial_events', 'financial events table exists');
SELECT columns_are('app', 'financial_events', ARRAY['id','event_number','event_type','project_id','client_id','event_date','status','description','submitted_at','submitted_by','duplicate_fingerprint','approved_at','approved_by','rejected_at','rejected_by','rejection_reason','created_at','created_by','updated_at','updated_by','version_number'], 'financial_events exact columns');
SELECT col_type_is('app', 'financial_events', 'event_number', 'character varying', 'event number varchar exact');
SELECT col_type_is('app', 'financial_events', 'event_type', 'app.financial_event_type', 'event type exact');
SELECT col_type_is('app', 'financial_events', 'status', 'app.financial_event_status', 'event status exact');
SELECT col_type_is('app', 'financial_events', 'event_date', 'date', 'event date exact');
SELECT col_type_is('app', 'financial_events', 'version_number', 'integer', 'event version exact');
SELECT has_index('app', 'financial_events', 'financial_events_event_number_uk', 'event number unique');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='app' AND indexname='financial_events_non_rejected_duplicate_uk'), 'non-rejected duplicate fingerprint partial unique exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_events_event_number_ck'), 'event number format constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_events_status_fields_ck'), 'event lifecycle field constraint exists');

SELECT has_table('app', 'financial_transactions', 'financial transactions table exists');
SELECT columns_are('app', 'financial_transactions', ARRAY['id','transaction_number','financial_event_id','transaction_date','status','reporting_currency_code','description','reverses_transaction_id','approved_at','approved_by','posted_at','posted_by','rejected_at','rejected_by','rejection_reason','created_at','created_by','version_number'], 'financial_transactions exact columns');
SELECT col_type_is('app', 'financial_transactions', 'transaction_number', 'character varying', 'transaction number varchar exact');
SELECT col_type_is('app', 'financial_transactions', 'status', 'app.financial_transaction_status', 'transaction status exact');
SELECT col_type_is('app', 'financial_transactions', 'reporting_currency_code', 'character(3)', 'transaction reporting currency exact');
SELECT has_index('app', 'financial_transactions', 'financial_transactions_transaction_number_uk', 'transaction number unique');
SELECT has_index('app', 'financial_transactions', 'financial_transactions_event_uk', 'one transaction per event unique');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_transactions_transaction_number_ck'), 'transaction number format constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_transactions_status_fields_ck'), 'transaction lifecycle field constraint exists');

SELECT has_table('app', 'ledger_entries', 'ledger entries table exists');
SELECT columns_are('app', 'ledger_entries', ARRAY['id','financial_transaction_id','line_no','ledger_account_id','project_id','client_id','currency_code','debit_amount','credit_amount','reporting_currency_code','reporting_debit_amount','reporting_credit_amount','exchange_rate_id','rate_base_currency_code','rate_quote_currency_code','rate_value','rate_source','rounding_adjustment','memo','created_at','created_by'], 'ledger_entries exact columns');
SELECT col_type_is('app', 'ledger_entries', 'line_no', 'integer', 'line number exact');
SELECT col_type_is('app', 'ledger_entries', 'debit_amount', 'numeric', 'debit amount numeric exact');
SELECT col_type_is('app', 'ledger_entries', 'credit_amount', 'numeric', 'credit amount numeric exact');
SELECT col_type_is('app', 'ledger_entries', 'rate_source', 'character varying', 'rate source varchar exact');
SELECT has_index('app', 'ledger_entries', 'ledger_entries_transaction_line_uk', 'unique transaction line number');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='ledger_entries_line_no_ck'), 'line number check exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='ledger_entries_amount_side_ck'), 'one-sided source amount check exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='ledger_entries_reporting_amount_side_ck'), 'one-sided reporting amount check exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='ledger_entries_rate_snapshot_ck'), 'rate snapshot pairing check exists');

SELECT has_table('app', 'account_opening_balances', 'account opening balances table exists');
SELECT columns_are('app', 'account_opening_balances', ARRAY['id','financial_event_id','financial_account_id','amount','currency_code','opening_date','notes'], 'account_opening_balances exact columns');
SELECT col_type_is('app', 'account_opening_balances', 'amount', 'numeric', 'opening amount numeric exact');
SELECT has_index('app', 'account_opening_balances', 'account_opening_balances_event_uk', 'one opening balance per event unique');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='account_opening_balances_amount_ck'), 'opening amount positive check exists');

SELECT fk_ok('app','financial_events','created_by','app','users','id','event created by FK');
SELECT fk_ok('app','financial_transactions','financial_event_id','app','financial_events','id','transaction event FK');
SELECT fk_ok('app','financial_transactions','reporting_currency_code','app','currencies','code','transaction reporting currency FK');
SELECT fk_ok('app','ledger_entries','financial_transaction_id','app','financial_transactions','id','ledger transaction FK');
SELECT fk_ok('app','ledger_entries','ledger_account_id','app','ledger_accounts','id','ledger account FK');
SELECT fk_ok('app','ledger_entries','exchange_rate_id','app','exchange_rates','id','exchange rate FK');
SELECT fk_ok('app','account_opening_balances','financial_event_id','app','financial_events','id','opening event FK');
SELECT fk_ok('app','account_opening_balances','financial_account_id','app','financial_accounts','id','opening financial account FK');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='app.financial_events'::regclass), 'financial events RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid='app.financial_events'::regclass), 'financial events RLS forced');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='app.financial_transactions'::regclass), 'financial transactions RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid='app.financial_transactions'::regclass), 'financial transactions RLS forced');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='app.ledger_entries'::regclass), 'ledger entries RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid='app.ledger_entries'::regclass), 'ledger entries RLS forced');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='app.account_opening_balances'::regclass), 'opening balances RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid='app.account_opening_balances'::regclass), 'opening balances RLS forced');

SELECT throws_ok($$ TRUNCATE app.ledger_entries $$, '23514', 'Ledger entries cannot be truncated.', 'ledger entry truncate prevented');
SELECT throws_ok($$ TRUNCATE app.financial_events CASCADE $$, '23514', 'Financial events cannot be truncated.', 'financial event truncate prevented');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payments','expenses','transfers','currency_exchanges','refunds','reversals','adjustments','account_balances')), 'excluded workflow tables remain absent except Package 14.2 payment requests');
SELECT hasnt_column('app','financial_accounts','current_balance','financial account current balance column absent');
SELECT hasnt_column('app','financial_accounts','opening_balance','financial account opening balance column absent');
SELECT hasnt_column('app','ledger_accounts','current_balance','ledger account current balance column absent');
SELECT hasnt_column('app','ledger_accounts','opening_balance','ledger account opening balance column absent');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_transaction%', 'current_account unchanged');
SELECT ok(EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'server_owner_create_client_payment'), 'Package 14.1 client payment workflow present');
SELECT ok(EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name='server_owner_create_project_expense'), 'project expense workflow added by Package 15.1');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema IN ('app','public') AND routine_name LIKE '%currency_exchange%'), 'currency exchange workflow absent');

SELECT * FROM finish();
ROLLBACK;
