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
