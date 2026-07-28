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

Each Project belongs to exactly one Client business record through `client_id`. New Projects require an active, non-archived Client. Owner-controlled Client reassignment is allowed only while the Project is `DRAFT`, `QUOTATION`, or `APPROVED`; reassignment is prohibited from `ACTIVE` onward. Package 10.3 adds the first dependent-record guard for Project staff assignment history; future financial/dependent-record guards remain required before finance or task packages introduce their own records.

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

## Stage 10 Package 10.3: Project Staff Assignment Foundation

Package 10.3 adds data-foundation records for Project staff assignments only. It does not activate Project Manager, Site Supervisor, or Accountant application access, does not add staff invitations or activation, does not add public staff Project reads, and does not add Flutter screens or Edge Functions.

`app.project_staff_assignments` contains exactly:

- `id`
- `project_id`
- `user_id`
- `assignment_role_code`
- `status`
- `assigned_at`
- `assigned_by`
- `removed_at`
- `removed_by`
- `notes`

Assignment status is exactly:

- `ACTIVE`
- `REMOVED`

Allowed assignment role codes are exactly:

- `project_manager`
- `site_supervisor`

`owner_admin`, `accountant`, and `client` cannot be used as assignment roles. Assignment creation never creates or changes `app.user_roles`; it only records an assignment for an existing active staff user who already holds the matching active global role. Because first-release access remains restricted, these records are future security infrastructure and do not make reserved roles usable.

Assignment creation is Owner-controlled and allowed only when the Project is:

- `DRAFT`
- `QUOTATION`
- `APPROVED`
- `ACTIVE`
- `ON_HOLD`

Creation is rejected for `COMPLETED`, `CANCELLED`, and `ARCHIVED` Projects. Removal remains allowed for active assignments in every Project status so access can be revoked. Removed rows are immutable historical records; reassignment creates a new row. A partial unique index prevents duplicate active assignments for the same Project, user, and assignment role while allowing removed history.

Private future helpers:

- `app.has_active_project_assignment(...)`
- `app.has_active_project_assignment_role(...)`

These helpers return false when an assignment is removed, the staff user is no longer active, the matching global role is no longer active, the role is not `project_manager` or `site_supervisor`, or the Project is archived. They have no public grants and do not activate application access.

Package 10.3 also introduces Project dependency guards:

- `app.change_project_client(...)` rejects Client reassignment once any staff assignment history exists for that Project, including removed history.
- `app.archive_project_record(...)` rejects archive while any active staff assignment exists. Removed historical assignment rows do not block archive.

Clients cannot list, view, or infer Project staff assignments, and Client-safe Project reads contain no assignment fields. Reserved staff roles remain default-denied by `public.current_account()` and have no public Project read RPCs in this package.

Central activity-log actions added by this package:

- `project_staff_assignment_created`
- `project_staff_assignment_removed`

Assignment activity metadata may include safe Project IDs, assignment role codes, and status transitions. It must mask or omit staff email, phone, Auth subjects, raw notes, Client identity, raw request bodies, and request/session secrets.

Later features remain excluded from Package 10.3: phases, milestones, tasks, task assignments, progress updates, documents, photographs, notifications, financial records, ledger entries, Project balances, and assigned-staff UI workflows.

## Stage 11 Package 11.1: Project Phase Foundation

Package 11.1 adds Project phase records only. It does not add milestones, tasks, task assignments, progress calculations, documents, finances, Flutter screens, Edge Functions, or reserved-role access.

`app.project_phases` contains exactly:

- `id`
- `project_id`
- `name`
- `description`
- `sequence_no`
- `start_date`
- `end_date`
- `client_visible`
- `is_active`
- `created_at`
- `created_by`
- `updated_at`
- `updated_by`
- `version_number`

Phase names must be trimmed and nonblank. Duplicate phase names are permitted; `sequence_no` is the authoritative order within a Project. Descriptions are normalized to `NULL` when blank and follow the existing 4000-character Project text convention.

Project phase ordering is Project-wide and active-first:

