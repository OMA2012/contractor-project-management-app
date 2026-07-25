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
