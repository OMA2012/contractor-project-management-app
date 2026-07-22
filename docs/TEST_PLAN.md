# Package 09.1 Test Plan

## Automated tests included

### Static validation

`scripts/static_validate.py` checks:

- all eight migrations parse as PostgreSQL;
- exact Package 09.1 file count and order;
- required foundation tables exist in SQL;
- client, project and financial tables are absent;
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