- active phases occupy contiguous sequence numbers from `1`;
- inactive historical phases remain after active phases;
- insertion, reorder, and archival lock the Project and phase rows before shifting sequence numbers;
- a deferrable unique constraint prevents duplicate `(project_id, sequence_no)`;
- failed ordering operations roll back completely.

Phase creation, normal update, and reorder are allowed only while the Project is `DRAFT`, `QUOTATION`, `APPROVED`, `ACTIVE`, or `ON_HOLD`. They are rejected for `COMPLETED`, `CANCELLED`, and `ARCHIVED` Projects. Phase archival is a soft archive that sets `is_active = false`; it is allowed for all Project statuses except `ARCHIVED`, including completed or cancelled closeout correction. Reactivation and hard deletion are not supported.

Phase dates must satisfy `start_date <= end_date` and must remain within the Project start/end date bounds when those Project dates are present. Cross-table Project-date enforcement is handled by trusted functions rather than a table CHECK.

Owner administration is exposed only through service-role gateways:

- `public.server_create_project_phase(...)`
- `public.server_update_project_phase(...)`
- `public.server_reorder_project_phases(...)`
- `public.server_archive_project_phase(...)`
- `public.server_owner_project_phase_list(...)`
- `public.server_owner_project_phase_detail(...)`

Client phase reads are authenticated-only and safe-field-only:

- `public.current_client_project_phases(project_id)`
- `public.current_client_project_phase(phase_id)`

Client-safe fields are exactly:

- `id`
- `project_id`
- `name`
- `description`
- `sequence_no`
- `start_date`
- `end_date`

Clients see only active, Client-visible phases for Projects owned by their linked active Client record. Hidden phases, inactive phases, unrelated Projects, audit actors, version numbers, and internal activity metadata are never exposed through Client reads.

Package 11.1 adds a Project dependency guard: `app.change_project_client(...)` rejects Client reassignment once any phase history exists for the Project, active or inactive. The existing staff-assignment-history guard remains in force.

Reserved roles remain default-denied. Project Manager, Site Supervisor, and Accountant receive no public phase functions, no phase RLS policies, no Flutter access, and no `public.current_account()` activation in this package. Assigned Project Manager phase management requires a later explicit activation package.

Central activity-log actions added by this package:

- `project_phase_created`
- `project_phase_updated`
- `project_phases_reordered`
- `project_phase_archived`

Phase activity metadata may include safe Project/phase IDs, changed-field indicators, sequence positions, Client-visibility-change indicators, and affected-row counts. It must omit or mask full descriptions, Auth subjects, Client identity, raw request bodies, IP/session/request secrets, and unrelated personal data.

Before milestones or tasks are added, later packages must enforce dependency guards so phase archival handles dependent active rows safely, phase ordering never changes milestone/task ownership, and Project/phase consistency remains inside one Project.

## Stage 11 Package 11.2: Project Milestone Foundation

Package 11.2 adds Project milestone records only. It does not add tasks, task assignments, task status, progress calculations, documents, finances, Flutter screens, Edge Functions, or reserved-role access.

`app.project_milestones` contains exactly:

- `id`
- `project_id`
- `phase_id`
- `name`
- `description`
- `due_date`
- `completed_at`
- `client_visible`
- `is_active`
- `created_at`
- `created_by`
- `updated_at`
- `updated_by`
- `version_number`

Milestone names are trimmed and nonblank. Duplicate milestone names are permitted; the milestone UUID is the record identity. Blank descriptions normalize to `NULL` and descriptions follow the existing 4000-character Project text convention.

Milestones do not have a status enum or status column. State is derived from `is_active` and `completed_at`:

- active incomplete: `is_active = true` and `completed_at IS NULL`;
- active completed: `is_active = true` and `completed_at IS NOT NULL`;
- inactive historical: `is_active = false`, with any existing completion timestamp preserved.

New milestones start active and incomplete. Completion uses trusted database time through `public.server_complete_project_milestone(...)`; completed milestones are read-only and may only be archived. Package 11.2 does not include reopening or completion reversal. Archival sets `is_active = false`, preserves history, and never hard-deletes the row.

Milestone creation and normal update are allowed only while the Project is `DRAFT`, `QUOTATION`, `APPROVED`, `ACTIVE`, or `ON_HOLD`. Completion is allowed only while the Project is `ACTIVE` or `ON_HOLD`. Milestone archival is allowed for all Project statuses except `ARCHIVED`.

