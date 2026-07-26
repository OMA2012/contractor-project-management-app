# Commands — Package 09.1

## Verify the actual repository and tools

```bash
bash scripts/verify_environment.sh "$PWD"
```

A nonzero result means at least one required repository/tool/config check is missing. The script deliberately treats the missing Flutter/Dart toolchain as a failure because Phase 0 readiness must ultimately prove the full repository, although Package 09.1 itself changes only the database.

## Static validation

```bash
python3 -m pip install pglast==7.2 PyYAML==6.0.2
python3 scripts/static_validate.py
```

## Local Supabase migration and tests

```bash
supabase start
supabase db reset --local
supabase test db
supabase migration list --local
supabase status
```

Use `supabase status` to discover the local Mailpit URL. The local Supabase CLI stack captures Auth email through Mailpit.

## Stage 09 Package 09.2 Edge helper checks

The shared Edge Function helper layer is pinned to:

- Deno `2.9.4`
- `@supabase/server@1.4.1`
- `@supabase/supabase-js@2.110.8`

```bash
cd supabase/functions
deno task fmt
deno task lint
deno task check
deno task test
deno task cache:frozen
```

Local Auth email OTP/invitation expiry is configured with:

```toml
[auth.email]
otp_expiry = 604800
```

Hosted Supabase Auth must be configured with an equivalent seven-day email OTP/invitation expiry before production deployment. This checkpoint does not alter hosted configuration.

Authenticated Stage 09.2C3 Edge Functions are expected to use handler-owned authentication and response behavior: platform JWT verification disabled, strict handler Origin checks for non-OPTIONS requests, and `withSupabase({ auth: "user" })` for verified claims. Local Kong may intercept preflight and add permissive CORS headers, so hosted preflight and handler CORS behavior remain a required production-readiness verification gate. CORS controls browser access to responses; it does not replace JWT verification or database authorization.

The shared helpers derive the JWKS endpoint from the trusted `SUPABASE_URL` as `{SUPABASE_URL}/auth/v1/.well-known/jwks.json` and pass that URL explicitly to `withSupabase`. Hosted project URLs must use HTTPS. Local development permits HTTP only for localhost, `127.0.0.1`, and Supabase local Edge runtime Docker hosts. Do not configure or accept a request-supplied JWKS URL. For local serving, create a temporary UTF-8 no-BOM env file containing only non-Supabase custom values such as:

```text
APP_BASE_URL=http://localhost:3000
```

Then run `supabase functions serve --env-file <temporary-no-bom-env-file>` from the repository root. The Supabase CLI injects its own local `SUPABASE_*` values; do not place service credentials in the temporary env file.

Stage 09 Package 09.2C3C adds only these Client invitation functions:

- `create-client-invitation`
- `resend-client-invitation`
- `revoke-client-invitation`
- `accept-client-invitation`

Each function has `verify_jwt = false` in local Supabase config so the handler can own strict CORS, authentication, and safe error responses. This does not make any mutation public: every non-OPTIONS request must validate the configured application Origin, authenticate with `withSupabase({ auth: "user" })`, derive the actor only from verified JWT claims, and authorize only through `public.server_*` database gateways before any privileged operation.

Request contracts:

```json
{ "email": "client@example.com" }
```

```json
{ "invited_user_id": "uuid" }
```

```json
{ "invitation_id": "uuid", "revoke_reason": "text" }
```

```json
{ "token": "base64url-token", "full_name": "Client Name" }
```

Create ordering is `auth.admin.generateLink({ type: "invite", ... })`, then `public.server_create_client_invitation(...)`, then `auth.admin.inviteUserByEmail(...)`. Resend uses the same safe delivery order after `public.server_client_identity_context(...)`: refresh Auth invite state without sending, replace the application token digest in the database, then send exactly one email.

If database creation fails after `generateLink`, retain the unconfirmed Auth identity for safe future reuse. If email delivery fails after database success, the pending invitation remains recoverable through resend. Mailpit tests must assert message counts and safe redirect host/path only; never snapshot full email bodies, action links, OTPs, application tokens, token digests, JWTs, or service credentials.

Hosted CORS and preflight behavior remains a production verification gate before deployment.

Stage 09 Package 09.2C3D adds only these Client account lifecycle functions:

- `suspend-client-account`
- `reactivate-client-account`
- `disable-client-account`

Each lifecycle function uses the same handler-owned authentication model: `verify_jwt = false` in local Supabase config, strict handler Origin validation, and `withSupabase({ auth: "user" })` for every non-OPTIONS request. The Owner Auth subject is derived only from verified claims. Request JSON must never supply actor IDs, roles, user types, or lifecycle statuses.

All three lifecycle requests use:

