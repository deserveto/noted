# Migration audit remediation implementation plan

**Goal:** Resolve all A1–A14 and T1–T5 findings in `docs/SUPABASE_MIGRATION_AUDIT.md`, preserve the UI, and verify/deploy compatible fixes.

**Architecture:** Retain Flutter MVVM/Provider and the Supabase services. Serialize local outbox updates, make database membership and overlapping writes atomic, fail closed on privacy/cleanup errors, and compare migration output against the actual legacy bundle. Add a forward migration; do not rewrite deployed migrations or legacy Firebase sources.

**Tech stack:** Existing Flutter/Dart, Supabase PostgreSQL/Realtime/Storage, TypeScript Edge Functions, Node migration tools.

**Spec:** `docs/SUPABASE_MIGRATION_AUDIT.md`; user authorized fixing all findings and permits Terra 6.1 High subagents.

## Constraints and decisions

- Work in the current dirty migration branch so all existing uncommitted UI/assets survive. No reset, clean, broad staging, or legacy Firebase writes.
- Regression tests must reproduce failures before the responsible patch. Keep test ownership separate between workers.
- Database interfaces shared by SQL/Edge workers are agreed before implementation.
- User's request authorizes compatible live migration/function fixes after passing gates. No release publication or destructive live data tests.
- Existing production signing identity and verified mail sender must be inspected, never invented or exposed. Hardware/third-party verification gaps remain explicit if no credentials/device are available.
- No new heavy dependencies or UI redesign.

## Review focus

- Offline rejection, failed recovery, simultaneous queue mutation, and an edit arriving during replay preserve all drafts.
- Concurrent grant/revoke and copy acceptance do not restore permissions or repeat completed transitions.
- Revoking any AI input dependency prevents saving/returning the generated answer.
- Returned Storage errors, nested folders, API pagination, and partially failed account deletion retain retryability.
- Corrupt/missing bundle files, legacy preferences, transformed rich text, and post-cutover cascade data fail safe.

## Tasks

- [x] 1. Flutter durability and refresh (coordinator): add `test/offline_reliability_test.dart`; serialize `OfflineNoteStore` mutations; single-flight replay with account checks; preserve rejected/recovery-failed drafts and expose errors; reliable reconnect/resume refresh; paginate library/favorites/history reads. Verify focused Flutter tests red then green.
- [x] 2. SQL (Terra High): add `20261027000004_audit_remediation.sql` and SQL regression tests for bounded notification text, typed preferences, accepted/pending peer visibility without rejected access, trusted legacy mapping, atomic limiter, immutable revision semantics, and atomic membership/copy operations. Agree RPC signatures with Edge worker. Verify PGlite tests red then green and actual multi-session test if available.
- [x] 3. Edge Functions (Terra High): add regression tests in a separate audit test file; consume atomic RPCs; fix AI dependency authorization, deletion failures/recursive enumeration/retryability, ordered pagination, queued email delivery, invitation privacy, sharing rate limits/idempotency. Verify focused tests red then green.
- [x] 4. Migration tools (Terra High): add separate regression tests; correct legacy settings and AI request export/import, enforce manifest integrity and export failure blockers, exact transformed parity, and rollback cascade protection. Verify focused tests red then green.
- [x] 5. Integration and operational configuration (coordinator): review all worker changes and cross-component contracts; inspect safe production signing/mail configuration, update docs and audit dispositions, retain explicit external blockers rather than claim them fixed.
- [x] 6. Verification/review/deployment (coordinator + fresh Terra High reviewer): `npm test`, `flutter pub get`, `flutter analyze`, `flutter test`, configured release APK; review all remediation changes; apply compatible forward migration and deploy five functions; read-only live schema/config and cron HTTP result checks; save final outcomes.

## Progress

Plan established from the already-reviewed audit and the user's instruction to fix it all. No additional design approval required for these specified corrections. Implementation continues without routine confirmation prompts.

Completed implementation, independent reviews, 81 backend tests, 103 Flutter tests, clean analysis, Deno checks, production-signed APK and live deployment of migrations 4–10/all five functions. Verified live ACL/RLS and authentication. Remaining external release gates: verified email domain/Auth SMTP and physical-device acceptance. No production email sent or legacy Firebase data accessed.
