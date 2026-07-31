# Package 09.1 Test Plan

## Automated tests included

### Static validation

`scripts/static_validate.py` checks:

- all eight migrations parse as PostgreSQL;
- exact Package 09.1 file count and order;
- required foundation tables exist in SQL;
- Package 14.1 financial accounts, system-managed asset ledger accounts, manual exchange rates, central ledger structure, opening-balance posting, full reversals, controlled adjustments, and Client Payment posting are present, while payment request, matching, expense, transfer, currency-exchange business, refund, upload, document-finance activation, notification, Flutter and Edge Function workflows remain absent;
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

`51_package_13_1_financial_accounts_schema.test.sql` verifies the exact approved `app.financial_account_type` enum, exact 17-column `app.financial_accounts` table, immutable global `FA-000001` account numbering, CASH/BANK metadata constraints, forced RLS, no financial-account status enum, no editable balance columns, and continued absence of transaction, balance, payment, expense and transfer tables.

`52_package_13_1_financial_accounts_security.test.sql` verifies direct-DML revocation, service-role-only server wrappers, private function revocation, absence of Client/reserved-role financial-account RPCs, no broad RLS policies, no exposure of `encrypted_account_details` in list/detail outputs, and no change to `public.current_account()`.

`53_package_13_1_financial_accounts_operations.test.sql` verifies Owner/Admin create/update/activate/deactivate/archive/list/detail workflows, optimistic concurrency, immutable account numbers, masked activity logging, encrypted detail non-exposure, Client and Accountant denial, no hard deletion, and no excluded financial workflow side effects.

### pgTAP Stage 13 Package 13.2 ledger-account and exchange-rate suites

`54_package_13_2_ledger_accounts_schema.test.sql` verifies exact `app.ledger_account_kind` and `app.entry_side` enums, exact `app.ledger_accounts` and `app.exchange_rates` columns, one-asset-ledger and duplicate-rate constraints, forced RLS, append-only/delete guards, no seeded CONTROL rows, and continued absence of posting-side finance tables.

`55_package_13_2_ledger_accounts_security.test.sql` verifies direct-DML revocation, service-role-only Owner exchange-rate gateways, private helper revocation, no broad RLS policies, no Client or reserved-role ledger/rate RPCs, private conversion helper access, append-only rates, and no change to `public.current_account()`.

`56_package_13_2_ledger_accounts_operations.test.sql` verifies automatic `ASSET-FA-000001` ledger synchronization on financial-account create/update/lifecycle changes, idempotent sync, manual exchange-rate creation/list/detail behavior, exact duplicate-rate rejection, safe activity logging, conversion helper arithmetic/rejections, and Client/reserved-role denial.

### pgTAP Stage 13 Package 13.3 central-ledger and opening-balance suites

`57_package_13_3_financial_transactions_schema.test.sql` verifies exact financial-event, financial-transaction and ledger-entry enums, exact `app.financial_events`, `app.financial_transactions`, `app.ledger_entries` and `app.account_opening_balances` columns, FE/FT numbering, constraints, indexes, forced RLS, mutation guards, no editable balance columns, and continued absence of incomplete finance workflows.

`58_package_13_3_financial_transactions_security.test.sql` verifies direct-DML revocation, service-role-only Owner opening-balance and balance gateways, private helper revocation, no broad RLS policies, no Client or reserved-role central-ledger RPCs, trusted posting context enforcement, safe list/detail return shapes, and no change to `public.current_account()`.

`59_package_13_3_financial_transactions_operations.test.sql` verifies Owner/Admin opening-balance create/update/submit/reject/approve workflows, optimistic concurrency, different-Owner approval, atomic two-line posting, same-currency and multi-currency exchange-rate snapshots, posted-only dynamic balances, idempotent approval retry, immutable posted records, safe failure without partial posting, and Client/reserved-role denial.

### pgTAP Stage 13 Package 13.4 financial-correction suites

`60_package_13_4_financial_corrections_schema.test.sql` verifies exact `app.adjustment_direction` values, exact `app.financial_reversals` and `app.financial_adjustments` columns, full-reversal-only and positive-amount constraints, subtype FKs, forced RLS, correction posting contexts, no correction status enum, no `REVERSED` status, and continued absence of excluded finance workflows.

