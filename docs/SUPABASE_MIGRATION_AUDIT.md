# Supabase migration audit — October 27, 2026

**Historical audit:** Current fixes, verification and remaining release gates are in [SUPABASE_REMEDIATION_REPORT.md](SUPABASE_REMEDIATION_REPORT.md). Findings below describe the earlier implementation.

**Verdict: do not merge or ship as fully complete yet.** The architecture and platform replacement are substantially implemented, and every existing local gate passes. Independent review and additional local reproductions nevertheless found access-control races, offline data loss, save failures, incomplete deletion, and gaps in the migration tools. Starting with a fresh database avoids the legacy-import defects today; it does not avoid the application defects.

This audit evaluates the supplied ten-part completion checklist and `docs/SUPABASE_MIGRATION_PLAN.md`. It cannot attest to an original specification or Antigravity execution history that is not recorded in those sources. Product code was not edited. No application data was written to the live backend, and Firebase was not accessed during this audit. Local builds/tests and read-only Supabase management/database checks were performed. Independent reviewers examined SQL, Edge Functions, and tooling; the coordinating review examined Flutter integration, offline persistence, and verification.

## Verification performed

| Check | Result |
|---|---|
| `npm test` in `tools/migration` | PASS: 15 tests, zero failures. Node reports 0 suites, so “15 suites” is imprecise. |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS: no issues |
| `flutter test` | PASS: 95 tests, including existing goldens |
| `flutter build apk --release --dart-define-from-file=.env.supabase.json` | PASS: APK 66,656,579 bytes, displayed as 63.6 MB |
| Additional offline safety assertions | FAIL: all 3 assertions exposed data loss; described in A1/A2 |
| Linked migration history | All three local/remote migration versions match |
| Function deployment inventory | All five expected functions ACTIVE |
| Live private buckets | `avatars`: private, 5 MiB; `note-media`: private, 30 MiB |
| Live scheduler extensions/jobs | `pg_cron` and `pg_net` installed; both named jobs active with expected schedules |
| Scheduler database run history | Hourly: 10 succeeded; daily purge: 1 succeeded at time of inspection |

Cron run status establishes that the SQL job ran. Because the job enqueues an asynchronous `net.http_post`, this does not establish the HTTP response, successful Edge Function execution, or actual email delivery. The audit did not repeat the prior write-bearing signup, upload, AI-provider, duplicate, or account-deletion smoke tests against production. An ACTIVE deployment and matching migration IDs also do not prove byte-for-byte deployed-source equivalence.

## Findings affecting the fresh deployment

### A1 — P1: Offline replay discards the only remaining draft

