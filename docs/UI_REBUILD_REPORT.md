# Noted UI rebuild and verification

> [!NOTE]
> **Historical UI Milestone Record**: This report records the 2026-10-26 UI rebuild verification on `feature/noted-ui-revised` prior to the full Supabase backend migration on `feature/supabase-migration`. Firebase Auth, Cloud Firestore, Firebase Storage, Cloud Functions, and Firebase Analytics have since been completely replaced by Supabase (`supabase/`, `lib/services/supabase_service.dart`). For current setup, backend architecture, and verification steps, see [../README.md](../README.md), [SUPABASE_SETUP_AND_CUTOVER.md](SUPABASE_SETUP_AND_CUTOVER.md), and [SUPABASE_MIGRATION_PLAN.md](SUPABASE_MIGRATION_PLAN.md).

Branch: `feature/noted-ui-revised`. Date: 2026-10-26. Flutter remains the application framework, with Provider/MVVM, Firebase Auth, Firestore and the original `docs/Logo.png`.

## Delivered implementation

The supplied React prototype is translated into native Flutter screens: welcome/sign-in/sign-up, Home, Notes, AI, Connections, Profile, Settings and editor overlays. DM Sans and italic Newsreader are bundled locally; reference SVG paths and both color palettes are ported. Favorites moved into Notes beside All and Live. The month calendar supports navigation, daily note counts and note creation on the selected date.

The editor is visual rich text with formatting, checklists, color/category/date controls, serialized autosave, focus mode, duplicate, trash/Undo and uploads for images, voice recordings and drawings. It does not expose Markdown source. Legacy content is rendered as a rich document and converted only after editing. Inline images imported with an existing document have a renderer and safe unavailable-media fallback.

Live notes have server-controlled edit/view membership, realtime Firestore snapshots, expiring presence and Quill Delta transformations inside retrying transactions. Conflicting metadata keeps the local draft for review/recovery. Copy sharing remains an independent-copy workflow. Duplication and accepted copies create independent media paths and download tokens.

AI uses a server-only OpenAI-compatible adapter, initially OpenRouter `openrouter/free`. Retrieval enforces current user access and requested scope, validates sources and structured output, and supports history, feedback, retry, cancellation, saving and insertion. Connections, invitation email, activity, notification preferences and weekly recap have actual server implementations. Settings include synced preferences, profile/account actions, native app lock, export and recently deleted notes.

## Compatibility and migration

See [feature reconciliation](UI_REBUILD_PLAN.md) for retained features. Existing note IDs, owner identity, timestamps, categories and content remain. New fields include color, liveMemberIds/liveRoles, revision, deletedAt, attachments and copy provenance. Shared favorites live under each user's private favorites collection. Settings and chat history use private user subcollections.

On authentication, `prepareNotedAccount` transactionally adds only missing `deletedAt: null` metadata to accessible legacy notes. It rechecks the field before writing, does not restore deleted notes, and does not rewrite content. A private schema marker avoids repeating the scan. Deploy the composite indexes with the rules for Live/pending queries. Owned notes can load independently of auxiliary favorite/live stream failures.

No production deployment, secret creation, Git commit or push was performed. The original pre-existing generated plugin registrant change was preserved; dependency tooling also updates that generated file.

## Verification

Final command results after the last integration pass are recorded below. Tests use isolated fixtures; production screens do not seed demo data.

| Check | Result |
|---|---|
| Firestore and Storage emulator tests | 17 passed, 0 skipped, using firebase-tools@14.27.0 on project demo-noted |
| Inline rich-document image regression | 4 editor document tests passed |
| `flutter pub get` | Passed |
| `flutter analyze` | No issues found |
| `flutter test` | 87 passed |
| `npm run check` | Passed |
| `npm audit --omit=dev` | 0 vulnerabilities |
| `git diff --check` | Passed; existing CRLF normalization warnings only |
| `flutter build apk --no-pub -v` | Passed, exit 0; 849 Gradle tasks, 8m 50s; APK 64.6 MB |