`phase_id` is optional. When present, it must reference an active phase belonging to the same Project. Milestone due dates must remain inside Project start/end dates when Project bounds exist, and inside phase start/end dates when an associated phase has bounds. Cross-table validation is implemented with trusted trigger/function logic rather than invalid SQL CHECK constraints.

Owner administration is exposed only through service-role gateways:

- `public.server_create_project_milestone(...)`
- `public.server_update_project_milestone(...)`
- `public.server_complete_project_milestone(...)`
- `public.server_archive_project_milestone(...)`
- `public.server_owner_project_milestone_list(...)`
- `public.server_owner_project_milestone_detail(...)`

Client milestone reads are authenticated-only and safe-field-only:

- `public.current_client_project_milestones(project_id)`
- `public.current_client_project_milestone(milestone_id)`

Client-safe fields are exactly:

- `id`
- `project_id`
- `phase_id`
- `name`
- `description`
- `due_date`
- `completed_at`

Clients see only active, Client-visible milestones for Projects owned by their linked active Client record. A milestone linked to a hidden or inactive phase is hidden from Client reads, including the phase identifier. Cross-Client Project, phase, or milestone identifier manipulation returns no unrelated existence information.

Package 11.2 adds dependency guards:

- `app.change_project_client(...)` rejects Client reassignment once any milestone history exists for the Project, active or inactive, while preserving the earlier staff-assignment and phase-history guards.
- `app.archive_project_phase(...)` rejects phase archival while any active milestone references the phase.
- `app.archive_project_record(...)` rejects Project archival while any active phase or active milestone exists.
- `app.update_project_record(...)` rejects date changes that would exclude existing phase or milestone history.
- `app.update_project_phase(...)` rejects date changes that would exclude milestone history linked to that phase.

Reserved roles remain default-denied. Project Manager, Site Supervisor, and Accountant receive no public milestone functions, no milestone RLS policies, no Flutter access, and no `public.current_account()` activation in this package. Assigned-staff milestone access requires a later explicit activation package.

Central activity-log actions added by this package:

- `project_milestone_created`
- `project_milestone_updated`
- `project_milestone_completed`
- `project_milestone_archived`

Milestone activity metadata may include safe Project/milestone IDs and changed-state indicators for phase association, due dates, completion, and Client visibility. It must omit or mask full descriptions, Auth subjects, Client identity, raw request bodies, IP/session/request secrets, and unrelated personal data.

Before tasks are added, later packages must enforce same-Project task ownership, reject or safely handle active task dependencies during milestone archival, block milestone phase reassignment after task history, and avoid automatic task, phase, Project, or payment completion side effects.

## Stage 11 Package 11.3: Project Task Record Foundation

Package 11.3 adds Project task records only. It does not add task assignments, task updates, task status transitions, task completion workflows, progress calculations, documents, finances, Flutter screens, Edge Functions, notifications, or reserved-role access.

`app.tasks` contains exactly:

- `id`
- `project_id`
- `phase_id`
- `milestone_id`
- `task_number`
- `title`
- `description`
- `client_summary`
- `status`
- `completion_percent`
- `weight_percent`
- `counts_toward_completion`
- `start_date`
- `due_date`
- `completed_at`
- `client_visible`
- `is_active`
- `created_at`
- `created_by`
- `updated_at`
- `updated_by`
- `version_number`

Task statuses are defined for the later workflow package as `TODO`, `IN_PROGRESS`, `BLOCKED`, `COMPLETED`, and `CANCELLED`. Package 11.3 creates every task as `TODO` with `completion_percent = 0`, `completed_at = NULL`, `is_active = true`, and `version_number = 1`. No Package 11.3 function accepts or modifies task status, completion percentage, or completion timestamp. Structural updates are limited to active `TODO` tasks.

Task numbers are Project-local and generated only by trusted database logic:

- `TSK-0001`
- `TSK-0002`
- `TSK-0003`