```json
{ "client_user_id": "uuid", "reason": "text" }
```

Database lifecycle state remains authoritative for application access. Supabase Auth banning is defense-in-depth and must not replace `public.current_account()` or database gateway authorization checks. A suspended or disabled Client must receive no application access even when presenting an existing JWT.

Suspend and disable use database-first ordering: retrieve minimal trusted Client context with `public.server_client_identity_context(...)`, call `public.server_suspend_client_account(...)` or `public.server_disable_client_account(...)`, then apply the long Auth ban with `auth.admin.updateUserById(..., { ban_duration: "876000h" })`. If Auth banning fails after database success, preserve the database state and return a safe consistency warning.

Reactivate uses Auth-first ordering: retrieve trusted suspended Client context, remove the Auth ban with `auth.admin.updateUserById(..., { ban_duration: "none" })`, then call `public.server_reactivate_client_account(...)`. If database reactivation fails after Auth unban, attempt to restore the long Auth ban and report a safe compensation status without claiming the account is active.

Disabled status is terminal in this checkpoint. Do not hard-delete Auth or application identities, do not call `deleteUser`, and do not reactivate disabled Clients.

Stage 09 Package 09.2C3E adds only the guarded first-Owner operator script:

- `scripts/bootstrap_production_owner.mjs`

It is not an Edge Function and does not add Flutter activation UI. Run it with the existing Deno function configuration and lock file:

```bash
deno run \
  --config supabase/functions/deno.json \
  --lock supabase/functions/deno.lock \
  --frozen \
  --allow-env \
  --allow-net \
  scripts/bootstrap_production_owner.mjs
```

Required environment variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `APP_BASE_URL`
- `BOOTSTRAP_OWNER_EMAIL`
- `BOOTSTRAP_OWNER_FULL_NAME`
- `BOOTSTRAP_CONFIRMATION`

`BOOTSTRAP_CONFIRMATION` must equal exactly:

```text
CREATE FIRST CONTRACTOR OWNER
```

`SUPABASE_SERVICE_ROLE_KEY` is server/operator-only and must never be placed in Flutter or browser bundles. `APP_BASE_URL` must be HTTPS outside localhost development. Production redirect allowlists must include the fixed Owner activation route:

```text
{APP_BASE_URL}/owner/activate
```

Bootstrap delivery ordering is `auth.admin.generateLink({ type: "invite", ... })`, then `public.server_bootstrap_first_owner(...)`, then one `auth.admin.inviteUserByEmail(...)` attempt only after database success. If delivery fails after database bootstrap, rerun the same guarded command; migration 0917 exposes `public.server_first_owner_delivery_context(...)` so the script may send again only when the same Auth subject and normalized email are proven to be the still-invited, inactive, unexpired first Owner. A generic already-bootstrapped error is never permission to send email.

If the pending first-Owner invitation has expired, the script does not send email, replace tokens, or mutate the database. A separate approved recovery operation is required.

Safe script exit codes:

- `0`: bootstrap or same-identity recovery proven, delivery confirmed
- `1`: validation, configuration, or confirmation failure
- `2`: Auth invitation preparation failure
- `3`: database bootstrap rejected and same-identity recovery not proven
- `4`: email delivery failed or remained uncertain
- `5`: invitation expired; separate recovery required
- `6`: unexpected safely handled internal failure

The script may print masked email, Auth user ID, application Owner user ID, invitation ID, expiry timestamp, delivery status, and exit code. It must never print the service-role key, JWTs, OTPs, raw application tokens, token digests, Auth hashed tokens, complete action links, or complete URLs containing tokens.

Future activation flow: the Owner authenticates through the Supabase invitation email, Supabase redirects to `{APP_BASE_URL}/owner/activate`, and the authenticated application calls `public.activate_current_invited_owner()`. Database preconditions determine whether the account becomes active. Hosted seven-day Auth expiry, redirect allowlist, and CORS verification remain production gates.

Script checks:

```bash
deno cache --config supabase/functions/deno.json --lock supabase/functions/deno.lock --frozen scripts/bootstrap_production_owner.mjs
deno fmt --check --config supabase/functions/deno.json scripts/bootstrap_production_owner.mjs scripts/bootstrap_production_owner_test.mjs
deno lint --config supabase/functions/deno.json scripts/bootstrap_production_owner.mjs scripts/bootstrap_production_owner_test.mjs
deno check --config supabase/functions/deno.json --lock supabase/functions/deno.lock --frozen scripts/bootstrap_production_owner.mjs scripts/bootstrap_production_owner_test.mjs
deno test --config supabase/functions/deno.json --lock supabase/functions/deno.lock --frozen --allow-env scripts/bootstrap_production_owner_test.mjs
```

