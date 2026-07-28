# Package 09.1 Test Plan

## Automated tests included

### Static validation

`scripts/static_validate.py` checks:

- all eight migrations parse as PostgreSQL;
- exact Package 09.1 file count and order;
- required foundation tables exist in SQL;
- Package 13.1 financial accounts are present, while financial transactions, ledger entries, payments, expenses and balances remain absent;
- exact five role codes are present;
- forbidden roles/features are absent;
- last-owner guard and default-deny RLS exist;
- no application policy is introduced prematurely;
- Supabase TOML and CI YAML parse;
- no frontend implementation or real privileged secret is present.

Run:

```bash
python3 -m pip install pglast==7.2 PyYAML==6.0.2
python3 scripts/static_validate.py
```

### pgTAP schema suite

`00_package_09_1_schema.test.sql` verifies the schema, types, tables, columns, indexes and excluded tables.

### pgTAP constraint suite

`01_package_09_1_constraints.test.sql` verifies:

- exact five roles;
- one contractor singleton;
- unique Auth subject and email;
- immutable authentication subject;
- one-to-one user profile;
- multiple staff roles;
- no client/staff role mixing;
- active assignment uniqueness;
- only active Owner assignment/revocation actor;
- no self-role assignment after controlled bootstrap;
- last-owner role and deactivation protection;
- protected system role definitions;
- no hard deletion of users or user-role history;
- immutable revoked role history and no in-place reactivation.

### pgTAP default-deny suite

`02_package_09_1_default_deny.test.sql` verifies RLS and FORCE RLS on each table, no policies yet, and no direct anon/authenticated SELECT privilege.

### pgTAP Stage 13 Package 13.1 financial-account suites

`51_package_13_1_financial_accounts_schema.test.sql` verifies the exact approved `app.financial_account_type` enum, exact 17-column `app.financial_accounts` table, immutable global `FA-000001` account numbering, CASH/BANK metadata constraints, forced RLS, no financial-account status enum, no editable balance columns, and continued absence of ledger, transaction, balance, exchange-rate, payment, expense and transfer tables.

`52_package_13_1_financial_accounts_security.test.sql` verifies direct-DML revocation, service-role-only server wrappers, private function revocation, absence of Client/reserved-role financial-account RPCs, no broad RLS policies, no exposure of `encrypted_account_details` in list/detail outputs, and no change to `public.current_account()`.

`53_package_13_1_financial_accounts_operations.test.sql` verifies Owner/Admin create/update/activate/deactivate/archive/list/detail workflows, optimistic concurrency, immutable account numbers, masked activity logging, encrypted detail non-exposure, Client and Accountant denial, no hard deletion, and no ledger or financial workflow side effects.

Run all database tests:

```bash
supabase start
supabase db reset --local
supabase test db
supabase stop --no-backup
```

## Required review tests in the real repository

1. Apply migrations to an empty local Supabase database.
2. Apply the same migrations to a production-like staging clone containing only fictional data.
3. Verify `supabase migration list --local` matches the eight files.
4. Re-run reset twice to prove deterministic clean setup.
5. Attempt a second contractor insert.
6. Attempt duplicate Auth subject and case-variant email.
7. Attempt staff/client role mixing and self-assignment.
8. Attempt concurrent revocation/deactivation of the only two owners in separate sessions; exactly one owner must remain.
9. Verify anonymous/authenticated direct REST queries receive no data/permission.
10. Review query plans for active-user and active-role lookups.

## Package exit gate

All static checks and all pgTAP assertions must pass with no Critical/High defect before Package 09.2 begins.

## Stage 12 Package 12.1 Tests

Package 12.1 adds tests 48-50:

- `48_package_12_1_documents_schema.test.sql` verifies exact document enum/table columns, document numbering defaults, metadata constraints, link constraints, enabled foreign keys, disabled finance link targets, and excluded finance/storage/scanner objects.
- `49_package_12_1_documents_security.test.sql` verifies forced RLS, direct table default-deny behavior, approved RPC presence/grants, and absence of reserved-role document gateways.
- `50_package_12_1_documents_operations.test.sql` verifies Owner/Admin metadata creation, `DOC-000001`/`DOC-000002` numbering, immutable document numbers, constraint failures, finance-link rejection, client-visible metadata reads, cross-client denial, and archive hiding.

Static validation now also checks the 1128-1130 migration markers, tests 48-50, finance dependency safety, and excluded upload/download/Storage/signed URL/scanner/thumbnail/Flutter/Edge Function/notification/finance/reserved-role behavior.