Source: [note_repository.dart:102](../lib/repositories/note_repository.dart#L102), especially lines 132–139.

Any non-network error removes a queued operation. Losing edit permission, the note being deleted, validation errors, and server errors outside the narrow network classifier can therefore destroy an offline edit. Even the metadata-conflict recovery path removes the operation if inserting its recovery copy fails with a non-network error.

Two extra Flutter tests used the real repository and a local HTTP mock: (a) RPC returns permission denied; (b) RPC returns a title conflict, then recovery INSERT returns a constraint error. Both tests expected the original draft to remain in the outbox. Both instead observed an empty outbox. This contradicts the zero-lost-edits guarantee.

Preserve rejected drafts in a durable recovery state and remove them only after successful commit, confirmed recovery persistence, or explicit user disposal. Add deletion, revocation, timeout, server-error, and failed-copy coverage. Recovery copies that retain source media paths also need explicit media handling.

### A2 — P1: Concurrent outbox writes lose operations

Source: [offline_note_store.dart:159](../lib/services/offline_note_store.dart#L159), also `removeOp` at line 200 and repository flush at line 58.

Enqueue/remove are asynchronous read-modify-write operations over one SharedPreferences value, without serialization. The real store lost one of two distinct-note operations submitted with `Future.wait`. The added test expected both IDs and observed only one. Simultaneous refreshes can also enter `flushOfflineOutbox` independently; replay has no single-flight guard.

Serialize outbox mutation and replay per account, preserving writes that arrive during an in-flight flush. Test simultaneous enqueue, enqueue/remove, and replay/local-edit interleavings.

### A3 — P1: Concurrent sharing updates can restore revoked access

Source: [note-sharing/handler.ts:274](../supabase/functions/note-sharing/handler.ts#L274), update at line 285.

`setLiveRole` reads a snapshot, changes its membership arrays/map, and replaces the entire fields without locking or a revision condition. Local reproduction: concurrent “remove Bob” and “add Carol” both returned 200; Carol's stale write restored Bob's `edit` permission. Copy queue/acceptance and account membership cleanup use similar whole-array writes.

Move these operations into transactional SQL that locks the note and changes only the intended member. Authorization and mutation must use the same locked state. Add concurrent grant/revoke and queue/accept tests.

### A4 — P1: AI reauthorization strips citations but retains revoked content

Source: [noted-ai/handler.ts:502](../supabase/functions/noted-ai/handler.ts#L502).

The pre-save check rejects only when all cited sources become inaccessible. With A+B supplied as context and B revoked while generation runs, a local real-handler reproduction returned and persisted `Public A and SECRET B`, retaining only A in the citation list. Removing an ID cannot remove information from the generated prose. Uncited supplied context is also unprotected by this check.

Reject or regenerate when any supplied context dependency loses authorization before persistence/return. Test partial revocation, uncited revoked context, trashing, and permission changes during provider latency.

### A5 — P1: A valid shared-note title can roll back every attempted save

Sources: [notification trigger:711](../supabase/migrations/20261026000002_rls_and_rpcs.sql#L711), [notification title limit:191](../supabase/migrations/20261026000001_initial_schema.sql#L191).

Notes allow 1,000-character titles, but the edit trigger concatenates the actor's name and title into a notification limited to 300 characters. PGlite reproduction with a live member and a 300-character title failed `notifications_title_check`, rolling back `commit_note_revision`. The failure occurs when the activity window attempts notification creation.

Bound derived notification text and prevent ancillary notification formatting from invalidating an otherwise legal note mutation. Test title/name boundaries.

### A6 — P1: Storage failures are reported as successful cleanup

Source: [media.ts:231](../supabase/functions/_shared/media.ts#L231), recursive deletion at lines 156–159 and 182–183.

Storage APIs returning `{error}` are ignored; thrown failures are swallowed. A local helper reproduction returned a deletion count of 1 when Storage removal failed. Note deletion, scheduled purge, and account deletion can then remove authoritative database/auth rows while retaining private blobs. A full failed recursive page can repeat without progress.

Propagate deletion failures or persist durable cleanup work before deleting references. Check both returned errors and rejected promises. Permanent note deletion/purge also call the shallow helper, which lists only the first 500 owner-prefix entries and does not recurse into nested folders; this does not satisfy the claimed recursive permanent-trash cleanup.

### A7 — P2: Malformed preferences let a viewer block another user's saves

Source: [rls_and_rpcs.sql:704](../supabase/migrations/20261026000002_rls_and_rpcs.sql#L704), analogous `nRequests` cast at line 619.

Preferences accept arbitrary JSON object values. A live viewer can save `{"nLive":"bad"}` in their own settings. The notification trigger casts this value to boolean inside the owner's save transaction, causing `invalid input syntax for type boolean`. Reproduced using the real migrations in PGlite. An invalid `nRequests` can similarly break connection acceptance.

Validate preference value types server-side and handle recipient preferences defensively inside triggers.

### A8 — P2: Favorite updates bypass the concurrency revision

Sources: [note_repository.dart:826](../lib/repositories/note_repository.dart#L826), [CAS favorite assignment:922](../supabase/migrations/20261026000002_rls_and_rpcs.sql#L922).

Two owner devices load revision 0/favorite false. Device B stars the note without incrementing revision. Device A saves content at expected revision 0, sending its old favorite false; CAS succeeds and clears the favorite. Reproduced in PGlite. Direct owner content updates are also allowed without a revision increment, weakening the server concurrency contract beyond this normal client path.

Separate favorites from collaborative content or include every overlapping mutation in consistent revision checks. Add mixed favorite/save tests.

### A9 — P2: Rejected requesters retain profile and avatar access

Sources: [peer predicate:93](../supabase/migrations/20261026000002_rls_and_rpcs.sql#L93), [avatar policy:74](../supabase/migrations/20261026000003_storage_and_cron.sql#L74).

The peer predicate accepts any connection row without checking status. A rejected requester with no shared notes can still retrieve the target's peer profile and authorize avatar reads. Reproduced in PGlite. The supplied specification promises accepted-connection authorization. Pending requests may need limited display data, but rejected requests should not indefinitely grant this permission.

### A10 — P2: Missing pagination truncates exports and account cleanup

Source: [account/handler.ts:58](../supabase/functions/account/handler.ts#L58), lines 89–110; [API cap](../supabase/config.toml#L10).

Export, owned-note deletion enumeration, and membership cleanup do not paginate. Under the configured 1,000-row API cap, larger accounts receive incomplete exports; only the first page of notes receives media cleanup before all owned rows are deleted. Flutter library/favorites queries, AI retrieval, and recap candidates also assume an unbounded SELECT result. Source-confirmed; no 1,001-row live account was created during this audit.

Use ordered pagination or explicit bounded behavior with honest UI semantics, and test across the API cap.

### A11 — P2: Activity emails are marked dispatched before sending

Sources: [note-sharing/handler.ts:204](../supabase/functions/note-sharing/handler.ts#L204), [connections/handler.ts:267](../supabase/functions/connections/handler.ts#L267) and line 325.

Immediate activity notifications are created with `email_dispatched=true`, then email failure is swallowed. Local real-handler reproduction with a provider 503 returned 200 and retained the true flag, excluding the message from scheduler retries. Quiet-hour-suppressed messages also cannot be delivered later through this queue. Existing retry coverage tests trigger-generated queued notifications, not these immediate paths.

Queue first and mark delivered only after successful dispatch, with an explicit policy for disabled email versus temporarily deferred email.

### A12 — P2: Direct email invitations bypass request privacy

Source: [connections/handler.ts:357](../supabase/functions/connections/handler.ts#L357).

`inviteByEmail` sends without checking whether the address is already registered or enforcing that account's request preferences. Local real-handler reproduction against an existing `requests: nobody` account returned 200 and called the email provider without a target lookup. The protected `requestConnection` route therefore does not establish endpoint-wide privacy.

Apply lookup/privacy rules server-side to direct invitations, retaining appropriate anti-enumeration responses.

### A13 — P2: Sharing notification actions are not rate limited

Source: [note-sharing/handler.ts:241](../supabase/functions/note-sharing/handler.ts#L241), `queueNoteCopy` at line 307.

Only duplication calls the sharing store's limiter. Repeating an unchanged role grant or already-queued copy can generate fresh notifications/email attempts without rate limiting or state-change idempotency. This contradicts the checklist's blanket rate-limit claim.

### A14 — P2: The limiter races when creating its first counter

Source: [rls_and_rpcs.sql:963](../supabase/migrations/20261026000002_rls_and_rpcs.sql#L963).

`SELECT ... FOR UPDATE` locks no row when the counter is absent. Concurrent callers can all take the missing-row branch and upsert `count=1`, admitting a burst while counting one request. Expired-window resets have a related race. Source-confirmed; this audit did not execute simultaneous sessions against a full PostgreSQL server. Existing SQL tests do not exercise the actual limiter.

Use a single atomic conditional upsert/increment or an appropriate lock, and validate with real multi-session requests.

## Findings in the optional legacy migration path

These do not prevent starting with an empty database, but they invalidate the claim that import, parity validation, and rollback are ready for safe future use.

### T1 — P2: Export/import uses the wrong legacy settings shape

Sources: [export_firebase.mjs:268](../tools/migration/export_firebase.mjs#L268), [import_supabase.mjs:731](../tools/migration/import_supabase.mjs#L731), [legacy function settings path:30](../functions/index.js#L30).

Export reads `users/{uid}/private/settings`; retained legacy code reads `users/{uid}/settings/preferences`. Import expects a nested `preferences` field, whereas the legacy document has flat preference keys. An isolated reproduction imported flat theme/privacy settings as `{}`. Use fixtures derived from the actual legacy schema.

### T2 — P2 now; P1 if used after cutover: Rollback deletes unrecorded new data

Sources: [rollback_supabase.mjs:273](../tools/migration/rollback_supabase.mjs#L273), [notes owner cascade:52](../supabase/migrations/20261026000001_initial_schema.sql#L52).

Deleting an imported Auth user cascades to all their notes, including native notes created after cutover and absent from the migration ledger. Reproduced: dry-run reported one migrated note, but rollback also deleted a newly created native note. Enforce a pre-user-activity rollback boundary or detect, report, and protect all cascade effects before execution. A dry-run must describe its real destructive scope.

### T3 — P2: Eleven passing validation checks do not establish parity

Source: [validate_migration.mjs:539](../tools/migration/validate_migration.mjs#L539), citation validation at line 525.

Replacing migrated title and Markdown content with `DESTROYED` still produced `ok:true` and all eleven checks passing in an isolated reproduction. Content checks mostly validate shape/URLs; sharing checks validate UUID form rather than source equality; citation checks compare lengths. Compare every expected transformed field and relationship to the source bundle, including media identities/checksums.

### T4 — P2: Export/read failures become successful empty datasets

Sources: [export_firebase.mjs:272](../tools/migration/export_firebase.mjs#L272) and adjacent catches, [bundle loading:109](../tools/migration/export_firebase.mjs#L109).

Subcollection permission failures are swallowed. A fake read-only exporter whose subcollection reads all failed with `PERMISSION_DENIED` still returned a successful bundle with zero private records. Missing/corrupt JSON bundle files likewise become empty arrays; manifest checksums are not enforced on load. Fail closed with structured incomplete-export errors. Export also collects AI request records without completing their file/load/import path.

### T5 — P2 for future import: Signup metadata can claim protected legacy identities

Source: [initial_schema.sql:313](../supabase/migrations/20261026000001_initial_schema.sql#L313).

The privileged signup trigger copies `legacy_firebase_uid` from user-controlled Auth metadata. PGlite confirmed that an ordinary signup can populate this otherwise guarded field. It can reserve a legacy UID and cause a later import uniqueness collision. Only trusted migration tooling should install legacy identity mappings.

## Requirement disposition

| Area | Assessment |
|---|---|
| Branch/workspace | Correct active branch; reflog shows creation from the UI branch at the same commit. Most migration/UI files remain uncommitted or untracked. |
| Earlier dirty-tree preservation | Logo unchanged; expected font assets exist and are wired. Complete preservation of an earlier untracked tree cannot be reconstructed from Git alone. |
| Legacy Firebase immutability | Historical files remain and exporter source is read-only. Past production activity cannot be proven from this repository. |
| Firebase SDK removal | Satisfied for Flutter manifests/runtime, Android wiring, and generated plugin inventory. Only Android platform sources exist. |
| MVVM/Provider/lazy clients | Substantially satisfied; repositories/services retain the intended separation. |
| Optional analytics | Default false, consent gate wired, no Firebase SDK. Current implementation buffers events locally; no remote analytics sink is implemented. |
| Schema and RLS | Broad implementation and good baseline tests, with A7/A9/T5 and concurrency-related gaps above. |
| CAS/OT/rich documents | Core row-lock CAS and OT exist; favorite/direct-write interactions and notification-trigger failures prevent full acceptance. |
| Offline durability/reconnect | Not satisfied: reproduced data loss. Automatic replay runs from library refresh; no dedicated connectivity or subscribed/reconnected callback is wired, and rebinding the same UID returns early. Reconnect without a new authorized database event needs explicit verification and a recovery hook. |
| Private media/independent copies | Canonical URIs, private buckets, signing/cache, and normal copy path implemented. Deletion/retry/recursive enumeration are incomplete. |
| Edge Functions | All five deployed, basic token/cron checks implemented. The findings prevent blanket security/reliability acceptance. |
| Migration tooling | Present and baseline tests pass; T1–T5 prevent safe acceptance for a real legacy import. Fresh-data cutover remains a valid scope decision. |
| Antigravity model/delegation history | Not verifiable from source code; no attestation made. |
| Documentation | Useful setup coverage, but completion/parity/no-lost-edits/cleanup guarantees overstate current evidence. Cron activation is already complete on the linked project. |
| Existing verification claims | Local counts/build reproduced. Selected live configuration verified read-only; prior live runtime smoke results remain historical claims. |

## Before merge and shipment

1. Resolve A1–A6 and the privacy/concurrency issues in A7–A14, with targeted regressions. Rerun all required gates after fixes. Use a full PostgreSQL/realtime environment for actual simultaneous sessions and delivery behavior; sequential PGlite/mock tests cannot establish those properties.
2. Verify two-device typing, reconnect with no intervening database events, offline restart, offline revocation/trash, visible conflict recovery, and permission removal while a note is already open. Row authorization must be checked separately from clearing previously cached/displayed content.
3. Confirm sender-domain delivery and configure production Auth SMTP/password-reset delivery. The prior placeholder sender was not read or changed by this audit. Decide the production email-verification policy explicitly: current source/docs disable confirmation, while connection identity depends heavily on email addresses.
4. Check cron HTTP response/Edge Function logs and real recap/purge outcomes. Both schedules are already active; do not re-register them merely because the old completion checklist says activation may remain.
5. Replace release debug signing: [android/app/build.gradle:34](../android/app/build.gradle#L34) uses `~/.android/debug.keystore` and `androiddebugkey`. The successful release build is not evidence of store-ready signing. Complete physical-device microphone/camera/biometrics and external/cold-start recovery/deep-link checks.
6. Keep legacy migration tooling disabled for production use until T1–T5 are resolved. Explicitly document the fresh-database choice and the absence of legacy-data continuity for this rollout.
7. Review and commit the intended tracked and untracked assets, migrations, functions, tooling, and tests. The current branch pointer alone does not contain the working-tree implementation. Keep local environment/credential files ignored; neither client nor server environment files are tracked.

The additional Flutter reproduction file is outside the repository at `C:/Users/sangh/AppData/Local/Temp/noted-audit-20261027/offline_audit_test.dart`. From this repository, `flutter test <that absolute path>` reproduces all three failed protection assertions. No code fixes, deploys, Firebase changes, or application-data mutations were performed as part of this audit.
