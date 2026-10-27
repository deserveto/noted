# Noted Full Backend Migration Plan: Firebase to Supabase

**Audit follow-up:** The original implementation/verification record below predates remediation. Current behavior, forward migrations and production gates are in [SUPABASE_REMEDIATION_REPORT.md](SUPABASE_REMEDIATION_REPORT.md).

**Date:** 2026-10-26 (Updated & Verified Live: 2026-10-27)
**Status:** Implemented & Verified End-to-End (`15/15` PostgreSQL/RLS/Edge Function/Migration suites passing, `95/95` Flutter unit/widget/golden tests passing, `flutter analyze` 0 issues, live Supabase Auth/RLS/Storage/Edge Function/OpenRouter smoke checks passing, release APK built).
**Scope:** Complete replacement of Firebase Authentication, Cloud Firestore, Cloud Storage, Cloud Functions, and Firebase Analytics with Supabase Auth, PostgreSQL + Row Level Security (RLS), Supabase Realtime, Private Supabase Storage, Supabase Edge Functions (OpenRouter AI + Resend Email), and `pg_cron` scheduling.

---

## 1. Current Firebase Audit

### 1.1 Dependencies & Platform Wiring Being Replaced
| Layer | Current Firebase Artifact | Replacement |
|---|---|---|
| `pubspec.yaml` | `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions`, `firebase_storage`, `firebase_analytics` | `supabase_flutter`, `crypto` (zero `firebase_*` or `cloud_*` packages) |
| Bootstrap | `lib/main.dart`, `lib/firebase_options.dart`, `lib/services/firebase_service.dart` | `lib/services/supabase_service.dart` (`Supabase.initialize` via `--dart-define` / `--dart-define-from-file`) |
| Android Gradle & Manifest | `com.google.gms.google-services` in `android/settings.gradle` & `android/app/build.gradle`; `firebase_analytics_collection_enabled` in `AndroidManifest.xml` | Removed Gradle Google Services plugin; added `noted://app/auth-callback` intent-filter alongside `noted://app/notes/` |
| Security Rules | `firestore.rules`, `firestore.indexes.json`, `storage.rules` | Versioned SQL migrations in `supabase/migrations/` with RLS policies, column-guard triggers, indexes, and `storage.objects` policies |
| Cloud Functions | `functions/index.js`, `functions/policy.js`, `functions/media.js` (16 callables/triggers/schedules) | `supabase/functions/` (`noted-ai`, `note-sharing`, `connections`, `account`, `scheduled-maintenance`) + atomic PostgreSQL RPCs & triggers |

### 1.2 Flutter Touchpoints Requiring Migration
1. **Models (`lib/models/`)**:
   - `note_model.dart`, `user_model.dart`, `connection_model.dart` import `cloud_firestore` (`Timestamp`, `QueryDocumentSnapshot`).
   - `settings_model.dart` is pure Dart (28 preference keys).
   - *Action*: Replace Firestore `Timestamp`/`DocumentSnapshot` types with pure Dart `fromRow`/`toRow` & `fromMap`/`toMap` supporting ISO-8601 UTC strings, `DateTime`, epoch millis, and legacy JSON/Markdown/Quill Delta documents without destructive rewriting.
2. **Repositories & Services (`lib/repositories/`, `lib/services/`)**:
   - `auth_repository.dart`, `account_services.dart`: Auth sign-in/up/out, password reset, reauth, email/password change, export, account deletion.
   - `note_repository.dart`, `collaboration_service.dart`: Notes streams, personal favorites, trash/restore/permanent delete, revision-checked OT collaborative save, presence heartbeats, copy queue/accept/decline, note duplication.
   - `attachment_service.dart`: Image, drawing, and voice note uploads + private signed URL resolution.
   - `connection_repository.dart`: Connection requests, accept/reject/remove/resend, email invitations.
   - `profile_repository.dart`, `settings_repository.dart`: Profile editing, avatar upload, stats, synced settings + `SharedPreferences` per-user cache.
   - `ai_repository.dart`: Scoped AI Q&A, cancellation, chat/message history, feedback, rename, clear history.