Numbering restarts independently for each Project, is backed by the internal `app.project_task_number_counters` table, is concurrency-safe through the accepted counter/upsert pattern, and never uses `MAX(...) + 1`. Numbers are unique per Project, remain immutable, and continue beyond `TSK-9999` without truncation.

Task structural fields may include an optional same-Project active phase, optional same-Project active milestone, description, Client summary, Client visibility, date bounds, and completion-weight metadata. `weight_percent` is nullable; when present it must be greater than 0 and no greater than 100. If `counts_toward_completion = false`, `weight_percent` must be `NULL`. Package 11.3 does not define weighting normalization, equal weighting, aggregation, or Project-completion calculations.

Task dates must fit inside Project dates when Project bounds exist and inside phase dates when a phase is linked. A task linked to both a phase and a milestone must use the milestone's phase when the milestone has one. No rule compares task due dates with milestone due dates in this package.

Owner task administration is exposed only through service-role gateways:

- `public.server_create_project_task(...)`
- `public.server_update_project_task(...)`
- `public.server_archive_project_task(...)`
- `public.server_owner_project_task_list(...)`
- `public.server_owner_project_task_detail(...)`

Client task reads are authenticated-only and safe-field-only:

- `public.current_client_project_tasks(project_id)`
- `public.current_client_project_task(task_id)`

Client-safe task fields are exactly:

- `id`
- `project_id`
- `phase_id`
- `milestone_id`
- `task_number`
- `title`
- `client_summary`
- `status`
- `completion_percent`
- `start_date`
- `due_date`
- `completed_at`

Clients see only active, Client-visible tasks for Projects owned by their linked active Client record. Tasks linked to hidden or inactive phases or milestones are hidden from Client reads. Cross-Client and cross-Project identifier manipulation returns no unrelated existence information.

Package 11.3 adds dependency guards:

- `app.change_project_client(...)` rejects Client reassignment once any task history exists for the Project.
- `app.archive_project_phase(...)` rejects phase archival while active tasks reference the phase.
- `app.archive_project_milestone(...)` rejects milestone archival while active tasks reference the milestone.
- `app.archive_project_record(...)` rejects Project archival while active tasks exist.
- `app.update_project_record(...)` rejects date changes that would exclude existing task history.
- `app.update_project_phase(...)` rejects date changes that would exclude task history linked to that phase.
- `app.update_project_milestone(...)` rejects phase reassignment when linked task history would become inconsistent.

Reserved roles remain default-denied. Project Manager, Site Supervisor, and Accountant receive no public task functions, no task RLS policies, no Flutter access, and no `public.current_account()` activation in this package. Assigned-staff task access and task assignment records require a later explicit activation package.

Central activity-log actions added by this package:

- `project_task_created`
- `project_task_updated`
- `project_task_archived`

Task activity metadata may include safe Project/task IDs and changed-state indicators for phase association, milestone association, dates, Client visibility, and completion-counting. It must omit or mask full descriptions, Client summary text, Auth subjects, Client identity, raw request bodies, IP/session/request secrets, and unrelated personal data.

## Stage 11 Package 11.4: Task Assignment Record Foundation

Package 11.4 adds task-assignment records only. It does not add task updates, task status transitions, task completion, progress calculations, assigned-staff application access, notifications, documents, finances, Flutter screens, Edge Functions, or reserved-role activation.

`app.task_assignments` contains exactly:

- `id`
- `task_id`
- `project_staff_assignment_id`
- `assigned_at`
- `assigned_by`
- `removed_at`
- `is_active`

Project, staff user, and assignment-role context are derived through the linked task and `app.project_staff_assignments` row. Task assignments never store their own Project ID, user ID, role code, task status, progress, notes, version, Client visibility, or notification state.

Assignment eligibility is based on an existing active Project staff assignment. The task must be active and `TODO`; the Project must be `DRAFT`, `QUOTATION`, `APPROVED`, `ACTIVE`, or `ON_HOLD`; the Project staff assignment must be active, belong to the same Project, reference an active staff user, and use `project_manager` or `site_supervisor`. Accountant, Client, and Owner/Admin are not task-assignment roles.

