# Issues and Deviations — Package 09.1

1. **Actual repository absent.** The supplied material is a ZIP/overlay, not the Phase 0 Git checkout. Files are delivered for integration; existing code cannot be truthfully marked changed or verified.
2. **Runtime toolchain absent.** Supabase CLI, Docker, PostgreSQL, Flutter and Dart are unavailable, so database and application runtime tests are pending.
3. **Identity split retained.** The approved ERD's `app.users` plus `app.user_profiles` structure is used instead of duplicating Auth identity, email and lifecycle fields in the profile table.
4. **Role-code representation.** Stable lowercase codes from the Stage 09 requirements are used; exact display labels remain approved.
5. **Historical role uniqueness.** A partial unique active assignment replaces a permanent user/role pair unique constraint so revoked history can be retained and a role can later be reassigned.
6. **Currency dependency included.** Only the approved lookup needed by `contractor_profiles` is created. This is not financial-workflow implementation.
7. **Activity logging deferred.** Package 09.1 has no `activity_logs` table; role-change logging will be added with the approved immutable audit foundation in a later package.
8. **RLS is default deny only.** No user-facing policies or protected backend role-management functions are added yet.

9. **CI CLI version.** The overlay uses `version: latest` only because the real Phase 0 toolchain lock was unavailable. During integration, the team must replace it with the reviewed repository-standard stable Supabase CLI version and record that change in the pull request.