APK: `build/app/outputs/flutter-apk/app-release.apk`, 67,725,108 bytes, built 2026-10-26 20:57 Jakarta time. SHA-256: `4e8a963615867d76feb0a3955c1f49c7ca83036482d2f05e0eaaabe0b73e597e`. Final build has no Kotlin metadata incompatibility diagnostics. Third-party Java/Gradle deprecation and unmatched ProGuard-rule notices remain informational.

The emulator suite covers authorization for editor/viewer/stranger, revision checks, deleted-note access, filtered Live and pending query results, private favorites/preferences, invitations and Storage upload/read boundaries. Pure server tests cover scoped retrieval, source validation, HTML export escaping, notifications and independent media copies.

Emulator command: `npx --yes firebase-tools@14.27.0 emulators:exec --only firestore,storage --project demo-noted "node --test functions/test/*.test.js"`. Server checks run from `functions/`; Flutter checks run from the repository root. Emulator results verify database/storage rules and pure server helpers, not deployed callable functions or external services.

Responsive widget/golden coverage includes 360/390/430 logical-pixel widths in light/dark themes, onboarding, library/calendar, settings/profile/connection states and the visual editor. Regression tests cover in-flight save/create changes, collaborative transforms, app lock above pushed routes, personal favorites, AI cancellation/history invalidation and links. Screenshots were inspected; a quantitative pixel comparison against the React runtime has not been performed, so exact pixel parity is not claimed.

Fixture previews: [visual editor](../test/goldens/editor_390_light.png), [Notes](../test/goldens/library_390_light.png), [calendar in dark mode](../test/goldens/calendar_390_dark.png), [welcome](../test/goldens/welcome_390_light.png). These are test fixtures, not screenshots of a signed-in production account.

Build integration first required newer AGP for AndroidX AAR requirements, then exposed Firebase Auth's Kotlin 2.3 metadata in the shrinker. Final configuration uses AGP 8.13.2 (R8 8.13.19), Gradle 8.13 and Kotlin 2.3.10, following [Android compatibility guidance](https://developer.android.com/build/releases/agp-8-13-0-release-notes). A stalled Android Build Tools 35 download was resolved by installing the official archive after verifying its published SHA-1. Earlier intermediate attempts failed or stalled before these corrections; the final result is reported separately above. Java 17 is used for Android builds.

## Configuration and outstanding acceptance

Use [backend setup](../functions/README.md). Set `AI_API_KEY` and `RESEND_API_KEY` as Firebase secrets. Copy the environment example to `functions/.env.superheromood-54691`, supply a verified `NOTED_EMAIL_FROM` and real `NOTED_APP_URL`, then deploy functions, Firestore indexes/rules and Storage rules. These services are not activated by installing the APK.

To change model, edit `AI_MODEL` and redeploy functions. To change an OpenAI-compatible provider, edit `AI_BASE_URL`, rotate `AI_API_KEY` and redeploy. Keys never belong in Dart or Git.

No Android device was connected for acceptance. Two-device concurrent editing, member revocation, background/reconnect behavior, uploads/recording/playback, biometric or device-PIN authentication and external link launching still require device/staging checks. OpenRouter generation and Resend delivery cannot be verified before credentials and deployment. Firebase platform configuration currently targets Android; iOS/web setup is not supplied by this repository.

Known differences from the requested prototype behavior: AI output appears after the full response is generated and validated, rather than token streaming. The spellcheck preference currently controls note titles; the Quill public editor API does not expose a body spellcheck switch. Attachments use a document attachment area, while imported inline images can render within the document. A server/service failure can still require retrying account deletion; cleanup is idempotent. Quiet-hour email is suppressed instead of queued for later delivery. Existing release signing is for local testing and requires a distribution keystore before store submission.
