# Beta update verification — 2026-11-05

Historical first-pass verification, before the authorized deployment/release follow-up. Verified locally on Windows. At this stage no infrastructure was deployed, workflow dispatched, APK uploaded, or release published. See [the follow-up release record](releases/2026-11-05-beta-2.0.1-build-4.md) for the open-enrollment policy and current release evidence.

## Results

| Command | Result |
| --- | --- |
| `npm test` in `tools/migration` | 121 passed; 0 failed, skipped or cancelled |
| `flutter pub get` | Passed; existing dependencies and lockfile retained |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub` | 169 passed, including existing goldens |
| `flutter build apk --release --dart-define-from-file=.env.supabase.json --dart-define=NOTED_UPDATE_CHANNEL=beta` | Passed; signed universal APK, 64.4 MB reported by Flutter |
| `npx --yes deno@2.9.6 check supabase/functions/app-updates/index.ts` | Passed |
| `node --check tools/releases/release.mjs` | Passed |
| `git diff --check` | Passed |

The beta flag explicitly selects distribution independently of the existing backend environment. The source remains `2.0.0+3`: this is a verification artifact, not the next beta release. Assign a unique higher build when publishing.

Final APK: `build/app/outputs/flutter-apk/app-release.apk`, 67,509,015 bytes. SHA-256: `02d4a294bd5ee944c62d72dd31618dc55fdd0dc420e96b2a7b19b3fe37973792`.

Android SDK `aapt dump badging` confirms `com.noted.app`, version `2.0.0`, build `3`, minimum SDK `24`, and `armeabi-v7a`, `arm64-v8a`, `x86_64`. `apksigner verify --verbose --print-certs -Werr` succeeds: APK Signature Scheme v2 verifies, with one signer. This verifies the local signature; continuity with previously installed tester APKs still needs an independently trusted certificate pin and device acceptance.

## Changed files and architecture

- `lib/models/app_release.dart`, `installed_app.dart`: pure Dart validated metadata, numeric installed identity and SDK compatibility.
- `lib/repositories/update_repository.dart`: lazy authenticated Supabase reads, exact installed-build notes, fresh download authorization and request timeouts.
- `lib/services/update_service.dart`, Android `MainActivity.kt`: package information, SDK lookup through a small method channel, strict HTTPS origin/path validation, external browser launch; no new dependency.
- `lib/viewmodels/update_viewmodel.dart`: coalescing, automatic check cooldown, per-account/release reminders, quiet errors and installed-upgrade bookkeeping in isolated `updates.*` preferences.
- `lib/services/update_coordinator.dart`, `app.dart`, `main.dart`, `app_lock_gate.dart`: Provider/lifecycle/Navigator wiring and lock visibility. Automatic prompts wait for the main shell. Note persistence and collaboration remain unchanged.
- `lib/widgets/update_dialog.dart`, `lib/views/updates_page.dart`, `settings_page.dart`: changelogs, installation explanation, loading/retry feedback, current version/channel, manual checks and release history.
- `supabase/migrations/20261105000001_beta_app_updates.sql`, `supabase/functions/app-updates/`, config and CI: private membership/releases, explicit privileges/RLS, dedicated private bucket, immutable artifact guards, final publication RPC, authenticated check/history/download.
- `tools/releases/`, `.github/workflows/beta-release.yml`: snapshot inspection of signed APK identity and pinned certificate, immutable upload, draft metadata, binary readback/hash verification, publication last and separate protected manual dispatch.
- `supabase/tests/app_updates.test.mjs`, `release_publication.test.mjs`, updated bucket expectation, `test/update_viewmodel_test.dart`, `update_ui_test.dart`, six update goldens: authorization, fail-safe publication, malformed data, concurrency, reminders, installed upgrades, lifecycle deferral, browser failure, history and accessibility.

New goldens cover light/dark at 360, 390 and 430 pixels. The 360-pixel light/dark images were visually inspected; a separate narrow 200% text test passes. Independent review found version-validation and old-release-note lookup mismatches; both were corrected and rechecked. APK inspection snapshots bytes first to avoid a concurrent build replacing the artifact being approved.

## External setup and limitations

The original follow-up was deployment, CI/signing setup and bootstrap distribution. The user subsequently chose open enrollment for all signed-in accounts, so individual tester enrollment was removed. Follow [the release runbook](beta-releases.md) and the current release record for publication/withdrawal commands, signing backups, corrective releases and Play migration considerations.

Physical-device/browser installation was unavailable. The runbook's acceptance checklist covers replacement installation, login/local notes/pending writes, cancelled download/install, browser return, offline startup, expired links, App Lock, editor/audio/recovery deferral and once-only upgrade notes. Local tests do not claim those device outcomes.

Initial scope is one Android beta channel, universal APKs and one certificate. History shows the latest 50 compatible published releases; installed-upgrade notes use exact-build lookup. Links expire after 15 minutes and cannot retract downloaded binaries. Preference resets can repeat reminders or reset upgrade detection. The browser downloads the APK; Flutter does not verify that downloaded binary. Updates remain advisory.
