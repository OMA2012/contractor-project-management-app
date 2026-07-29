# Stage 09 — Package 09.1

This review package implements only the first database foundation for the Contractor Project Management App:

- repository and environment verification tooling;
- PostgreSQL/Supabase extensions and identity enums;
- the approved currency lookup required by the contractor singleton;
- `app.contractor_profiles`;
- `app.users` and one-to-one `app.user_profiles`;
- the exact five predefined roles;
- append-preserving `app.user_roles` assignments;
- structural integrity, role-mixing and last-active-owner guards;
- default-deny RLS preparation;
- pgTAP tests and a database-only CI gate.

It now includes the Stage 13 Package 13.3 database foundation for Owner/Admin-managed CASH and BANK financial accounts, system-managed asset ledger accounts, manual exchange rates, central financial-event/transaction/ledger-entry structure, and opening-balance posting. It does **not** implement client payments, payment requests, project expenses, transfers, currency-exchange business workflows, refunds, reversals, adjustments, finance notifications, Flutter finance screens, Edge Functions, documents, or financial reports.

## Integration commands

From the actual Phase 0 repository root:

```bash
git checkout -b stage09/package-09-1
rsync -av --exclude '.git' /path/to/contractor_stage09_package_09_1/ ./
git status --short
git diff --check
bash scripts/verify_environment.sh "$PWD"
python3 -m pip install pglast==7.2 PyYAML==6.0.2
python3 scripts/static_validate.py
git add .github/workflows/package-09-1-database.yml \
  .env.example .gitignore README.md docs scripts supabase
git commit -m "feat(db): add Stage 09 Package 09.1 identity foundation"
```

## Local database commands

Prerequisites: Docker Desktop/Engine and Supabase CLI.

```bash
supabase start
supabase db reset --local
supabase test db
supabase migration list --local
supabase status
```

Stop the local stack without preserving local test data:

```bash
supabase stop --no-backup
```

## Review rule

Do not proceed to Package 09.2 until:

1. the overlay is reconciled with the real Phase 0 repository;
2. clean migration application succeeds;
3. all three pgTAP suites pass;
4. the static scope/secret checks pass;
5. the database reviewer accepts the schema and the documented deviations.
