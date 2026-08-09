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

## Stage 12 Package 12.1

1. **Finance links are schema-present but disabled.** The approved `document_links` finance target columns are present, nullable, and constrained to remain `NULL`. Foreign keys and enabled behavior are deferred until `client_payments`, `payment_requests`, `project_expenses`, and `currency_exchanges` exist.
2. **Metadata-only storage fields in Package 12.1.** `storage_bucket` and `storage_object_key` began as metadata fields only. Storage, scanner, finance links and photograph derivatives are added only by later explicit Stage 12 packages; Flutter UI, notification integration and reserved-role activation remain excluded.
3. **Unfinalized file policy values remain unresolved.** MIME allowlist, maximum file size, retention period, quarantine period, and scanner policy are not invented in Package 12.1.

## Stage 12 Package 12.2

1. **Publication is intentionally blocked at `AWAITING_SCAN`.** Package 12.2 validates private uploads but does not insert newly uploaded files into `app.documents` because the approved ClamAV-compatible scan/quarantine/final publication gate is deferred to the next Stage 12 package.
2. **Legacy metadata creation is forward-restricted.** The old service-role metadata creation wrapper can no longer create an `ACTIVE` document from caller-selected bucket, object key, MIME, size, hash and uploader facts. Existing list/archive behavior remains available.
3. **No Client upload in first release.** Client-safe finalized document access is implemented, but Client upload/transfer-evidence submission remains deferred until the approved workflow package.
4. **Backend proxying is preferred for Client access.** The access gateway streams authorized finalized objects instead of returning raw reusable Storage signed URLs to Clients.

## Stage 12 Package 12.3

1. **Production scanner endpoint remains deployment configuration.** Package 12.3 defines the backend-only ClamAV-compatible HTTPS adapter contract using `DOCUMENT_SCANNER_URL` and `DOCUMENT_SCANNER_TOKEN`, but no endpoint or credential is committed.
2. **Scanner failures fail closed.** Missing scanner configuration, network failure, timeout, malformed response and unknown result all record an error/failed scan state and never create `app.documents`.
3. **Quarantine is logical private quarantine.** Malicious uploads move to `QUARANTINED`, retain bounded scan evidence, and do not publish. Package 12.3 does not invent a retention duration and does not add scheduled cleanup.
4. **Final object token uses stored cryptographic UUID-derived opacity.** The final key is generated once by trusted database logic under `objects/<reserved_document_id>/<opaque-token>` and reused on retry.
