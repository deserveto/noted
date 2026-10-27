# Noted

Combined UI/backend PR review: [Full change review](docs/FULL_CHANGE_REVIEW.md). Historical migration fixes: [Supabase remediation report](docs/SUPABASE_REMEDIATION_REPORT.md).

A calm Flutter notes app for personal and business use, built with MVVM/Provider and backed by Supabase Auth, PostgreSQL (with Row Level Security), Supabase Realtime, Private Supabase Storage, and Supabase Edge Functions.

![Noted logo](docs/Logo.png)

The revised interface follows the supplied prototype: onboarding, a useful monthly calendar, a searchable library with Favorites/Live filters, a visual rich-text editor, collaborative notes, AI, connections, profile insights and synced settings. The original Noted logo remains.

## Run and verify

Verified development toolchain: Flutter 3.41.6 / Dart 3.11.4 and Node.js 22+ on Windows. Android uses Java 17, Android Gradle Plugin 8.13.2, Gradle 8.13 and Kotlin 2.3.10.

```powershell
# 1. Run Supabase SQL/RLS, Edge Function & migration tooling tests (89 tests)
Set-Location tools/migration
npm test
Set-Location ../..

# 2. Configure local public Supabase client values (if not already present)
if (-not (Test-Path .env.supabase.json)) {
  Copy-Item .env.supabase.example.json .env.supabase.json
}

# 3. Run Flutter verification (115 tests) & build release APK
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=.env.supabase.json
flutter build apk --release --dart-define-from-file=.env.supabase.json
```

Notes use versioned Quill rich documents; legacy Markdown remains readable and imports without destructive bulk rewriting. Realtime collaborative saves rebase Quill Delta operations via atomic revision-checked RPCs (`commit_note_revision`, including calendar-dated creation timestamps) and preserve competing metadata or offline conflict copies for user review. Offline edits queue in a per-account local outbox (`OfflineNoteStore`) and replay on reconnect. Copy sharing and duplication copy private media to independent Storage paths (`noted-media://note-media/...`) resolved via short-lived signed URLs.

## Supabase backend configuration

Noted's Supabase backend (Auth, PostgreSQL schema + RLS + RPCs, Private Storage buckets `avatars` and `note-media`, and all 5 Edge Functions) is defined in `supabase/` and verified end-to-end against a live Supabase project. For new environments or redeployments, follow [docs/SUPABASE_SETUP_AND_CUTOVER.md](docs/SUPABASE_SETUP_AND_CUTOVER.md) and architecture details in [docs/SUPABASE_MIGRATION_PLAN.md](docs/SUPABASE_MIGRATION_PLAN.md):

```powershell
if (-not (Test-Path supabase/.env)) {
  Copy-Item supabase/.env.example supabase/.env
}
npx supabase link --project-ref <your-project-ref>
npx supabase db push
npx supabase secrets set --env-file supabase/.env --project-ref <your-project-ref>
npx supabase functions deploy noted-ai --no-verify-jwt --project-ref <your-project-ref>
npx supabase functions deploy note-sharing --no-verify-jwt --project-ref <your-project-ref>
npx supabase functions deploy connections --no-verify-jwt --project-ref <your-project-ref>
npx supabase functions deploy account --no-verify-jwt --project-ref <your-project-ref>
npx supabase functions deploy scheduled-maintenance --no-verify-jwt --project-ref <your-project-ref>
```

The AI service uses OpenRouter (`AI_BASE_URL=https://openrouter.ai/api/v1`, `AI_MODEL=openrouter/free`); `AI_API_KEY`, `RESEND_API_KEY`, and `CRON_SECRET` live exclusively in Supabase Edge Function secrets. For outbound Resend emails (invitations, activity notifications, Sunday recaps), set `NOTED_EMAIL_FROM` to an address on a domain verified in [Resend Domains](https://resend.com/domains) (or `"Noted <onboarding@resend.dev>"` when testing delivery to your own Resend account email) and push updated secrets with `npx supabase secrets set --env-file supabase/.env --project-ref <your-project-ref>`. Until a verified sender domain is configured, in-app connection requests and notifications continue to work cleanly without failing requests. To switch AI model or OpenAI-compatible provider, update `AI_MODEL` / `AI_BASE_URL` / `AI_API_KEY` via `npx supabase secrets set` without rebuilding Flutter. Optional anonymous usage analytics (`AnalyticsService`) are strictly disabled by default and gated on user consent in Settings. Optional feedback email is configured with `--dart-define=NOTED_FEEDBACK_EMAIL=...`; the default opens the repository's issue form.

## Optional migration from Firebase

Fresh Supabase deployments do **not** need to run the Firebase migration scripts. If you later choose to import historical users, notes, connections, chats, and media from the legacy Firebase project, repeatable read-only export, dry-run/live import, 11-point validation, and rollback scripts live in [tools/migration/README.md](tools/migration/README.md). Legacy Firebase rules/functions in `functions/`, `firestore.rules`, `storage.rules`, and `firebase.json` are retained read-only solely as historical audit reference; the Flutter application has zero Firebase dependencies.

## Implementation and acceptance notes

See [Supabase setup & cutover](docs/SUPABASE_SETUP_AND_CUTOVER.md), [migration plan](docs/SUPABASE_MIGRATION_PLAN.md), [design system](DESIGN.md), [UI rebuild plan](docs/UI_REBUILD_PLAN.md), and [UI rebuild report](docs/UI_REBUILD_REPORT.md). Responsive/golden fixtures in `test/` use test-only data.

Live backend checks have verified Supabase Auth sign-up, profile/settings triggers & RPCs, `commit_note_revision` CAS concurrency, private Storage uploads & signed URLs, independent media duplication (`note-sharing`), live OpenRouter responses (`noted-ai`), `scheduled-maintenance`, and full account/media deletion (`account`). Remaining physical-device acceptance checks are: concurrent editing across two physical devices, hardware voice recording/playback, camera/gallery upload, biometric/device-PIN lock, external deep-link taps (`noted://app/notes/<id>` and `noted://app/auth-callback`), and verified-domain Resend email delivery. The spellcheck preference controls note titles; Quill's current public editor API does not provide a body spellcheck switch. AI responses are validated after generation rather than streamed token by token. Configure your release keystore before store distribution.
