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

Every file is transactional. Production correction is forward-fix first; never rewrite an already applied migration.