3. **Direct Firebase Leaks in Views/Widgets (Refactored to Clean MVVM Repositories)**:
   - `lib/app.dart`: `FirebaseAnalytics` -> consent-gated `AnalyticsService`.
   - `lib/viewmodels/auth_viewmodel.dart`: `User` / `FirebaseAuthException` -> Supabase/domain auth state & friendly error mapping.
   - `lib/views/ai_page.dart`: `QuerySnapshot` & `FirebaseFunctionsException` -> typed `Stream<List<AiChatSummary>>` & `AiServiceException`.
   - `lib/views/connections_page.dart`: `_EmailInvitations` direct Firestore stream -> `ConnectionRepository.watchInvitations` / `cancelInvitation`.
   - `lib/views/settings_page.dart`: `_pickAvatar` direct `FirebaseStorage` upload -> `ProfileRepository.uploadAvatar` (private `avatars` bucket).
   - `lib/services/recently_deleted_page.dart`: direct Firestore & callable queries -> `NoteRepository.watchDeletedNotes`, `restoreNote`, `permanentlyDeleteNote`.
   - `lib/widgets/activity_sheet.dart`: `ActivityBell` & `ActivitySheet` direct Firestore streams -> `ActivityRepository`.
   - `lib/widgets/note_card.dart`: `LiveAvatarStack` & `_MemberAvatar` direct Firestore calls -> `NoteRepository.watchPresence` & cached `ProfileRepository.load`.

---

## 2. PostgreSQL Schema & ID Preservation Mapping

### 2.1 Primary Key & Legacy ID Strategy
- **`auth.users.id` / `public.profiles.id` (`UUID`)**: Supabase Auth mandates UUID user identifiers, whereas Firebase Auth UIDs are arbitrary strings (typically 28-char alphanumeric).
  - *Migration Mapping*: Migration tooling maps every Firebase UID deterministically via **UUIDv5** (`uuidv5(firebaseUid, NOTED_MIGRATION_NAMESPACE)`) and records every mapping in `public.migration_id_mappings` (`entity_type`, `firebase_id`, `supabase_id`, `checksum`, `migrated_at`) as well as `public.profiles.legacy_firebase_uid UNIQUE`.
- **Preserved String IDs (`TEXT`)**:
  - `public.notes.note_id` (`TEXT PRIMARY KEY`), `source_note_id` (`TEXT`), `ai_chats.chat_id` (`TEXT`), `ai_messages.id` (`TEXT`), `connection_requests.connection_id` (`TEXT`), `notifications.id` (`TEXT`), `ai_requests.request_id` (`TEXT`) remain `TEXT`.
  - **Result**: 100% of existing note IDs, native deep links (`noted://app/notes/<noteId>`), web note links, provenance references (`source_note_id`), favorites (`user_favorites.note_id`), and AI chat source citations (`sources` JSONB array) survive verbatim without rewriting note identifiers.

