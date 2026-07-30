BEGIN;
SELECT plan(47);

SELECT has_type('app', 'adjustment_direction', 'adjustment direction enum exists');
SELECT results_eq($$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname='adjustment_direction' ORDER BY enumsortorder $$, $$ VALUES ('INCREASE'::name),('DECREASE'::name) $$, 'adjustment direction values are exact');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='app' AND t.typname IN ('reversal_status','adjustment_status','financial_reversal_status','financial_adjustment_status')), 'no correction status enum added');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_enum e WHERE e.enumlabel='REVERSED'), 'REVERSED status absent');

SELECT has_table('app','financial_reversals','financial reversals table exists');
SELECT columns_are('app','financial_reversals',ARRAY['id','financial_event_id','original_transaction_id','reason','full_reversal','reversal_date'],'financial_reversals exact columns');
SELECT col_type_is('app','financial_reversals','id','uuid','reversal id uuid');
SELECT col_type_is('app','financial_reversals','financial_event_id','uuid','reversal event uuid');
SELECT col_type_is('app','financial_reversals','original_transaction_id','uuid','reversal original uuid');
SELECT col_type_is('app','financial_reversals','reason','text','reversal reason text');
SELECT col_type_is('app','financial_reversals','full_reversal','boolean','full reversal boolean');
SELECT col_type_is('app','financial_reversals','reversal_date','date','reversal date date');
SELECT has_index('app','financial_reversals','financial_reversals_event_uk','one reversal subtype per event');
SELECT has_index('app','financial_reversals','financial_reversals_original_transaction_uk','one full reversal per target transaction');
SELECT fk_ok('app','financial_reversals','financial_event_id','app','financial_events','id','reversal event FK');
SELECT fk_ok('app','financial_reversals','original_transaction_id','app','financial_transactions','id','reversal original transaction FK');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_reversals_reason_ck'), 'reversal reason nonblank constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_reversals_full_only_ck'), 'full-reversal-only constraint exists');
SELECT ok((SELECT column_default LIKE '%gen_random_uuid%' FROM information_schema.columns WHERE table_schema='app' AND table_name='financial_reversals' AND column_name='id'), 'reversal id has database default');
SELECT ok((SELECT column_default LIKE '%true%' FROM information_schema.columns WHERE table_schema='app' AND table_name='financial_reversals' AND column_name='full_reversal'), 'full reversal defaults true');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='app.financial_reversals'::regclass), 'financial reversals RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid='app.financial_reversals'::regclass), 'financial reversals RLS forced');

SELECT has_table('app','financial_adjustments','financial adjustments table exists');
SELECT columns_are('app','financial_adjustments',ARRAY['id','financial_event_id','adjusted_transaction_id','financial_account_id','direction','amount','currency_code','adjustment_date','reason'],'financial_adjustments exact columns');
SELECT col_type_is('app','financial_adjustments','id','uuid','adjustment id uuid');
SELECT col_type_is('app','financial_adjustments','financial_event_id','uuid','adjustment event uuid');
SELECT col_type_is('app','financial_adjustments','adjusted_transaction_id','uuid','adjusted transaction uuid');
SELECT col_type_is('app','financial_adjustments','financial_account_id','uuid','adjustment financial account uuid');
SELECT col_type_is('app','financial_adjustments','direction','app.adjustment_direction','adjustment direction exact');
SELECT col_type_is('app','financial_adjustments','amount','numeric(20,6)','adjustment amount exact precision');
SELECT col_type_is('app','financial_adjustments','currency_code','character(3)','adjustment currency exact');
SELECT col_type_is('app','financial_adjustments','adjustment_date','date','adjustment date exact');
SELECT col_type_is('app','financial_adjustments','reason','text','adjustment reason text');
SELECT has_index('app','financial_adjustments','financial_adjustments_event_uk','one adjustment subtype per event');
SELECT fk_ok('app','financial_adjustments','financial_event_id','app','financial_events','id','adjustment event FK');
SELECT fk_ok('app','financial_adjustments','adjusted_transaction_id','app','financial_transactions','id','adjusted transaction FK');
SELECT fk_ok('app','financial_adjustments','financial_account_id','app','financial_accounts','id','adjustment account FK');
SELECT fk_ok('app','financial_adjustments','currency_code','app','currencies','code','adjustment currency FK');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_adjustments_amount_ck'), 'adjustment positive amount constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname='financial_adjustments_reason_ck'), 'adjustment reason nonblank constraint exists');
SELECT ok((SELECT column_default LIKE '%gen_random_uuid%' FROM information_schema.columns WHERE table_schema='app' AND table_name='financial_adjustments' AND column_name='id'), 'adjustment id has database default');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='app.financial_adjustments'::regclass), 'financial adjustments RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid='app.financial_adjustments'::regclass), 'financial adjustments RLS forced');

SELECT ok((SELECT pg_get_functiondef('app.ledger_entries_trusted_insert_guard()'::regprocedure)) LIKE '%financial_reversal_posting%' AND (SELECT pg_get_functiondef('app.ledger_entries_trusted_insert_guard()'::regprocedure)) LIKE '%financial_adjustment_posting%' AND (SELECT pg_get_functiondef('app.ledger_entries_trusted_insert_guard()'::regprocedure)) LIKE '%opening_balance_posting%', 'ledger posting guard allows only approved posting contexts');
SELECT ok((SELECT pg_get_functiondef('app.financial_transactions_trusted_mutation_guard()'::regprocedure)) LIKE '%REVERSAL%' AND (SELECT pg_get_functiondef('app.financial_transactions_trusted_mutation_guard()'::regprocedure)) LIKE '%reverses_transaction_id%', 'transaction guard supports trusted reversal link');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='app' AND table_name IN ('payments','expenses','transfers','account_transfers','currency_exchanges','refunds','account_balances')), 'excluded workflow tables remain absent except approved payment, request, matching and expense packages');
SELECT ok((SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_reversal%' AND (SELECT pg_get_functiondef('public.current_account()'::regprocedure)) NOT LIKE '%financial_adjustment%', 'current_account unchanged');

SELECT * FROM finish();
ROLLBACK;
