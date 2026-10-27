# Legacy Firebase Backend Reference (Superseded by `supabase/`)

> **Status — Historical / Read-Only Reference Only**
>
> Noted's application backend has been migrated in full to **Supabase** (`supabase/migrations/`, `supabase/functions/`, and `tools/migration/`). The Flutter app no longer depends on Firebase Auth, Cloud Firestore, Cloud Functions, Firebase Storage, or Firebase Analytics.
>
> Do **not** deploy from this `functions/` directory for new environments. Follow [../docs/SUPABASE_SETUP_AND_CUTOVER.md](../docs/SUPABASE_SETUP_AND_CUTOVER.md) instead.
>
> The files in `functions/`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, and `firebase.json` are intentionally preserved read-only so the existing Firebase project (`superheromood-54691`) remains untouched and auditable during reversible data export and cutover (`tools/migration/export_firebase.mjs`).
