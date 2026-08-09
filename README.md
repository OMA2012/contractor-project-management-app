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

It now includes Stage 12 finalized-document lifecycle completion, the Stage 12 Package 12.3 ClamAV-compatible scan, quarantine and final publication gate, the Stage 12 Package 12.2 private Storage and secure file-access foundation, the Stage 14 Package 14.1 database foundation for Client Payments, the Stage 14 Package 14.2 Payment Request foundation, the Stage 14 Package 14.3 Payment Matching foundation, the Stage 15 Package 15.1 Project Expense foundation, the Stage 16 Package 16.1 Same-Currency Account Transfer foundation, and the Stage 17 Package 17.1 Currency Exchange foundation. Stage 12 lifecycle completion adds Owner/Admin archive logging, restore-to-private behavior backed by lifecycle Client-access privacy markers, immutable replacement/supersession history, normalized full-link business-context validation, lifecycle-aware Client access hiding, Owner/Admin historical reads, forced RLS, service-role-only gateways, and pgTAP coverage. No approved document-level Owner/Admin re-share operation currently exists to clear restored-private lifecycle privacy; restored documents remain Client-private until a future approved explicit sharing operation is added. Package 12.3 adds append-preserving scan attempts, Owner/Admin-triggered backend scanning through a ClamAV-compatible HTTPS adapter, logical quarantine for malicious results, fail-closed scanner-error handling, final object publication under `objects/<document_uuid>/<opaque-token>`, and final `app.documents`/`app.document_links` creation only after a clean scan. Package 12.2 adds the private `documents-private` bucket, temporary upload reservations, Owner/Admin upload authorization, trusted file validation, `AWAITING_SCAN` stop-state behavior, secure finalized-document access authorization and orphan invalidation foundation. Package 14.1 uses deterministic `CTRL-CLIENT-PAYMENT-<currency_code>` control accounts. Package 14.2 adds payment requests. Package 17.1 adds exact `app.currency_exchanges`, Owner/Admin draft/update/submit/reject/list/detail/different-Owner approval workflows, server-derived destination amounts using manual transaction-date business rates, optional Project association, full fee posting, deterministic `CTRL-FX-CLEARING-<currency_code>` and `CTRL-FX-FEE-<currency_code>` debit-normal controls, four-line conversion posting without fees, six-line posting with fees, forced RLS, service-role-only wrappers, and pgTAP tests. Stage 12 lifecycle completion does **not** add Flutter screens, galleries, notifications, cleanup jobs, public sharing, AI/video/DOCX/XLSX processing, staff-role activation, finance workflow changes, hard delete, Storage overwrite/delete, or scanner bypass. Package 12.3 does **not** commit a production scanner endpoint or credential; production operation fails closed until `DOCUMENT_SCANNER_URL` and `DOCUMENT_SCANNER_TOKEN` point to a real HTTPS adapter. Package 17.1 does **not** implement document-finance link activation, notifications, automatic rate retrieval, external banking, Flutter, Edge Functions, Flutter finance screens, Client access, reserved-role access, refunds, advanced reports, arbitrary journals, editable balances, partial reversals, sufficient-balance enforcement, or separate exchange numbering.

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

## Stage 12 - Storage Reconciliation Foundation

This workspace includes Stage 12 - Storage Reconciliation Foundation as a report-only database capability. It compares temporary upload reservations, private `documents-private` Storage objects, finalized documents, scan/quarantine state and photograph derivative metadata/objects through a service-role-only computed report.

It performs no physical Storage deletion and no business mutation. Retention durations, automatic physical deletion, quarantine disposal, cleanup cadence, cron/scheduling, stale scan timeout, stale image-processing timeout and automatic retry policy remain undecided and unimplemented.