Multiple active assignees may share one task. The database enforces only one active row for the same `(task_id, project_staff_assignment_id)` pair using a partial unique index. After removal, the same staff assignment may be assigned to the same task again through a new historical row. Removed rows are immutable, cannot be reactivated, and are never hard-deleted.

Owner task-assignment management is exposed only through service-role gateways:

- `public.server_assign_project_task(...)`
- `public.server_remove_project_task_assignment(...)`
- `public.server_owner_project_task_assignment_list(...)`
- `public.server_owner_project_task_assignment_detail(...)`

Clients receive no task-assignment reads, and existing Client-safe task reads do not expose assignment fields. Project Manager, Site Supervisor, and Accountant remain default-denied: no public staff task RPCs, no assignment RLS policies, no Flutter access, and no `public.current_account()` activation are added in this package.

Package 11.4 adds dependency behavior:

- `app.archive_project_task(...)` rejects archival while active task assignments exist.
- `app.remove_project_staff_assignment(...)` atomically marks child active task assignments inactive when Project access is removed, preserving assignment history and writing one child activity event per automatically removed assignment.
- `app.archive_project_record(...)` rejects archival while active task assignments remain.

Central activity-log actions added by this package:

- `project_task_assigned`
- `project_task_assignment_removed`

Task-assignment activity metadata may include safe Project/task/assignment IDs, assignment role code, affected active-assignment counts, and removal cause. It must omit or mask Auth subjects, staff email, staff phone, full staff profile data, Client identity, raw request bodies, IP/session/request secrets, and unrelated personal data.

## Stage 11 Package 11.5: Task Update and Status Workflow Foundation

Package 11.5 adds Owner-only task workflow state changes and append-only task-update history. It does not add assigned-staff application access, reserved-role activation, Project or phase completion calculations, completion overrides, progress-update records, upcoming or overdue views, notifications, documents, finances, Flutter screens, or Edge Functions.

`app.task_updates` contains exactly:

- `id`
- `task_id`
- `previous_status`
- `new_status`
- `previous_completion_percent`
- `new_completion_percent`
- `update_note`
- `created_at`
- `created_by`

Task-update rows are append-only. Trusted workflow functions insert them atomically with the corresponding `app.tasks` state change. Rows cannot be updated, deleted, truncated, reassigned to another task, or removed during task archival.

Canonical task state is:

- `COMPLETED`: `completion_percent = 100` and `completed_at` is set.
- Any non-completed status: `completion_percent < 100` and `completed_at` is null.
- `CANCELLED`: terminal in this package, active until separately archived, with the cancellation reason retained in `update_note`.

Ordinary transitions are exactly:

- `TODO -> IN_PROGRESS`
- `TODO -> BLOCKED`
- `IN_PROGRESS -> BLOCKED`
- `BLOCKED -> IN_PROGRESS`

Dedicated workflow functions handle completion, reopening, and cancellation:

- `IN_PROGRESS -> COMPLETED`
- `BLOCKED -> COMPLETED`
- `COMPLETED -> IN_PROGRESS` with a required reason and completion below 100.
- `TODO`, `IN_PROGRESS`, or `BLOCKED -> CANCELLED` with a required reason.

Owner workflow access is exposed only through service-role gateways:

- `public.server_update_project_task_progress(...)`
- `public.server_change_project_task_status(...)`
- `public.server_complete_project_task(...)`
- `public.server_reopen_project_task(...)`
- `public.server_cancel_project_task(...)`
- `public.server_owner_project_task_update_list(...)`
- `public.server_owner_project_task_update_detail(...)`

Clients see only current safe task state through existing Client task reads. They do not receive task-update history or `update_note` values. Project Manager, Site Supervisor, and Accountant remain default-denied: task assignments still do not grant application access, no public staff task-update RPCs exist, no staff RLS policies are added, and `public.current_account()` remains unchanged.

Task archival is now terminal-only: only `COMPLETED` or `CANCELLED` tasks may be archived. Active task assignments must still be removed first, and task-update history remains linked.

Central activity-log actions added by this package:

- `project_task_progress_updated`
- `project_task_status_changed`
- `project_task_completed`
- `project_task_reopened`
- `project_task_cancelled`

