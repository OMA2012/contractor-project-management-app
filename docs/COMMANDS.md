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
