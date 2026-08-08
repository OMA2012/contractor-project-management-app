# Approved Database Design Review — Package 09.1

## Decisions followed

1. PostgreSQL is authoritative and objects use the `app` schema, UUID primary keys, explicit constraints, UTC `timestamptz`, and `ON DELETE RESTRICT` identity/history relationships.
2. The application is single-contractor. `app.contractor_profiles` is a singleton using `singleton_key = 1`; no organisation or tenant switching is introduced.
3. Supabase `auth.users` remains the authentication provider. `app.users` stores the application identity and lifecycle; `app.user_profiles` stores personal/business profile data. Passwords and authentication secrets are not duplicated.
4. The five global roles are seeded with stable codes: `owner_admin`, `project_manager`, `accountant`, `site_supervisor`, and `client`.
5. Multiple approved staff roles are allowed. A client identity may hold only `client`; staff/client role mixing is rejected.
6. Role assignment rows are retained historically. The active pair is unique through a partial index rather than overwriting an earlier revoked row.
7. The last active Owner/Administrator is protected on both role revocation and user deactivation, with a transaction-scoped advisory lock to close the concurrent-removal race.
8. Package 09.1 uses default-deny RLS and no application-facing policies. Authorised SELECT/write policies and protected role-management functions belong to a later reviewed package.

## Narrow interpretation and documented differences

### `users` plus `user_profiles`

The Stage request lists minimum profile fields in one conceptual list, while the approved ERD separates security identity from the personal profile. This package follows the ERD separation.

### Role codes

The database specification describes uppercase conceptual role values in one status table, while the Stage 09 requirements recommend stable lowercase codes. This package uses the already approved Stage 09 lowercase codes and exact display labels.

### `user_roles` uniqueness

The data dictionary says the user/role pair is unique, but the same requirements require retained role history. A permanent pair unique constraint would prevent append-preserving re-assignment after revocation. Package 09.1 therefore uses one unique **active** assignment and preserves earlier revoked rows.

### Currency table

`contractor_profiles.default_reporting_currency_code` has an approved foreign key to the currency lookup. The lookup and USD/SAR/YER rows are included only as a dependency. No financial account, exchange-rate, transaction, balance, payment, expense, or ledger table is created.

## Deferred to Package 09.2 or later

- invitation and activation functions;
- activity-log writes for role changes;
- authenticated RLS policies;
- owner role-management RPC/Edge Function;
- staff profile read view;
- clients, client logins, projects and assignments;
- frontend authentication and routing.

## Stage 12 Package 12.4 Design Notes

Package 12.4 follows the already approved Package 12.1 document model by activating the reserved finance target columns instead of introducing a second document-link table. Finance document links use one exact target per document or upload reservation and retain the existing scan-before-publication workflow from Package 12.3.

The Client upload surface is intentionally narrower than the Owner/Admin surface and is mediated by the Edge storage handler. A Client may submit only `BANK_TRANSFER_EVIDENCE` for a Client Payment that was submitted by that same authenticated Client and is still in the submitted financial state. The Client cannot choose document type, visibility, alternate finance targets, storage key, trusted hash facts, scanner state or finalization behavior.

Private Client transfer evidence is authorized for direct access by its submitting Client after clean finalization, but it is not part of the generic client-visible document list. Project Expense and Currency Exchange targets remain Owner/Admin document targets only for Client visibility purposes.