## Stage 09 Package 09.2 Local E2E Release Gate

Package 09.2 includes a manual local-only authentication integration harness:

```bash
deno run \
  --config supabase/functions/deno.json \
  --lock supabase/functions/deno.lock \
  --frozen \
  --allow-env \
  --allow-net \
  --allow-read \
  --allow-write \
  --allow-run \
  scripts/package_09_2_e2e_local.mjs
```

Prerequisites:

- Docker is running.
- Local Supabase is available; the harness runs `supabase db reset --local` before and after the flow.
- The harness discovers API, function and Mailpit URLs from `supabase status`.
- The harness starts all seven Package 09.2 Client Edge Functions automatically from the repository root with a temporary UTF-8 no-BOM env file containing only `APP_BASE_URL=http://localhost:3000`.

The harness is intentionally not part of normal pull-request CI. CI runs only the mocked Deno tests for `scripts/package_09_2_e2e_local_test.mjs`; the full Docker/Mailpit E2E run is a manual local release gate.

Safe output policy: the harness prints only scenario progress and assertion results. It must not print service-role keys, JWTs, OTPs, Auth verification tokens, application invitation tokens, token hashes, complete Mailpit bodies, or complete action links. Temporary files are removed, function-serving processes started by the harness are stopped, Mailpit is cleared best-effort, and the local database is reset during cleanup.

Successful run summary should include:

- first Owner bootstrap and activation
- Client invitation creation and acceptance
- invitation resend with prior-token invalidation
- invitation revocation
- Client suspension, reactivation and terminal disabling
- Owner-only authorization and durable denied-operation activity logging

Exit codes:

- `0`: all Package 09.2 local E2E scenarios passed
- `1`: environment or local-safety validation failed
- `2`: Supabase reset/start/status failure
- `3`: Edge Function startup/readiness failure
- `4`: Owner bootstrap or activation failure
- `5`: Client invitation or acceptance failure
- `6`: resend or revocation failure
- `7`: lifecycle failure
- `8`: authorization or activity-log assertion failure
- `9`: cleanup failure
- `10`: unexpected safely handled failure

Package 09.2 does not add Flutter `/owner/activate` or `/accept-invitation` routes or invitation UI; those remain future UI work under the current acceptance criteria. Hosted redirect allowlists, hosted seven-day Auth expiry, and hosted CORS/preflight verification remain deployment gates.

## Stage 10 Package 10.1 Client Business Records

Package 10.1 adds only the Client business-record and portal-link database foundation. It does not add projects, project assignments, phases, milestones, tasks, staff invitations, staff activation, documents, identification-document fields, payments, expenses, financial accounts, ledger entries, editable balances, Flutter screens, or Edge Functions.

Client numbers are generated by PostgreSQL sequence `app.client_number_seq` as:

```text
CL-000001
CL-000002
CL-000003
```

The sequence starts at 1, increments by 1, has maximum 999999, does not cycle, and is formatted with six zero-padded digits. Sequence gaps after rolled-back transactions are acceptable. Client numbers are immutable and must never be generated with `MAX(...) + 1`.

`app.clients` contains exactly:

- `id`
- `client_number`
- `portal_user_id`
- `display_name`
- `legal_name`
- `email`
- `phone`
- `address`
- `status`
- `internal_notes`
- `is_active`
- `archived_at`
- `archived_by`
- `created_at`
- `created_by`
- `updated_at`
- `updated_by`
- `version_number`

Client status values are exactly `ACTIVE` and `INACTIVE`. Financial summaries such as total paid and outstanding amount are not stored as editable Client columns; future financial views must derive summaries from approved ledger entries.

Portal-link rules:

- a Client record can exist before a portal user is linked;
- `portal_user_id` is nullable and unique;
- one Client record has zero or one portal user;
- one portal user can be linked to at most one Client record;
- linking, replacement and unlinking are Owner-controlled operations;
- link targets must be active application users with `user_type = CLIENT`, `status = ACTIVE`, `is_active = true`, an active `client` role, and no active staff role;
- suspended, disabled, inactive, staff and reserved-role identities cannot be linked;
- archiving clears `portal_user_id` immediately and removes Client portal access;
- hard deletion is prohibited.

Owner/Administrator permissions are implemented through trusted database functions and service-only gateways. Owners may create Client records, list and view all Client records, update approved fields, view internal notes, link or replace a portal user, unlink a portal user, and archive Client records.

Client self-read is exposed only through:

```sql
public.current_client_record()
```

It derives identity from `auth.uid()` and returns a row only for the current active Client user's linked, active, non-archived Client record. Client-visible fields are limited to:

- `id`
- `client_number`
- `display_name`
- `legal_name`
- `email`
- `phone`
- `address`
- `status`

