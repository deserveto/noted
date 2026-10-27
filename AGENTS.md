# Noted Project Context

## Project Overview

Noted is a Flutter mobile note-taking app for personal and business use: capture rich-text notes, organize them by category and calendar date, mark favorites, collaborate live with edit/view roles and presence, attach images/drawings/voice memos, explore notes with Noted AI, connect with collaborators by email, and share independent note copies. Built with MVVM architecture and Provider state management, backed by **Supabase** (Supabase Auth, PostgreSQL with Row Level Security, Supabase Realtime, Private Supabase Storage, Edge Functions, and `pg_cron` schedules).

Verified environment: Flutter 3.41.6 (stable) / Dart 3.11.4 and Node.js 22+ on Windows. `flutter`, `dart`, and `node` are on `PATH`.

The repository is a git repo (remote: `https://github.com/deserveto/noted.git`, default branch: `main`). The combined UI/backend migration was merged in PR #50; its fully merged feature branches have been removed.

## Current Features (verified in code)

- **Auth & Account**: email/password sign up, sign in, logout, password reset (`noted://app/auth-callback` in-app recovery), profile photo upload, password update, JSON export, and full account deletion via `AuthViewModel` + `AuthRepository` + `account` Edge Function.
- **Notes CRUD & Trash**: title, WYSIWYG Quill Delta content (with non-destructive legacy Markdown import), category, note color, favorite flag, soft delete (`RecentlyDeletedPage`), restore, and 30-day scheduled purge.
- **Live Collaboration & Concurrency**: edit/view roles, expiring Realtime presence (`note_presence`), member revocation, and atomic revision-checked CAS operational transformation (`commit_note_revision` + `CollaborativeDocument`).
- **Offline Support**: per-account local note cache and coalescing pending-write outbox (`OfflineNoteStore`) replayed automatically on reconnect.
- **Private Media**: images, doodles, voice memos, and avatars stored in private Supabase Storage buckets (`note-media`, `avatars`) with `noted-media://` URIs resolved to short-lived signed URLs (`MediaUrlResolver`) and copied independently on share/duplication.
- **Noted AI**: scoped note retrieval, source validation, structured blocks, cancellation, feedback, and chat history via the `noted-ai` Edge Function (OpenRouter `openrouter/free` default, configurable OpenAI-compatible adapter).
- **Connections & Activity**: email connection requests, Resend email invitations, activity feed (`notifications`), quiet hours, and Sunday weekly recaps (`scheduled-maintenance`).
- **Theme, Accessibility & Navigation**: light/dark/system themes (`AppColors`, `AppTheme`), DM Sans + Newsreader italic typography, App Lock (`AppLockGate`), and 5-tab shell (Home, Notes, AI, Connections, Profile).

## Architecture

Actual structure (follow it; keep responsibilities clear):

```text
lib/
  main.dart          # SupabaseService.initialize() + MultiProvider wiring
  app.dart           # MaterialApp, named routes, deep links, AuthGate, AnalyticsService
  models/            # pure Dart + Postgres/JSON mapping: note_model, user_model, connection_model, settings_model
  repositories/      # Supabase access: auth, note, connection, ai, settings, activity, profile
  services/          # supabase_service, media_url_resolver, offline_note_store, analytics_service, attachment_service, collaboration_service, account_services, app_lock_gate
  utils/             # app_colors, app_theme, app_routes, validators, document_codec, collaborative_document, markdown_formatter, note_links
  viewmodels/        # Provider ChangeNotifiers: auth, note, connection, settings, theme
  views/             # welcome, sign_in/up, main_shell, home, notes, ai, connections, profile, settings, add_edit_note, note_detail, note_link
  widgets/           # noted_ui, reference_icon, note_card, note_attachments, rich_note_embed, ai_blocks, activity_sheet, share_note_sheet, calendar_sheet, formatting_toolbar
supabase/
  config.toml        # Local Supabase CLI & Edge Function config
  migrations/        # Versioned PostgreSQL schema, RLS, triggers, RPCs, private Storage & pg_cron setup
  functions/         # Deno Edge Functions: noted-ai, note-sharing, connections, account, scheduled-maintenance
  tests/             # Automated PGlite SQL/RLS, Edge Function & migration test suites
tools/migration/     # Repeatable Firebase -> Supabase export, import (--dry-run), validation & rollback CLI
```

Key patterns:

- `main.dart` calls `SupabaseService.initialize()` (reading `--dart-define-from-file=.env.supabase.json`) and wires `ChangeNotifierProxyProvider`s bound to `AuthViewModel`.
- Repositories resolve `SupabaseService.maybeClient` lazily so widget/golden tests run without live network credentials.
- Never introduce Firebase dependencies (`firebase_*`, `cloud_*`) or heavyweight DI frameworks.
- Never place API keys, `SUPABASE_SERVICE_ROLE_KEY`, or DB credentials in Flutter, logs, Git, or chat.

## Design Direction

- Approved UI reference: `C:/dev/NotedUIRevised` (preserve `docs/Logo.png`, DM Sans + Newsreader italic fonts, `AppColors`, light/dark palettes, and WYSIWYG Quill editing without visible Markdown markers).
- Consult `DESIGN.md` before any UI work and keep all golden tests in `test/goldens/` passing.

## Verification Expectations

Before claiming completion, run:

- `Set-Location tools/migration; npm test` — runs PostgreSQL/RLS, Edge Function, and migration tooling tests (`89` tests at the latest full review verification)
- `flutter pub get`
- `flutter analyze` — must be clean (`0` issues)
- `flutter test` — all unit, widget, golden, and Supabase migration tests must pass (`115` tests at the latest full review verification)
- `flutter build apk --release --dart-define-from-file=.env.supabase.json` — full Android APK verification wired to `.env.supabase.json`
