# Noted Migration Suite: Firebase to Supabase

This directory contains repeatable, idempotent, production-grade CLI tooling to migrate Noted user accounts, Firestore documents, and Cloud Storage media from Firebase to Supabase (PostgreSQL + GoTrue + Private Storage).

---

## 1. Architecture & Strategy

### 1.1 Account Migration Strategy & Password Hashing
Firebase Authentication encrypts passwords using a **modified-scrypt** algorithm (`firebase-scrypt`) that relies on project-specific secrets:
- Base64 Signer Key
- Base64 Salt Separator
- Rounds (typically 8)
- Memory cost (typically 14)

Because standard Supabase Auth (GoTrue) defaults to bcrypt/Argon2, password hashes exported from Firebase **cannot be verified automatically** unless GoTrue is configured with the project's exact hash signer key and salt separator.

**Recommended Strategy:**
1. Firebase email verification is preserved: only verified source emails are confirmed. Disabled users receive a 100-year Supabase Auth ban; this is finite and must be managed before expiry. Missing verification flags are treated as unverified.
2. Enabled users need an appropriate verified email recovery flow to establish a Supabase password; no invitation is automatically sent. An existing confirmed Supabase account cannot be unconfirmed by the Auth admin API, so an unverified source account with that mapped ID blocks import for manual resolution.
3. Every Firebase UID (such as 28-character alphanumeric strings) is deterministically converted into an RFC-4122 UUIDv5 via `firebaseUidToSupabaseUuid(firebaseUid)`.
4. The user's original Firebase UID is preserved permanently in `public.profiles.legacy_firebase_uid`.
5. If re-run, the mapping algorithm produces the exact same UUIDs, preserving all foreign keys, collaborator roles, and private Storage paths.

### 1.2 Deep Link & Content Preservation
- **Verbatim `note_id`s:** Existing Firestore note document IDs (e.g. 20-character strings) are preserved verbatim in `public.notes.note_id`. Deep links formatted as `noted://app/notes/<id>` continue to resolve without rewriting.
- **Non-Destructive Content Rewriting:** Notes authored in Quill Delta JSON (`{"notedDocument":1,"ops":[...]}`) or Markdown are preserved without altering ops formatting, text, or internal links. Matched attachment download URLs are rewritten to canonical private media URIs: `noted-media://note-media/<mappedPath>`.
- **Private Storage:** Avatars are stored in the private `avatars` bucket; note attachments are stored in the private `note-media` bucket.

### 1.3 Idempotency & Duplicate Protection
Every migrated entity is recorded in `public.migration_id_mappings` alongside a SHA-256 checksum of its source payload. Re-running the import detects matching checksums and skips already-migrated rows, ensuring 0 duplicates and safe resume capability.

---

## 2. CLI Tooling Reference

### 2.1 Export from Firebase (`export_firebase.mjs`)
Exports Auth users, Firestore collections (including user subcollections `private/settings`, `favorites`, `invitations`, `notifications`, `chats`, `messages`), and Storage blobs.

```bash
# Export using service account key
node export_firebase.mjs \
  --out ./exports/latest \
  --project superheromood-54691 \
  --service-account ./service-account.json \
  --include-media true
```

#### Requirement 10 Compliance:
The export tool **NEVER fabricates synthetic data** and **NEVER mutates or deletes anything in Firebase**. If credentials are missing, inaccessible, or lack necessary permissions, it halts immediately with a structured JSON report and human explanation of the required IAM roles:
- `Firebase Authentication Viewer`
- `Cloud Datastore Viewer`
- `Storage Object Viewer`

---

### 2.2 Dry-Run Import (`import_supabase.mjs --dry-run`)
Validates every user, note, membership, role, connection, favorite, setting, invitation, notification, chat/message, and storage path rewrite without writing anything to the database or storage.

```bash
node import_supabase.mjs \
  --bundle ./exports/latest \
  --dry-run
```

Outputs a full summary table and mapping preview with 0 database mutations.

---

### 2.3 Live Import (`import_supabase.mjs`)
Performs live import into Supabase Auth, PostgreSQL tables (`ON CONFLICT DO UPDATE`), and private Storage buckets.

```bash
node import_supabase.mjs \
  --bundle ./exports/latest \
  --supabase-url https://<project>.supabase.co \
  --service-role-key <SERVICE_ROLE_KEY>
```

---

### 2.4 Validate Migration (`validate_migration.mjs`)
Compares imported values with transformed bundle data, including note content, memberships, AI citations, and downloaded media SHA-256 checksums. Source timestamps are compared when supplied; generated timestamps cannot be independently reproduced when absent from the source. Validation fails if source records were skipped as orphans. Its checks include:
1. Row counts across all 9 application tables
2. User UUIDv5 deterministic mapping & `legacy_firebase_uid` retention
3. Note ownership & verbatim `note_id` deep-link preservation
4. `live_member_ids` and `live_roles` UUID integrity & role validation (`edit`/`view`)
5. `shared_with_user_ids` & `pending_shared_with_user_ids` UUID arrays
6. Copied note provenance (`source_owner_id`, `source_note_id`)
7. Personal favorites (`public.user_favorites`)
8. Connection requests (`public.connection_requests`)
9. AI chats & messages `sources` array integrity
10. Quill Delta JSON & Markdown non-destructive preservation
11. Private Storage objects presence (`avatars` and `note-media`)
12. Auth email confirmation and active ban state against the source flags

```bash
node validate_migration.mjs \
  --bundle ./exports/latest \
  --supabase-url https://<project>.supabase.co \
  --service-role-key <SERVICE_ROLE_KEY>
```

---

### 2.5 Database-only rollback safety

Legacy ledgers without a trusted rollback seal cannot be rolled back by this tool. New imports may opt in to `--seal-rollback` against an entirely empty target. Keep the target offline during import. After importing, the tool captures a locked database snapshot, validates those exact rows against the source bundle (including exact identities/counts and empty runtime state), then supplies the same snapshot to the seal RPC. The RPC rejects any intervening change under locks. Later activity similarly blocks rollback. The importer does not silently bless whichever rows happen to exist at sealing time; these checks do not make the multi-request import itself atomic or replace an offline cutover window.

Rollback preflight and database deletion run in a single locked database transaction. The operation refuses changed state or unexpected cascade dependencies. It deliberately retains Auth users, profiles, settings, and all Storage blobs; it is a partial database rollback, not full account or media cleanup. Dry-run reports any blocker and retained data. Restore from a verified backup using an independently reviewed procedure for complete recovery.

```bash
node rollback_supabase.mjs --dry-run --supabase-url <url> --service-role-key <key>
node rollback_supabase.mjs --confirm-rollback --supabase-url <url> --service-role-key <key>
```

---

## 3. Running Automated Tests

All migration tools are tested against real in-memory PostgreSQL (`PGlite`) simulating Supabase Auth, Row Level Security, and Storage:

```bash
npm run test:migration
```