`61_package_13_4_financial_corrections_security.test.sql` verifies private Owner/Admin correction functions, service-role-only server gateways, direct-DML revocation, private helper revocation, no broad RLS policies, no Client or reserved-role correction RPCs, and no change to `public.current_account()`.

`62_package_13_4_financial_corrections_operations.test.sql` verifies reversal of opening-balance and reversal transactions, repeated full-reversal prevention, exact opposite ledger totals, original history immutability, adjustment increase/decrease, optional and linked adjusted-transaction references, deterministic `CTRL-ADJUSTMENT-<currency_code>` accounts, exchange-rate snapshots, different-Owner approval, rejection without ledger effect, idempotent approval retry, posted-only balance effects, rollback on missing rate, and Client/reserved-role denial.

### pgTAP Stage 14 Package 14.1 Client Payment suites

`63_package_14_1_client_payments_schema.test.sql` verifies the exact approved 13-column `app.client_payments` schema, data types, defaults, FKs, one subtype row per event, RLS, immutability triggers, forbidden columns, and the narrow `client_payment_posting` ledger context while preserving Stage 13 contexts.

`64_package_14_1_client_payments_security.test.sql` verifies direct-DML revocation, no broad policies, private helper revocation, service-role-only Owner gateways, authenticated-only current-Client gateways, Client-safe return shapes, no Client account-selection/approval/rejection/internal-note gateways, no Accountant/reserved-role activation, no document-link or notification producer behavior, and no `public.current_account()` change.

`65_package_14_1_client_payments_operations.test.sql` verifies Owner draft/update/submit/reject/approve, Client direct submission as `SUBMITTED`, narrow Owner verification of Client-submitted payments, forbidden Client-submitted fact mutation, Project/Client identity, account/currency/date/amount validation, normalized duplicate behavior, different-Owner approval, exact two-line posting, same-currency and multi-currency snapshots, idempotent approval, rollback on missing rate, posted-only balances and Project totals, immutable payments, Client-safe own-payment reads, cross-Client denial, reserved-role denial, and explicit exclusions.

### pgTAP Stage 14 Package 14.2 Payment Request suites

`66_package_14_2_payment_requests_schema.test.sql` verifies the exact approved `app.payment_request_status` enum order, exact 20-column `app.payment_requests` schema, data types, defaults, FKs, checks, `PREQ-000001` numbering sequence, indexes, forced RLS, trusted mutation/delete/truncate guards and forbidden columns.

`67_package_14_2_payment_requests_security.test.sql` verifies direct table and sequence revocation, no broad policies, private helper revocation, service-role-only Owner gateways, authenticated-only current-Client gateways, Client-safe return shapes, no Client mutation/status gateways, no reserved-role activation, no financial/ledger/notification side effects and no `public.current_account()` change.

`68_package_14_2_payment_requests_operations.test.sql` verifies Owner create/update/send/cancel, optimistic concurrency, active currency and date validation, contractor-local-date behavior, `PREQ` numbering exhaustion, Client draft hiding, own sent/cancelled visibility, cross-Client denial, explicit first-view acknowledgement, idempotent view logging, effective overdue without read mutation, Owner overdue refresh, derived paid/remaining values when no matches exist, terminal cancellation, direct-DML denial, no manual `PARTIALLY_PAID`/`PAID` transition, reserved-role denial and continued absence of uploads, document activation, notifications, financial events, transactions and ledger entries.

`69_package_14_3_payment_matches_schema.test.sql` verifies the exact approved `app.payment_match_status` enum order, exact 14-column `app.payment_matches` schema, data types, defaults, FKs, state-field checks, unique payment/request pair, forced RLS, trusted mutation/delete/truncate guards and forbidden columns.

`70_package_14_3_payment_matches_security.test.sql` verifies direct table revocation, private helper revocation, service-role-only Owner gateways, no authenticated raw-match gateways, no reserved-role activation, Client request response safety, no generic match status setter and continued absence of excluded finance workflows.

`71_package_14_3_payment_matches_operations.test.sql` verifies Owner draft creation, creator-only compare-and-lock draft update, different-Owner approval, idempotent approval, controlled draft/approved voiding, pair uniqueness after void, capacity checks, Project/Client/currency eligibility, derived payment availability and request paid/remaining values, request status synchronization, partial-overdue precedence, Client-safe aggregate balances, reversal-chain parity, no ledger/financial side effects, immutable history and safe activity logs.