### 2.2 Table Mapping
| Firestore Collection / Path | PostgreSQL Table | Key Columns & Constraints |
|---|---|---|
| `users/{uid}` | `public.profiles` | `id UUID PK REFERENCES auth.users ON DELETE CASCADE`, `email TEXT`, `name TEXT`, `field_of_study TEXT`, `avatar_path TEXT`, `avatar_url TEXT`, `legacy_firebase_uid TEXT UNIQUE`, `created_at`, `updated_at` |
| `users/{uid}/private/settings` | `public.user_settings` | `user_id UUID PK REFERENCES auth.users ON DELETE CASCADE`, `preferences JSONB NOT NULL DEFAULT '{}'::jsonb`, `timezone_offset_minutes INT DEFAULT 0`, `notes_schema INT DEFAULT 2`, `updated_at TIMESTAMPTZ` |
| `notes/{noteId}` | `public.notes` | `note_id TEXT PK`, `user_id UUID NOT NULL REFERENCES auth.users ON DELETE CASCADE`, `owner_name TEXT`, `owner_email TEXT`, `title TEXT (<=1000)`, `content TEXT (<=1000000)`, `category TEXT (<=200)`, `color TEXT CHECK IN ('blue','pink','mint','yellow','peach','lav')`, `is_favorite BOOLEAN`, `live_member_ids UUID[]`, `live_roles JSONB`, `shared_with_user_ids UUID[]`, `pending_shared_with_user_ids UUID[]`, `source_owner_id UUID`, `source_note_id TEXT`, `attachments JSONB`, `revision INT (>=0)`, `last_edited_by UUID`, `deleted_at TIMESTAMPTZ`, `created_at`, `updated_at` |
| `users/{uid}/favorites/{noteId}` | `public.user_favorites` | `(user_id UUID, note_id TEXT) PK`, FKs to `auth.users` & `public.notes ON DELETE CASCADE` |
| `notes/{noteId}/presence/{uid}` | `public.note_presence` | `(note_id TEXT, user_id UUID) PK`, `name TEXT (<=200)`, `typing BOOLEAN`, `expires_at TIMESTAMPTZ` |
| `notes/{noteId}/activityWindows/{id}` | `public.note_activity_windows` | `(note_id TEXT, window_key TEXT) PK`, `created_at TIMESTAMPTZ` |
| `connection_requests/{id}` | `public.connection_requests` | `connection_id TEXT PK`, `from_user_id UUID`, `from_name`, `from_email`, `to_user_id UUID`, `to_name`, `to_email`, `status CHECK IN ('pending','accepted','rejected')`, partial unique index preventing duplicate active pairs |
| `users/{uid}/invitations/{hash}` | `public.user_invitations` | `(user_id UUID, email_hash TEXT) PK`, `email TEXT`, `sent_at TIMESTAMPTZ` |
| `users/{uid}/notifications/{id}` | `public.notifications` | `id TEXT PK`, `user_id UUID`, `type TEXT`, `title TEXT`, `body TEXT`, `note_id TEXT`, `actor_id UUID`, `actor_name TEXT`, `read BOOLEAN DEFAULT false`, `email_dispatched BOOLEAN DEFAULT false`, `created_at TIMESTAMPTZ` |
| `users/{uid}/aiRequests/{id}` | `public.ai_requests` | `(user_id UUID, request_id TEXT) PK`, `cancelled BOOLEAN`, `status CHECK IN ('running','completed','cancelled','failed')`, `created_at`, `updated_at`, `completed_at` |
| `users/{uid}/chats/{chatId}` | `public.ai_chats` | `(user_id UUID, chat_id TEXT) PK`, `title TEXT (<=200)`, `scope JSONB`, `updated_at TIMESTAMPTZ` |
| `users/{uid}/chats/{chatId}/messages/{id}` | `public.ai_messages` | `id TEXT PK`, `(user_id, chat_id) FK ON DELETE CASCADE`, `role CHECK IN ('user','ai')`, `text TEXT`, `blocks JSONB`, `sources JSONB`, `intent TEXT`, `fb CHECK IN ('up','down')`, `created_at TIMESTAMPTZ` |
| `rate_limits/{key}` | `public.rate_limits` | `(user_id UUID, operation TEXT) PK`, `count INT`, `reset_at TIMESTAMPTZ` (server-only, no client RLS policy) |
| *(New)* | `public.migration_id_mappings` | `(entity_type TEXT, firebase_id TEXT) PK`, `supabase_id TEXT NOT NULL`, `checksum TEXT`, `metadata JSONB`, `migrated_at TIMESTAMPTZ` (server-only) |

---

## 3. Security Model: RLS Matrix & Column-Guard Triggers

1. **`public.profiles`**:
   - Direct `SELECT`/`INSERT`/`UPDATE`: `id = auth.uid()` only (prevents client-side email enumeration or bulk user scraping). `DELETE` denied to client (handled by `account` Edge Function).
   - **Triggers `enforce_profile_insert_rules` & `enforce_profile_update_rules`**: Prevent client-side forging of `legacy_firebase_uid` or arbitrary `email` values on insert or update.
   - Collaborator & connection display names/avatars resolved through `SECURITY DEFINER` RPC `get_peer_profile(target_id UUID)` which checks that caller is self, connected peer, or co-member on a non-deleted note.
2. **`public.notes`**:
   - `SELECT`: `user_id = auth.uid()` OR (`deleted_at IS NULL` AND (`auth.uid() = ANY(live_member_ids)` OR `auth.uid() = ANY(pending_shared_with_user_ids)`)). Soft-deleted notes immediately vanish from live editors/viewers and pending copy recipients while remaining visible in the owner's Recently Deleted list.
   - `INSERT`: `user_id = auth.uid()`, `deleted_at IS NULL`, `revision = 0`, empty sharing/live membership arrays.
   - `UPDATE`: Owner OR (`deleted_at IS NULL` AND `auth.uid() = ANY(live_member_ids)` AND `live_roles ->> (auth.uid()::text) = 'edit'`).
   - **Trigger `enforce_note_update_rules`**: Rejects client-initiated modifications to `user_id`, `note_id`, `created_at`, `source_owner_id`, `source_note_id`, `live_member_ids`, `live_roles`, `shared_with_user_ids`, or `pending_shared_with_user_ids`. Enforces that non-owner live editors cannot alter `is_favorite` or `deleted_at`, and must increment `revision = OLD.revision + 1` with `last_edited_by = auth.uid()`.
   - `DELETE`: Denied to client; permanent deletion requires `delete_trashed_note` / `note-sharing` Edge Function on an already trashed note (`deleted_at IS NOT NULL`) owned by caller.
   - **Declining Pending Copy**: `SECURITY DEFINER` RPC `decline_note_share(p_note_id TEXT)` allows a recipient in `pending_shared_with_user_ids` to remove only themselves without granting write access to any other column.
