BEGIN;
SELECT plan(56);

SELECT has_type('app', 'ledger_account_kind', 'ledger account kind enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'app' AND t.typname = 'ledger_account_kind' ORDER BY enumsortorder $$,
  $$ VALUES ('FINANCIAL_ASSET'::name), ('CONTROL'::name) $$,
  'ledger account kind enum values are exact'
);
SELECT has_type('app', 'entry_side', 'entry side enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'app' AND t.typname = 'entry_side' ORDER BY enumsortorder $$,
  $$ VALUES ('DEBIT'::name), ('CREDIT'::name) $$,
  'entry side enum values are exact'
);

SELECT has_table('app', 'ledger_accounts', 'ledger accounts table exists');
SELECT columns_are('app', 'ledger_accounts', ARRAY[
  'id','code','name','account_kind','financial_account_id','currency_code',
  'normal_side','is_system','is_active'
], 'ledger_accounts has exact approved columns');
SELECT col_type_is('app', 'ledger_accounts', 'id', 'uuid', 'ledger id type exact');
SELECT col_type_is('app', 'ledger_accounts', 'code', 'character varying(80)', 'ledger code type exact');
SELECT col_type_is('app', 'ledger_accounts', 'name', 'character varying(160)', 'ledger name type exact');
SELECT col_type_is('app', 'ledger_accounts', 'account_kind', 'app.ledger_account_kind', 'ledger kind type exact');
SELECT col_type_is('app', 'ledger_accounts', 'financial_account_id', 'uuid', 'financial account id type exact');
SELECT col_type_is('app', 'ledger_accounts', 'currency_code', 'character(3)', 'ledger currency type exact');
SELECT col_type_is('app', 'ledger_accounts', 'normal_side', 'app.entry_side', 'normal side type exact');
SELECT col_type_is('app', 'ledger_accounts', 'is_system', 'boolean', 'is system type exact');
SELECT col_type_is('app', 'ledger_accounts', 'is_active', 'boolean', 'is active type exact');
SELECT hasnt_column('app', 'ledger_accounts', 'status', 'ledger status absent');
SELECT hasnt_column('app', 'ledger_accounts', 'version_number', 'ledger version absent');
SELECT hasnt_column('app', 'ledger_accounts', 'created_at', 'ledger created at absent');
SELECT hasnt_column('app', 'ledger_accounts', 'updated_at', 'ledger updated at absent');
SELECT hasnt_column('app', 'ledger_accounts', 'archived_at', 'ledger archived at absent');
SELECT fk_ok('app', 'ledger_accounts', 'financial_account_id', 'app', 'financial_accounts', 'id', 'ledger financial account foreign key exists');
SELECT fk_ok('app', 'ledger_accounts', 'currency_code', 'app', 'currencies', 'code', 'ledger currency foreign key exists');
SELECT has_index('app', 'ledger_accounts', 'ledger_accounts_code_uk', 'ledger code unique constraint exists');
SELECT has_index('app', 'ledger_accounts', 'ledger_accounts_financial_account_uk', 'one ledger account per financial account constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ledger_accounts_kind_financial_account_ck'), 'ledger kind financial account constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ledger_accounts_financial_asset_debit_ck'), 'financial asset debit constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ledger_accounts_system_managed_ck'), 'system managed constraint exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.ledger_accounts'::regclass), 'ledger accounts RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.ledger_accounts'::regclass), 'ledger accounts RLS forced');

SELECT has_table('app', 'exchange_rates', 'exchange rates table exists');
SELECT columns_are('app', 'exchange_rates', ARRAY[
  'id','rate_date','base_currency_code','quote_currency_code','rate_value',
  'source','source_reference','entered_by','created_at'
], 'exchange_rates has exact approved columns');
SELECT col_type_is('app', 'exchange_rates', 'id', 'uuid', 'exchange rate id type exact');
SELECT col_type_is('app', 'exchange_rates', 'rate_date', 'date', 'rate date type exact');
SELECT col_type_is('app', 'exchange_rates', 'base_currency_code', 'character(3)', 'base currency type exact');
SELECT col_type_is('app', 'exchange_rates', 'quote_currency_code', 'character(3)', 'quote currency type exact');
SELECT col_type_is('app', 'exchange_rates', 'rate_value', 'numeric(30,12)', 'rate value type exact');
SELECT col_type_is('app', 'exchange_rates', 'source', 'character varying(120)', 'source type exact');
SELECT col_type_is('app', 'exchange_rates', 'source_reference', 'text', 'source reference type exact');
SELECT col_type_is('app', 'exchange_rates', 'entered_by', 'uuid', 'entered by type exact');
SELECT col_type_is('app', 'exchange_rates', 'created_at', 'timestamp with time zone', 'created at type exact');
SELECT hasnt_column('app', 'exchange_rates', 'updated_at', 'exchange rate updated at absent');
SELECT hasnt_column('app', 'exchange_rates', 'deleted_at', 'exchange rate deleted at absent');
SELECT hasnt_column('app', 'exchange_rates', 'archived_at', 'exchange rate archived at absent');
SELECT fk_ok('app', 'exchange_rates', 'base_currency_code', 'app', 'currencies', 'code', 'base currency foreign key exists');
SELECT fk_ok('app', 'exchange_rates', 'quote_currency_code', 'app', 'currencies', 'code', 'quote currency foreign key exists');
SELECT fk_ok('app', 'exchange_rates', 'entered_by', 'app', 'users', 'id', 'entered by foreign key exists');
SELECT has_index('app', 'exchange_rates', 'exchange_rates_exact_duplicate_uk', 'authoritative duplicate-rate constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exchange_rates_distinct_currency_ck'), 'distinct currency constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exchange_rates_rate_value_ck'), 'positive rate constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exchange_rates_source_ck'), 'nonblank source constraint exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.exchange_rates'::regclass), 'exchange rates RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.exchange_rates'::regclass), 'exchange rates RLS forced');
SELECT throws_ok($$ TRUNCATE app.ledger_accounts CASCADE $$, '23514', 'Ledger accounts cannot be truncated.', 'ledger truncate prevented');
SELECT throws_ok($$ TRUNCATE app.exchange_rates CASCADE $$, '23514', 'Exchange rates cannot be truncated.', 'exchange rate truncate prevented');
SELECT is_empty($$ SELECT id FROM app.ledger_accounts WHERE account_kind = 'CONTROL' $$, 'CONTROL accounts are supported but not seeded');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('account_balances','payments','expenses','transfers','currency_exchanges','refunds','reversals','adjustments')), 'excluded finance workflow tables remain absent');

SELECT * FROM finish();
ROLLBACK;
