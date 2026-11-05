# Changelog

## 2.0.1 beta — build 4 — 2026-11-05

- Added open-enrollment Android beta updates for every signed-in Noted account, with changelogs and release history in Settings.
- Added private APK storage, authenticated short-lived download links and a verified publication process.
- Added safe-screen reminders and installed-build-based “What’s new”; Android installation remains user-controlled.
- Included the current main-branch workspace filtering, shared-note previews, inline image placement, connection refresh and delete/undo corrections.

Existing testers must manually install this first updater-enabled build using the same signing identity as version 2.0.0. See [the beta release runbook](docs/beta-releases.md). Physical-device replacement installation and persistence acceptance remain separate checks.

## [2.0.0](https://github.com/deserveto/noted/releases/tag/v2.0.0) — 2026-11-01

A complete interface rebuild and backend transition for Noted, merged in [PR #50](https://github.com/deserveto/noted/pull/50).

### A new space for your notes

- Rebuilt onboarding and the five-tab Home, Notes, AI, Connections, and Profile shell.
- Added a warm sage-and-paper visual system, bundled DM Sans/Newsreader type, light/dark themes, responsive layouts, and golden coverage.
- Added Quill rich-text writing, calendar organization, favorites, categories, note colors, trash/restore, and synced preferences.
- Added images, drawings, voice memos, profile photos, account export/deletion, and app lock.

### A Supabase foundation

- Replaced Flutter Firebase dependencies with Supabase Auth, PostgreSQL/RLS, Realtime, private Storage, and five Edge Functions.
- Added revision-checked collaborative editing, edit/view roles, expiring presence, member revocation, and independent copy sharing.
- Added per-account offline caching and an outbox that preserves recovery drafts and replays pending edits.
- Added note-scoped AI, validated sources, structured answers/flashcards, cancellation, feedback, and conversation history.
- Added personal workspaces, saved study decks, and selected-text AI editing. Prior chat context is restricted to the current note scope.
- Extended JSON exports to include workspaces, note assignments, and study decks when available. Attachment files and automatic restore are not included.
- Added in-app activity, quiet hours, email-provider integration, scheduled recaps, and claimed trash/media cleanup.
- Added optional read-only Firebase export, state-preserving import, parity validation, and guarded database-only rollback.

### Reliability corrections

- Prevented stale account/profile/logout results from replacing a newer session.
- Fixed deletion during a new note's pending save, library search reset/debounce, and delayed AI cancellation.
- Reauthorized duplication after access/revision changes and serialized AI history clearing against in-flight commits.
- Preserved legacy verified/disabled Auth states and corrected the legacy connection-request export path.

### Upgrade and deployment notes

- Configure a Supabase environment before running v2. The app does not continue using Firebase; historical user/data import is optional and requires the reviewed tooling.
- On November 1, the linked backend's migration history matched all 13 current migrations; the `noted-ai`, `note-sharing`, and `account` handlers were deployed and checked against this candidate. Authenticated end-to-end acceptance remains outstanding.
- Gmail Auth SMTP delivery/confirmation, the separate Resend sender, and physical-device acceptance remain open. See [release readiness](README.md#release-readiness) before public rollout.
- Android version is `2.0.0` (build `3`). The APK uses the configured Noted upload certificate. The 1.0.0 APK used a different debug certificate and cannot be upgraded in place; preserve local notes/drafts before changing installations.
- Local verification covers 99 backend tests, 150 Flutter tests, zero analysis issues, five Deno entry points, and a signed release APK. This is not a claim that the remaining live/device checks passed.

### Repository presentation

- Rebuilt the root README with light/dark vector banners, six paired app previews, architecture, quick start, verification, and release notes.
- Added backend/documentation landing pages and refreshed the migration and historical Firebase READMEs.
- Removed the fully merged feature branches after checking ancestry, worktrees, and stashes.

## [1.0.0](https://github.com/deserveto/noted/releases/tag/v1.0.0) — 2026-06-15

Previous published release. See its GitHub release page for the original notes and assets.