### pgTAP Stage 16 Package 16.1 Account Transfer suites

`75_package_16_1_account_transfers_schema.test.sql` verifies the exact nine-column `app.account_transfers` schema, required FKs, positive amount and distinct-account checks, subtype integrity, contractor-level null Project/Client design, same-currency/date validation, approved immutability, no transfer-number/status/approval/timestamp/version/Project/Client/exchange/fee/document/archive/delete/editable-balance columns, forced RLS and the narrow `account_transfer_posting` ledger context while preserving existing posting contexts.

`76_package_16_1_account_transfers_security.test.sql` verifies service-role-only Owner/Admin transfer wrappers, direct-DML revocation from all runtime roles including `service_role`, private helper revocation, no broad RLS policy, no Client transfer gateway, no Project Manager/Accountant/Site Supervisor gateway, safe list return shape and no `public.current_account()` modification.

`77_package_16_1_account_transfers_operations.test.sql` verifies Owner/Admin draft create/update/submit/reject/list/detail/different-Owner approve workflows, stale-version rejection, self-approval denial, duplicate protection, null-reference false-positive avoidance, saved contractor reporting-currency snapshot, transaction-date rate snapshot when needed, exactly two ledger lines, debit destination financial asset, credit source financial asset, no transfer control account, source decrease, destination increase, unrelated account unchanged, combined currency total preservation, reporting net zero, no Project-balance effect, idempotent approval retry, posted immutability, existing full-reversal compatibility, negative source balance allowance and safe activity logs.

### pgTAP Stage 17 Package 17.1 Currency Exchange suites

`78_package_17_1_currency_exchanges_schema.test.sql` verifies the exact 19-column `app.currency_exchanges` schema, approved FKs and checks, absence of forbidden subtype columns and exchange-number sequences, forced RLS, signed/derived ledger snapshot compatibility, and the narrow `currency_exchange_posting` ledger context while preserving previous posting contexts.

`79_package_17_1_currency_exchanges_security.test.sql` verifies service-role-only Owner/Admin Currency Exchange wrappers, direct-DML revocation from all runtime roles including `service_role`, private helper revocation, no broad RLS policy, no Client or reserved-role gateway, safe list shape, no `public.current_account()` modification, and continued absence of uploads, notifications and refunds.

`80_package_17_1_currency_exchanges_operations.test.sql` verifies contractor-level and optional Project-associated exchanges, saved reporting currency, canonical multiply/divide directions, server-derived destination amount, ROUND_HALF_UP signed rounding result, zero-fee normalization, source-account default fee, separate fee account validation, draft/update/submit/reject/approve, stale-version and self-approval denial, exact four-line and six-line postings, source/destination/fee account effects, reporting net zero, idempotent approval, immutability, full-reversal compatibility, negative-balance allowance and safe activity logging.

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

Static validation now also checks the 1128-1130 migration markers, tests 48-50, the 1134-1136 Package 13.2 markers, tests 54-56, the 1137-1139 Package 13.3 markers, tests 57-59, the 1140-1142 Package 13.4 markers, tests 60-62, the 1143-1145 Package 14.1 markers, tests 63-65, the 1146-1148 Package 14.2 markers, tests 66-68, the 1155-1157 Package 16.1 markers, tests 75-77, the 1158-1160 Package 17.1 markers, tests 78-80, finance dependency safety, and excluded upload/download/Storage/signed URL/scanner/thumbnail/Flutter/Edge Function/notification/reserved-role behavior.
## Stage 15 Package 15.1

Run after applying migrations:

```bash
supabase db reset --local
supabase test db
python scripts/static_validate.py
cd supabase/functions && deno task test
cd ../../app && dart format --set-exit-if-changed . && flutter analyze && flutter test
git diff --check
git status --short
```

Package 15.1 coverage is in pgTAP suites 72-74: schema/seeds/RLS, grants and forbidden access, Owner category workflow, draft/update/submit/reject/list/detail, different-Owner approval, two-line Project Expense ledger posting, duplicate protection and safe activity logs.
