# Migration audit remediation — October 27, 2026

**Subsequent full review:** See [FULL_CHANGE_REVIEW.md](FULL_CHANGE_REVIEW.md) for the complete UI/backend review, additional fixes and current PR verification/deployment boundary. The measurements below record the earlier remediation gate, not the later PR head.

This supersedes the readiness verdict in `SUPABASE_MIGRATION_AUDIT.md`, which remains the historical findings record. Existing UI/assets and the dirty migration branch were preserved. No Firebase access, reset, clean, merge or broad staging was performed.

## Audit disposition

| IDs | Corrected behavior |
|---|---|
| A1, A2 | Serialized per-account durable outbox mutations and single-flight replay; rejected drafts and failed recovery copies remain durable. Later edits cannot be removed by an older create acknowledgement. Offline overlays, reconnect/auth/foreground refresh and access rechecks preserve drafts while hiding revoked remote notes. |
| A3 | Locked SQL role, copy queue, acceptance and membership mutations; acceptance checks source revision and consumes the pending share atomically. Unchanged grants/copy queues do not notify again. |
| A4 | Selected text requires an accessible source note. All supplied/reused context dependencies are authorized; unmarked legacy assistant history is excluded. A service-only SQL RPC locks dependencies and authorizes and persists the exchange atomically, including authorize-only requests with history disabled. Authorization is established at transaction commit, not guaranteed at wire delivery time. |
| A5, A7 | Derived notification text is bounded. Boolean settings are validated; recipient preferences cannot abort another user's save through invalid casts. |
| A6 | Storage errors propagate. Durable deletion claims block restore/edit; account write barriers precede cleanup and wait for outstanding copies. Cleanup visits nested/paginated folders, every uploader for a deleted note, and the deleting account's entire uploader prefix. Copy reservations and permanent rotating re-sweeps retain cleanup knowledge after interrupted or late writes. |
| A8 | Content CAS preserves independently managed favorites; direct overlapping edits advance revision. |
| A9 | Rejected requests no longer grant peer profile/avatar access; pending request display remains supported. |
| A10 | Ordered pagination covers library/favorites/trash/pending shares, connections, AI history/retrieval, export and cleanup. |
| A11 | Activity email remains queued until sent, respects quiet hours and retries provider failures. A durable rotating cursor prevents starvation; runs bound both examined candidates and send attempts. |
| A12–A14 | Direct invitations cannot bypass registered-recipient privacy. Sharing transitions are rate limited/idempotent; limiter initialization/reset/increment is serialized. |
| T1, T4 | Export uses the actual legacy settings path/shape, includes AI requests, and fails closed on incomplete reads, missing/corrupt files and checksum mismatches. |
| T2 | Unsafe Auth-cascade rollback is removed. An opt-in fresh import captures a source-validated snapshot and compares it under locks before sealing and before transactional rollback. Changed, extra or unmapped dependent rows prevent deletion. |
| T3 | Validation compares transformed content/metadata/memberships/citations and downloaded media hashes with the source, rather than treating shape checks as parity. |
| T5 | Signup-controlled metadata cannot populate protected legacy identities; trusted import tooling sets them separately. |

Forward migrations `20261027000004` through `20261027000010` preserve the first three deployed migration files. New private runtime tables have RLS, no client policies and no direct client grants.

## Compatibility choices and limits

- Rollback is **database-only**: Auth users, profiles, settings and Storage blobs remain. Old unsealed ledgers fail closed. Full environment recovery requires a verified backup and a separately reviewed restore procedure. The fresh-database rollout executes neither legacy import nor rollback.
- Activity email uses the hourly queue, so delivery is no longer immediate.
- Cleanup failures leave note/account deletion pending and retryable. Account deletion blocks new writes until complete.
- Tombstones and copy sweeps remain so late remote objects stay discoverable. Periodic reconciliation provides eventual cleanup; the database cannot promise instantaneous physical erasure of an externally in-flight Storage write.
- Ordered pagination is not a multi-request database snapshot; concurrent list changes can shift pages, and later refreshes reconcile them.

## Production Android signing

At the user's request a new 3072-bit RSA upload key was created. Release builds load ignored `android/key.properties`; there is no debug-signing fallback. Missing signing configuration fails the release build.

Private material is outside Git at `C:/Users/sangh/.noted/signing/`. Securely back up `noted-upload.jks` and `noted-upload.properties`. The public certificate is `noted-upload-cert.pem`. Passwords were neither printed nor committed. APK signing verifies as `CN=Noted Upload, OU=Mobile, O=Noted`; certificate SHA-256 fingerprint: `934751720dcf265118d7ba8b5ec484c384bc0e1d257f8cdfb35d6bfa313e5f6b`.

A new certificate cannot upgrade an existing debug-signed installation in place. Preserve local drafts before manual installation changes.

## Verification

- Backend/migration tests: 81 passed after completed remediation.
- `flutter pub get`: passed.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 103 passed, including existing goldens.
- Deno type checking: all five function entry points passed.
- Configured release APK: built, 63.7 MB; `apksigner` verification passed with the new upload certificate.

Database tests use PGlite and handler/client tests use controlled HTTP/Storage fakes. Physical two-device Realtime, hardware capture/biometrics and cold-start external recovery/deep links remain device acceptance gates. These results do not establish that every concurrent Storage/runtime interleaving was exercised in production.

## Deployment and remaining production setup

- All ten local/remote migration versions match; the seven forward migrations were applied successfully.
- All five remediated functions deployed and are ACTIVE: AI/connections version 2; sharing/account/maintenance version 3.
- All six new private runtime tables have live RLS enabled and authenticated SELECT privilege disabled.
- Live unauthenticated probes return 401 for all five functions. A valid-secret maintenance request with an unsupported no-op job returns the expected 400 `invalid-argument`, validating the deployed runtime/secret without triggering email or cleanup.
- Both cron jobs remain active. Existing `pg_net` responses inspected during deployment were HTTP 200 without timeout; they predate the new deployment and are not a fresh end-to-end scheduler execution proof. No send-bearing maintenance job was manually invoked.
- APK SHA-256: `CCA3C1ABE65EA96F01B1B296775E63EAAFC63AD5429DAD455EE1077B9B53B384`.

Activity email through Resend is blocked on sender/domain verification. Its sender remains a placeholder; the connected Resend account has no verified domain. Gmail **Auth SMTP** was subsequently configured and verified by a read-only settings check; actual delivery remains untested and confirmation was still off. No email was sent and no DNS records were changed during verification.

Finish the separate Resend activity-mail configuration (or a reviewed alternate adapter), test Auth SMTP delivery, and enable mandatory email confirmation before public rollout. Both cron jobs were already active; SQL dispatch success must be distinguished from function HTTP success and delivered email.