Workflow activity metadata may include safe Project/task/update IDs, previous and new status, previous and new completion values, and whether a reason was provided. It must omit full update notes, Auth subjects, email, phone, Client identity, raw request bodies, IP/session/request secrets, and unrelated personal data.

Package 11.6 remains responsible for later task-workflow extensions. Completion calculations, completion overrides, notification delivery, assigned-staff workflow access, Flutter workflow screens, documents, photographs, and financial features remain excluded.

## Stage 11 Package 11.6: Phase and Project Completion Calculation Foundation

Package 11.6 adds derived completion calculations only. It does not add completion overrides, progress-update records, assigned-staff access, reserved-role activation, upcoming or overdue views, notifications, Flutter screens, Edge Functions, documents, photographs, or financial features.

Counted tasks now require an explicit `weight_percent`. A task with `counts_toward_completion = true` must have a non-null weight greater than `0` and no greater than `100`. A task with `counts_toward_completion = false` must have `weight_percent = NULL`. The migration does not generate, backfill, divide, normalize, or assign equal weights automatically; callers must provide a valid counted-task weight or explicitly create a non-counting task.

Completion is calculated at read time with PostgreSQL `numeric` arithmetic:

```sql
COALESCE(
  round(
    sum(weight_percent * completion_percent)
    / NULLIF(sum(weight_percent), 0),
    2
  ),
  0.00
)::numeric(5,2)
```

Qualifying tasks are active, counted, non-cancelled tasks with a non-null weight. `TODO`, `IN_PROGRESS`, `BLOCKED`, `COMPLETED`, reopened active tasks, and newly created counted tasks are included. Inactive tasks, archived tasks, `CANCELLED` tasks, and non-counting tasks are excluded. No qualifying tasks returns `0.00`.

Phase completion uses qualifying tasks whose `phase_id` is the requested phase. Tasks without a phase do not affect phase completion. Project completion uses all qualifying tasks in the Project, including tasks without phases. Inactive phase Owner reads return the current derived value, not a point-in-time historical snapshot.

Owner snapshots are exposed only through service-role gateways:

- `public.server_owner_project_phase_completion(...)`
- `public.server_owner_project_completion(...)`

Owner output includes the calculated percentage, counted task count, and total weight.

Client aggregate reads are exposed only to authenticated Clients:

- `public.current_client_project_phase_completion(...)`
- `public.current_client_project_completion(...)`

Client output is aggregate-only. It returns only Project/phase identifiers and the calculated percentage. Hidden tasks still affect the authoritative Project aggregate, but Client responses never include task counts, total weight, task IDs, task titles, descriptions, assignment data, or hidden-task details.

Successful calculation reads create no activity-log entry, increment no version number, update no record, and trigger no lifecycle automation. They do not complete milestones, phases, Projects, or tasks; do not archive tasks; do not change assignments; and do not create notifications, progress updates, or overrides.

Project Manager, Site Supervisor, and Accountant remain default-denied. Package 11.6 adds no staff completion RPCs and does not change `public.current_account()`. Package 11.7 completion overrides remain excluded.

## Stage 11 Package 11.7: Project Completion Override Foundation

Package 11.7 adds Project-level official completion overrides only. It does not add progress updates, notifications, upcoming or overdue logic, assigned-staff access, reserved-role activation, Flutter screens, Edge Functions, documents, photographs, or financial features.

`app.project_completion_overrides` contains exactly:

- `id`
- `project_id`
- `override_percent`
- `reason`
- `effective_at`
- `approved_at`
- `approved_by`
- `revoked_at`
- `revoked_by`
- `created_at`
- `created_by`

There is no stored status column and no stored calculated-completion snapshot. State is derived from approval and revocation fields:

- Pending: approval and revocation fields are all null.
- Active: approval fields are present and revocation fields are null.
- Superseded or revoked: approval and revocation fields are all present.

Multiple pending requests may exist for one Project. Exactly one approved active override may exist per Project, enforced with a partial unique index. Approval of a new request atomically supersedes the previous active override and retains every historical row.

Only an active Owner/Admin may request an override. Only a different active Owner/Admin may approve it; requester self-approval is always denied, so production approval requires two distinct active Owner/Admin accounts. An active Owner/Admin may revoke the current active override with a required reason. Future scheduling is excluded: request effective timestamps must be non-null and no later than the transaction time, so an approved unrevoked override becomes official immediately on approval.

