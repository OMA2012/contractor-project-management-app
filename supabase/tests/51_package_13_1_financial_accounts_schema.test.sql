BEGIN;
SELECT plan(48);

SELECT has_type('app', 'financial_account_type', 'financial account type enum exists');
SELECT results_eq(
  $$ SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'app' AND t.typname = 'financial_account_type' ORDER BY enumsortorder $$,
  $$ VALUES ('CASH'::name), ('BANK'::name) $$,
  'financial account type enum values are exact'
);
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'app' AND t.typname = 'financial_account_status'), 'financial account status enum is absent');
SELECT has_table('app', 'financial_accounts', 'financial accounts table exists');
SELECT columns_are('app', 'financial_accounts', ARRAY[
  'id','account_number','name','account_type','currency_code','bank_name',
  'masked_account_identifier','encrypted_account_details','is_active','notes',
  'archived_at','archived_by','created_at','created_by','updated_at','updated_by',
  'version_number'
], 'financial_accounts has exact approved 17 columns');
SELECT col_type_is('app', 'financial_accounts', 'account_number', 'character varying(50)', 'account number type exact');
SELECT col_type_is('app', 'financial_accounts', 'name', 'character varying(160)', 'name type exact');
SELECT col_type_is('app', 'financial_accounts', 'account_type', 'app.financial_account_type', 'account type exact');
SELECT col_type_is('app', 'financial_accounts', 'currency_code', 'character(3)', 'currency code type exact');
SELECT col_type_is('app', 'financial_accounts', 'bank_name', 'character varying(160)', 'bank name type exact');
SELECT col_type_is('app', 'financial_accounts', 'masked_account_identifier', 'character varying(80)', 'masked identifier type exact');
SELECT col_type_is('app', 'financial_accounts', 'encrypted_account_details', 'bytea', 'encrypted details type exact');
SELECT col_type_is('app', 'financial_accounts', 'is_active', 'boolean', 'is active type exact');
SELECT col_type_is('app', 'financial_accounts', 'notes', 'text', 'notes type exact');
SELECT col_type_is('app', 'financial_accounts', 'archived_at', 'timestamp with time zone', 'archived at type exact');
SELECT col_type_is('app', 'financial_accounts', 'archived_by', 'uuid', 'archived by type exact');
SELECT col_type_is('app', 'financial_accounts', 'created_at', 'timestamp with time zone', 'created at type exact');
SELECT col_type_is('app', 'financial_accounts', 'created_by', 'uuid', 'created by type exact');
SELECT col_type_is('app', 'financial_accounts', 'updated_at', 'timestamp with time zone', 'updated at type exact');
SELECT col_type_is('app', 'financial_accounts', 'updated_by', 'uuid', 'updated by type exact');
SELECT col_type_is('app', 'financial_accounts', 'version_number', 'integer', 'version type exact');
SELECT hasnt_column('app', 'financial_accounts', 'status', 'status column absent');
SELECT hasnt_column('app', 'financial_accounts', 'display_name', 'display name absent');
SELECT hasnt_column('app', 'financial_accounts', 'current_balance', 'current balance absent');
SELECT hasnt_column('app', 'financial_accounts', 'opening_balance', 'opening balance absent');
SELECT hasnt_column('app', 'financial_accounts', 'ledger_account_id', 'ledger account id absent');
SELECT hasnt_column('app', 'financial_accounts', 'bank_account_holder_name', 'removed bank holder absent');
SELECT hasnt_column('app', 'financial_accounts', 'bank_account_last_four', 'removed bank last four absent');
SELECT hasnt_column('app', 'financial_accounts', 'bank_branch', 'removed bank branch absent');
SELECT hasnt_column('app', 'financial_accounts', 'bank_swift_code', 'removed bank swift absent');
SELECT hasnt_column('app', 'financial_accounts', 'bank_iban_last_four', 'removed bank iban absent');
SELECT hasnt_column('app', 'financial_accounts', 'internal_notes', 'internal notes absent');
SELECT hasnt_column('app', 'financial_accounts', 'activated_at', 'activated at absent');
SELECT hasnt_column('app', 'financial_accounts', 'deactivated_at', 'deactivated at absent');
SELECT fk_ok('app', 'financial_accounts', 'currency_code', 'app', 'currencies', 'code', 'currency foreign key exists');
SELECT fk_ok('app', 'financial_accounts', 'archived_by', 'app', 'users', 'id', 'archived by foreign key exists');
SELECT fk_ok('app', 'financial_accounts', 'created_by', 'app', 'users', 'id', 'created by foreign key exists');
SELECT fk_ok('app', 'financial_accounts', 'updated_by', 'app', 'users', 'id', 'updated by foreign key exists');
SELECT has_index('app', 'financial_accounts', 'financial_accounts_account_number_uk', 'account number unique constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'financial_accounts_account_number_ck'), 'account number format constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'financial_accounts_cash_bank_metadata_ck'), 'cash bank metadata constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'financial_accounts_archive_pair_ck'), 'archive pair constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'financial_accounts_archived_inactive_ck'), 'archived inactive constraint exists');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'financial_accounts' AND indexname = 'financial_accounts_owner_list_order_idx'), 'owner list order index exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.financial_accounts'::regclass), 'financial accounts RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.financial_accounts'::regclass), 'financial accounts RLS forced');
SELECT throws_ok($$ TRUNCATE app.financial_accounts CASCADE $$, '23514', 'Financial accounts cannot be truncated.', 'truncate prevented');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name IN ('account_balances','payments','expenses','transfers')), 'later financial workflow objects remain absent');

SELECT * FROM finish();
ROLLBACK;