Clients never receive `internal_notes`, `portal_user_id`, actor audit fields, archive actor fields, or unrelated Client records. Reserved first-release staff roles remain unusable.

All Client mutations require optimistic concurrency through `expected_version_number`. A successful update, link, replacement, unlink, or archive increments `version_number` exactly once. Idempotent same-link and already-unlinked operations return deterministic no-change results without duplicate activity logs.

Central activity-log actions added by this package:

- `client_record_created`
- `client_record_updated`
- `client_portal_user_linked`
- `client_portal_user_unlinked`
- `client_portal_user_replaced`
- `client_record_archived`

Activity metadata must mask sensitive values such as email, phone, address, internal notes, portal user identifiers, Auth subjects, and raw request bodies.

## Stage 10 Package 10.2 Project Business Records

Package 10.2 adds only the Project business-record database foundation. It does not add project staff assignments, staff invitation or activation, Project Manager/Accountant/Site Supervisor access, phases, milestones, tasks, progress updates, completion calculations, documents, photographs, notifications, payment requests, payments, expenses, financial accounts, exchange rates, financial events, financial transactions, ledger entries, Project balances, Flutter screens, or Edge Functions.

Project numbers are generated by trusted PostgreSQL logic as:

```text
PRJ-YYYY-0001
```

The year is calculated from the contractor singleton `app.contractor_profiles.time_zone`, currently `Asia/Kuching`, not from the database server time zone. Numbering resets each contractor-local calendar year, uses four zero-padded digits, allows gaps, and is limited to 9,999 Projects per year. The generator uses a protected yearly counter and must never use `MAX(...) + 1`.

Project statuses are exactly:

- `DRAFT`
- `QUOTATION`
- `APPROVED`
- `ACTIVE`
- `ON_HOLD`
- `COMPLETED`
- `CANCELLED`
- `ARCHIVED`

Lifecycle transitions are exactly:

```text
DRAFT -> QUOTATION, APPROVED, CANCELLED
QUOTATION -> DRAFT, APPROVED, CANCELLED
APPROVED -> ACTIVE, CANCELLED
ACTIVE -> ON_HOLD, COMPLETED, CANCELLED
ON_HOLD -> ACTIVE, CANCELLED
COMPLETED -> ARCHIVED
CANCELLED -> ARCHIVED
ARCHIVED -> no transitions
```

Completion, cancellation, and archive use dedicated trusted functions. Direct status updates are blocked. Completed and cancelled history is retained when archived, and archiving never hard-deletes a Project.

Each Project belongs to exactly one Client business record through `client_id`. New Projects require an active, non-archived Client. Owner-controlled Client reassignment is allowed only while the Project is `DRAFT`, `QUOTATION`, or `APPROVED`; reassignment is prohibited from `ACTIVE` onward. A future dependent-record guard must be added before Package 10.3 or any financial/dependent records are introduced.

Project monetary fields are metadata only:

- `contract_amount`
- `contract_currency_code`
- `budget_amount`
- `budget_currency_code`
- `reporting_currency_code`

Zero contract and budget amounts are valid. These fields do not post ledger entries, calculate balances, fetch exchange rates, or create financial events. Financial summaries and balances must later be derived from approved central-ledger records, never stored as editable Project columns.

Client-safe Project reads return exactly:

- `id`
- `project_number`
- `name`
- `project_type`
- `location`
- `status`
- `start_date`
- `end_date`
- `reporting_currency_code`
- `client_visible_summary`

Client-safe reads never expose contract amounts, contract currency, budget amounts, budget currency, internal notes, cancellation reason, audit actor fields, unrelated Client IDs, actor Auth subjects, or unrelated Projects.

Central activity-log actions added by this package:

- `project_record_created`
- `project_record_updated`
- `project_client_changed`
- `project_status_changed`
- `project_completed`
- `project_cancelled`
- `project_archived`

Activity metadata must omit or mask internal notes, full location, actor Auth subjects, raw request bodies, full cancellation reason, private Client identity details, secrets, and raw monetary values. Monetary changes are logged only as safe field-change indicators and are not ledger entries.

## Inspect schema manually

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -c "\\dt app.*"

psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -c "SELECT code, name, is_staff_role, is_active FROM app.roles ORDER BY code;"

psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -c "SELECT schemaname, tablename, rowsecurity FROM pg_tables WHERE schemaname='app' ORDER BY tablename;"
```

## Git review and commit

```bash
git checkout -b stage09/package-09-1
git status --short
git diff --check
git diff -- supabase/migrations supabase/tests
git add .github/workflows/package-09-1-database.yml \
  .env.example .gitignore README.md docs scripts supabase
git commit -m "feat(db): add Stage 09 Package 09.1 identity foundation"
```