Official Project completion is:

- the active approved override percentage when one exists;
- otherwise the Package 11.6 calculated Project completion.

The request-time calculated percentage and requester effective role are retained in immutable activity-log entries, not in the override table. Successful request, approval, supersession, and revocation logs retain the validated Owner reason where applicable. Denied-operation logs and Client output do not echo submitted reasons.

Owner access is exposed only through service-role gateways:

- `public.server_owner_request_project_completion_override(...)`
- `public.server_owner_approve_project_completion_override(...)`
- `public.server_owner_revoke_project_completion_override(...)`
- `public.server_owner_official_project_completion(...)`
- `public.server_owner_project_completion_override_list(...)`
- `public.server_owner_project_completion_override_detail(...)`

Client Project completion keeps the existing authenticated gateway:

- `public.current_client_project_completion(project_id)`

Client output is aggregate-only:

- `project_id`
- `calculated_completion_percent`
- `official_completion_percent`
- `is_overridden`

Clients never receive override IDs, reasons, effective timestamps, creators, approvers, revokers, pending-request existence, request counts, history, task counts, task weights, task identifiers, or hidden-task details. Phase completion remains calculated-only.

Override rows are permanently retained. Direct update, delete and truncate are prohibited; controlled approval and revocation are the only mutation paths after request creation. Project Manager, Site Supervisor, and Accountant remain default-denied, no assignment-based override access is added, and `public.current_account()` remains unchanged. Package 11.8 progress updates remain excluded.

## Stage 11 Package 11.8: Progress Update Foundation

Package 11.8 adds narrative Project progress updates only. It does not add task-linked progress, delay/problem fields, next-planned-work fields, separate private and Client summaries, notifications, photographs, document storage, upcoming or overdue views, calendar functions, Flutter screens, Edge Functions, finance, assigned-staff access, or reserved-role activation.

The external data dictionary is authoritative for `app.progress_updates`. The table contains exactly:

- `id`
- `project_id`
- `milestone_id`
- `title`
- `summary`
- `reported_completion_percent`
- `status`
- `client_visible`
- `submitted_at`
- `submitted_by`
- `approved_at`
- `approved_by`
- `rejected_at`
- `rejected_by`
- `rejection_reason`
- `published_at`
- `archived_at`
- `archived_by`
- `created_at`
- `created_by`
- `updated_at`
- `updated_by`
- `version_number`

`app.progress_update_status` has exactly `DRAFT`, `SUBMITTED`, `APPROVED`, and `REJECTED`. Publication and archival are represented by timestamps, not enum values. A published row may later be archived; the `published_at` timestamp is retained as history while archived rows disappear from active Client feeds.

First-release workflow is Owner-only:

- Create a `DRAFT`.
- Edit only while still `DRAFT`.
- Submit from `DRAFT` to `SUBMITTED`.
- Approve from `SUBMITTED` to `APPROVED` by a different active Owner/Admin than the creator.
- Reject from `SUBMITTED` to `REJECTED` with a required reason.
- Change Client visibility only while approved, unpublished, and unarchived.
- Publish only approved, visible, unarchived updates for Projects whose Client portal relationship remains readable.
- Archive only approved or rejected updates.

Approval requires two distinct active Owner/Admin accounts. Approval alone does not expose an update to Clients; publication is a separate explicit action. Package 11.8 publishes the single `summary` field, so it must not contain internal notes, private delay assessment, staff-private comments, supplier information, financial information, or secrets before publication.

Optional `milestone_id` must reference an active same-Project milestone at draft creation and draft editing. Client reads return `milestone_id` only when the milestone independently remains Client-visible, active, and not hidden behind an inactive or private phase; otherwise the Client-safe projection returns `NULL`.

Client access is read-only and limited to active authenticated Clients reading their own Projects. Client list/detail output contains only:

- `id`
- `project_id`
- `milestone_id`
- `title`
- `summary`
- `reported_completion_percent`
- `published_at`