3. **Private User Data (`user_settings`, `user_favorites`, `ai_chats`, `ai_messages`, `ai_requests`, `user_invitations`, `notifications`)**:
   - Strictly isolated to `user_id = auth.uid()`.
   - `notifications`: client can `SELECT`, `DELETE`, and `UPDATE` only `read` (`enforce_notification_update_rules` trigger prevents forging `title`/`body`/`type`). `INSERT` restricted to server triggers & privileged functions.
4. **`public.connection_requests`**:
   - `SELECT`: `from_user_id = auth.uid() OR to_user_id = auth.uid()`.
   - `INSERT`: Server-only via `connections` Edge Function (`requestConnection` enforces rate limits, email lookup, and target `requests` privacy `'everyone' | 'mutual' | 'nobody'`).
   - `UPDATE`: Recipient (`to_user_id = auth.uid()`) only while `OLD.status = 'pending'` and `NEW.status IN ('accepted', 'rejected')`, leaving identity columns immutable. Trigger `on_connection_accepted` automatically inserts the `Connection accepted` notification for `from_user_id`.
   - `DELETE`: `from_user_id = auth.uid() OR to_user_id = auth.uid()`.

---

## 4. Transactional Concurrency, Realtime & Offline Strategy

### 4.1 Collaborative Document Concurrency (Requirement 7)
- PostgreSQL `SECURITY DEFINER` RPC `commit_note_revision(...)` (9-argument signature including optional `p_created_at TIMESTAMPTZ` for calendar-dated note creation) acquires a row lock (`SELECT ... FOR UPDATE`), verifies owner/live-editor permission and `deleted_at IS NULL`, checks `revision = p_expected_revision`, and:
  - On match: writes updated fields, increments `revision = revision + 1`, sets `last_edited_by = auth.uid()`, triggers 5-minute windowed collaborator activity notification (`notify_live_note_edited`), and returns `{ committed: true, note }`.
  - On mismatch: returns `{ committed: false, remote }` without overwriting.
- `NoteRepository.saveCollaborative(local, base)` runs the existing Quill Delta Operational Transformation merge (`mergeContent(base, local, remote)` in `lib/utils/collaborative_document.dart`), attachment union merge, and competing metadata detection (`choose()`), retrying `commit_note_revision` against `remote.revision` or raising `NoteConflictException(remote)` so the UI conflict recovery banner ("Keep mine" / "Use latest" / "Duplicate mine") works identically.

### 4.2 Offline Persistence & Reconnect Outbox (Requirement 8)
- `lib/services/offline_note_store.dart` provides explicit per-user persistence via `SharedPreferences`:
  - **Read Cache**: `noted.cache.notes.<uid>` and `noted.cache.pending_shares.<uid>` hydrate `NoteViewModel` immediately on cold start or offline launch.
  - **Durable Pending-Write Outbox**: `noted.outbox.notes.<uid>` persists queued creates, collaborative saves (`{local, base}` snapshots), favorite toggles, and trash/restore operations across offline sessions and app restarts.
  - **Reconnect Flush & Conflict Recovery**: When network connectivity or Supabase auth session recovers, `NoteRepository` replays queued operations in order through `commit_note_revision`, preserving OT merge and automatically saving an owned `(Offline conflict copy)` note whenever an unresolvable metadata/content conflict occurs during background replay so zero user work is ever lost.
  - **Account Isolation**: Cache and outbox keys are namespaced by `uid` and purged on account deletion.

---

## 5. Private Media & Independent Copy Design (Requirement 9)

- **Buckets**: `avatars` (`public = false`, 5 MB, `image/*`) and `note-media` (`public = false`, 30 MB, `image/*`, `audio/*`).
- **Canonical Reference Format**:
  - Uploaded attachments store `path` (`users/<uploaderUid>/notes/<noteId>/<ts>_<safeName>`) and canonical URI `noted-media://note-media/<path>` inside Quill embeds and attachment metadata so permanent public tokens are never stored in document JSON.
  - `MediaUrlResolver` resolves `noted-media://...` URIs and storage paths via `storage.from(bucket).createSignedUrl(path, 3600)` with a 50-minute in-memory TTL cache cleared on sign-out.
