# Migration Manifest — Package 09.1

| Order | File | Purpose | Dependencies | Forward-fix / rollback approach | Required test |
|---:|---|---|---|---|---|
| 1 | `20260721220100_0901_extensions_and_identity_types.sql` | Adds `pgcrypto`, `citext`, `app`, `user_status`, and `user_type` | Supabase PostgreSQL | Before shared use, reset local DB. After merge, never edit; add a forward migration | Schema test confirms schema/types |
| 2 | `20260721220200_0902_currency_reference.sql` | Creates approved currency reference dependency and seeds USD/SAR/YER | 0901 | Forward-fix currency metadata; do not drop referenced rows | Schema and seed assertions |
| 3 | `20260721220300_0903_contractor_profiles.sql` | Creates protected single-contractor row structure | 0902 | Forward migration; singleton data must not be deleted | Singleton and FK tests |
| 4 | `20260721220400_0904_users_and_user_profiles.sql` | Creates application identity linked to Auth and one-to-one personal profile; completes contractor actor FKs | 0901, 0903, Supabase Auth schema | Forward migration; identities are not hard deleted | Uniqueness, lifecycle, one-to-one, immutable auth subject |
| 5 | `20260721220500_0905_predefined_roles.sql` | Creates and seeds exactly five roles | 0901 | Forward-fix only; stable role codes are never renamed/deleted | Exact role allowlist and immutability |
| 6 | `20260721220600_0906_user_role_assignments.sql` | Creates append-preserving role assignment/revocation history | 0904, 0905 | Forward-fix; revoke rather than delete | Active uniqueness and lifecycle |
| 7 | `20260721220700_0907_foundation_integrity_triggers.sql` | Adds version timestamps, role/type guards, owner-only actor validation, last-owner protection, immutable role history, and hard-delete guards | 0903–0906 | Replace functions/triggers in a new migration; do not edit applied file | Constraint suite |
| 8 | `20260721220800_0908_default_deny_rls.sql` | Enables/forces RLS and revokes direct anon/authenticated access without adding policies | 0902–0907 | Later package adds reviewed policies/grants in a new migration | Default-deny suite |

| 51 | `20260724103400_1131_financial_account_schema.sql` | Adds Package 13.1 financial-account type, immutable global FA numbering, exact financial account table, guards, RLS and direct-DML revocation | 0902, 0904, 0911, 0913 | Forward-fix only; account rows are retained and never hard-deleted | 51 schema suite |
| 52 | `20260724103500_1132_financial_account_functions.sql` | Adds Owner/Admin-only trusted financial-account create/update/activate/deactivate/archive/list/detail functions and service wrappers | 1131, owner authorization, activity logs | Replace functions in forward migration; no Client or reserved-role access | 52 security and 53 operations suites |
| 53 | `20260724103600_1133_financial_account_grants.sql` | Grants service-role execution on server wrappers only and keeps direct table/private function access revoked | 1132 | Forward-fix grants only | 52 security suite |

Every file is transactional. Production correction is forward-fix first; never rewrite an already applied migration.

## Stage 12 Package 12.1 Addendum

| Order | File | Purpose | Dependencies | Forward-fix / rollback approach | Required test |
|---:|---|---|---|---|---|
| 1128 | `20260724103100_1128_documents.sql` | Adds metadata-only document status, document types, document metadata, document links, global document numbering, constraints, indexes, RLS and mutation guards | Packages 09-11; existing `app.users`, `app.clients`, `app.projects`, `app.tasks`, `app.progress_updates` | Forward migration only; do not rewrite after apply. Finance link FKs are deferred until finance tables exist | Test 48 |
| 1129 | `20260724103200_1129_document_functions.sql` | Adds Owner/Admin metadata RPCs and client-visible metadata list RPC | 1128 plus first-release Owner/Admin and Client identity gates | Forward-fix functions only; no Storage, upload, signed URL, scanner, UI, notification or finance behavior | Tests 49-50 |
| 1130 | `20260724103300_1130_document_grants.sql` | Revokes direct table access and grants only service owner RPCs plus authenticated client read RPC | 1129 | Forward-fix grants in a new migration | Test 49 |

Package 12.1 preserves all eight approved `document_links` target columns. Only client, project, task and progress-update targets are enabled. Finance target columns remain nullable but constrained to `NULL` until later forward migrations add their tables and foreign keys.