Clients never receive status, draft/submission/approval/rejection metadata, rejection reasons, version numbers, unpublished or archived history, activity metadata, Auth subjects, staff identities, or private Project data. Cross-Client identifiers use the existing safe no-row behavior.

Progress updates are narrative snapshots. They do not update tasks, insert task-update history, change phase or Project completion, change official completion overrides, alter Project/phase/milestone status, create notifications, access storage, create documents, or create financial records.

Activity actions added by this package:

- `progress_update_created`
- `progress_update_updated`
- `progress_update_submitted`
- `progress_update_approved`
- `progress_update_rejected`
- `progress_update_client_visibility_changed`
- `progress_update_published`
- `progress_update_archived`

Successful reads create no activity entry. Denied-operation logs must not echo submitted summaries or rejection reasons. Project Manager, Site Supervisor, and Accountant remain default-denied, no assignment-based progress gateway is added, and `public.current_account()` remains unchanged. Package 11.9 notifications remain excluded.

## Stage 11 Package 11.9: In-App Notification Foundation

Package 11.9 adds in-app database notifications only. It does not add email, push, SMS, WhatsApp, delivery status, retry queues, scheduled jobs, preferences, task deadline producers, upcoming or overdue processing, document producers, financial producers, Flutter screens, Edge Functions, assigned-staff access, or reserved-role activation.

`app.notification_status` has exactly `UNREAD`, `READ`, and `ARCHIVED`. `app.notifications` contains exactly:

- `id`
- `recipient_user_id`
- `project_id`
- `notification_type`
- `title`
- `body`
- `status`
- `related_entity_type`
- `related_entity_id`
- `created_at`
- `read_at`
- `archived_at`

Package 11.9 has one producer: publishing a Client-visible progress update creates one duplicate-safe `PROGRESS_UPDATE_PUBLISHED` notification for the Project-owning Client portal user. The related entity is `progress_update`, and trusted database code derives the recipient, Project, notification type, title, body, and related entity. Callers cannot choose a recipient or provide arbitrary notification text.

The notification text is constant and safe:

- Title: `New project progress update`
- Body: `A new progress update is available for your project.`

The progress-publication transaction is atomic: the progress update is marked published, its version increments once, the notification is inserted or found through duplicate suppression, and the existing `progress_update_published` activity entry is written together. If Client or portal-user resolution fails, publication, versioning, notification insertion, and success activity all roll back. Package 11.9 adds no separate `notification_created` activity action.

Notification creation is protected by the trusted transaction-local context `app.notification_creation_context = progress_update_publication`, private functions, forced RLS, revoked direct DML, and narrow public gateways. Duplicate suppression uses the recipient, notification type, related entity type, and related entity ID so retries do not create duplicate progress-publication notifications.

Current-recipient inbox functions derive the user from `auth.uid()` and allow only a single usable first-release context: Owner/Admin or Client. Reserved roles remain predefined but unusable, and `public.current_account()` is unchanged. Inbox output omits `recipient_user_id` and returns only notification fields safe for the current recipient. List ordering is deterministic by `created_at DESC, id DESC`; archived rows are excluded by default unless explicitly requested by status or include-archived filtering.

Reading a notification does not mark it read. Mark-read, mark-unread, and archive are current-recipient-only state changes. The first read sets `read_at`; later unread/read toggles retain that first-read timestamp. Repeated mark-read, mark-unread, or archive calls are idempotent no-ops and create no duplicate activity. Archive is terminal: there is no unarchive, no read/unread after archive, and no hard deletion.

Notification related-entity fields are navigation hints only. Opening a linked progress update must still call the approved progress-detail endpoint and independently pass Client ownership, Project readability, publication visibility, and archive restrictions. Historical notification rows may retain inaccessible related IDs, but notification access never bypasses entity-specific authorization.

State-change activity actions added by this package are `notification_marked_read`, `notification_marked_unread`, and `notification_archived`. Activity metadata may include notification ID, Project ID, notification type, previous status, new status, and accepted request/correlation context. It must not include title, body, progress summary, recipient contact data, Client name, Auth subject, tokens, session secrets, or raw request content.

Other notification producers and external delivery infrastructure are deferred to later approved packages.

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