- **Revocation**: Removing a collaborator (`setLiveRole(..., 'none')`) or trashing a note immediately blocks new signed URL generation via `storage.objects` RLS; any previously issued URL expires within at most 60 minutes.
- **Independent Copies**: `acceptNoteCopy` and `duplicateNote` copy every attachment in `note-media` to `users/<recipientUid>/notes/<newNoteId>/<uuid>_<safeName>`, rewrite both `attachments` metadata and inline document references, and clean up partial copies on error.

---

## 6. Edge Functions, AI, Email & Scheduling

| Function | Actions / Schedule | External Integrations & Secrets |
|---|---|---|
| `noted-ai` | `ask`, `cancel`, `clearHistory` | OpenAI-compatible adapter (`AI_BASE_URL=https://openrouter.ai/api/v1`, `AI_MODEL=openrouter/free`, secret `AI_API_KEY`). Enforces 40/hr rate limit, scoped retrieval, source subset validation, source re-authorization before commit, and `ai_requests.cancelled` abort check. |
| `note-sharing` | `setLiveRole`, `queueNoteCopy`, `acceptNoteCopy`, `duplicateNote`, `deleteNote` | Enforces connection status, `reshare` & `copies` preferences, independent Storage copies, permanent trash media cleanup, and activity email dispatch. |
| `connections` | `requestConnection`, `resendConnectionRequest`, `inviteByEmail` | Server-side email lookup, `requests` privacy (`everyone`/`mutual`/`nobody`), deterministic pair key, Resend email invitations (`RESEND_API_KEY`, `NOTED_EMAIL_FROM`, `NOTED_APP_URL`). |
| `account` | `prepareAccount`, `exportData`, `deleteAccount` | Password-verified full account wipe (Storage + memberships + connections + rows + `auth.admin.deleteUser`). |
| `scheduled-maintenance` | `pg_cron` (`0 * * * *` recap & queued emails; `0 3 * * *` 30-day trash + Storage purge) | Authenticated via `CRON_SECRET`; respects `timezone_offset_minutes` and `quiet_hours`. |

---

## 7. Account Migration & Optional Analytics Handling

### 7.1 Account Migration Strategy (Requirement 5)
- **Truthful Password Policy**: Firebase Authentication hashes passwords with Google's modified scrypt using project-private signer/salt keys that are not exportable without Firebase Admin project owner credentials, and cannot be verified without those exact parameters. **We do not claim existing passwords transfer automatically.**
- **Supported Cutover Flow**:
  1. `export_firebase.mjs` exports Auth users, Firestore documents/subcollections, and Storage media (when Firebase Admin credentials are provided) into a checksummed local bundle.
  2. `import_supabase.mjs` creates Supabase Auth users with deterministic UUIDv5 IDs (`email_confirm: true`), imports all mapped rows and private Storage objects idempotently, and supports `--dry-run`.
  3. Migrated users authenticate via **Password Reset ("Forgot password?" on the Sign In screen)** on first login to set their Supabase password cleanly (or optional scrypt hash import if project hash parameters are supplied via Supabase CLI/Management API).

### 7.2 Optional Analytics Audit
- Previously, `firebase_analytics` required `firebase_core` and `google-services.json`, linking the binary to Firebase.
- **Final Handling**: Removed `firebase_analytics` and the Google Services Gradle plugin completely so zero Firebase SDKs remain in the app. Preserved the user-facing `Settings > Privacy > Usage analytics` toggle (`SettingsModel.analytics`, default `false`, synced to `public.user_settings`) wired to a lightweight, consent-gated `AnalyticsService` (`lib/services/analytics_service.dart`) that is strictly a no-op when `analytics == false` and emits structured client events only when explicitly enabled and an analytics sink is configured.

---

## 8. Cutover & Rollback Plan
1. **Zero Source Destruction**: The existing Firebase project (`superheromood-54691`), Firestore data, Auth users, and Storage buckets are **never** modified or deleted by any migration script.
2. **Dry-Run & Validation Gate**: Run `node tools/migration/import_supabase.mjs --dry-run`, then import to staging/production Supabase, then run `node tools/migration/validate_migration.mjs` to verify counts, ownership, memberships, deep-link `note_id` parity, and Storage object existence before shipping the Supabase APK.
3. **Rollback**: `node tools/migration/rollback_supabase.mjs` cleanly removes only entities recorded in `public.migration_id_mappings` (rows, Storage objects, and imported Auth users) while leaving the original Firebase deployment untouched if an emergency rollback to the prior Firebase build is needed.
