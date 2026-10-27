# Legacy Firebase backend

**Historical reference. The active backend is [Supabase](../supabase/README.md).**

This directory preserves the earlier Firebase functions for audit and legacy export context. The Flutter app now uses Supabase Auth, PostgreSQL/RLS, Realtime, private Storage, and Edge Functions; it has no Firebase SDK dependencies.

## Where to go instead

| Task | Current location |
|---|---|
| Run the app | [Root README](../README.md#run-it-locally) |
| Understand the active backend | [supabase/README.md](../supabase/README.md) |
| Configure or deploy Supabase | [Setup & cutover guide](../docs/SUPABASE_SETUP_AND_CUTOVER.md) |
| Export historical Firebase data | [Migration tools](../tools/migration/README.md) |
| Inspect review findings and verification | [Combined change review](../docs/FULL_CHANGE_REVIEW.md) |

## What is retained

`index.js`, `media.js`, `policy.js`, their tests, and the old package lockfile describe the previous implementation. Related historical rules/configuration remain in the repository root: `firestore.rules`, `firestore.indexes.json`, `storage.rules`, and `firebase.json`.

These artifacts provide context, not the deployment entry point for the current app. Use `supabase/functions/` for active handlers and `supabase/migrations/` for schema changes. Do not run a Firebase deployment as part of setting up Noted.

Legacy export reads Firebase through narrowly scoped read-only credentials. Import, parity validation, and guarded rollback target Supabase; see the migration guide for the limits of each operation. Retaining these files does not mean they are byte-for-byte copies of the pre-migration baseline.
