# Noted Implementation Log

## 2026-06-14

### Requested Scope

- Build the Flutter app described in `docs/Noted_PRD_dan_Kerangka_Desain.md`.
- Use the app name `Noted`.
- Use `docs/1.webp`, `docs/2.webp`, and `docs/3.webp` as design references.
- Use `docs/Logo.png` as the logo.
- Use subagents for core/Firebase, frontend/UI, and design system/QA where practical.

### Source Material Reviewed

- `docs/Noted_PRD_dan_Kerangka_Desain.md`
- `docs/1.webp`
- `docs/2.webp`
- `docs/3.webp`
- `docs/Logo.png`

### Key Requirements Extracted

- Flutter mobile app.
- Firebase Authentication.
- Cloud Firestore.
- Provider state management.
- MVVM structure.
- Screens: welcome, sign in, sign up, home/dashboard, notes list, add/edit note, note detail, favorites, profile.
- Features: active user display, CRUD notes, categories, favorites, search, profile, logout.

### Design Notes

- Minimal notes UI inspired by the references.
- Off-white canvas, compact search, rounded chips, colored note tiles, dark floating add button.
- Logo should be used on the welcome/auth experience.

### Environment Findings

- Workspace initially contained only the `docs/` folder.
- Workspace was not a git repository.
- `where.exe flutter` and `where.exe dart` did not find executables on `PATH`.
- `flutter --version` timed out during the initial environment check.
- Pub cache exists under `C:\Users\sangh\AppData\Local\Pub\Cache`, including Firebase-related packages and `flutterfire.bat`.
- PowerShell resolved Flutter at `C:\Users\sangh\flutter\bin\flutter.bat`.
- Removing stale `C:\Users\sangh\flutter\bin\cache\flutter.bat.lock` unblocked Flutter and Dart.

### Progress

- Created `AGENTS.md` for persistent project context.
- Created this implementation log for cross-session tracking.
- Added Flutter project metadata, app bootstrap, Firebase options placeholder, MVVM models, repositories, Provider viewmodels, reusable widgets, and the required app screens.
- Added Android project shell files for `com.noted.app`, including manifest, Gradle files, Kotlin `MainActivity`, launch background, and vector app icon.
- Core + Firebase Agent review:
  - Confirmed AuthRepository supports sign up, sign in, active user loading/fallback creation, and logout through Firebase Auth + Firestore `users`.
  - Confirmed NoteRepository supports Firestore note watch, add, update, delete, and favorite toggling in the `notes` collection.
  - Fixed NoteViewModel logout/null-user binding so stale search and category filters are cleared with note state.
  - Added a focused viewmodel test for clearing note filters when no user is bound.
  - Fixed owned analyzer const-constructor hints in AuthRepository.
- Frontend/UI Agent review:
  - Tightened note tiles, chips, stat cards, buttons, search field, dashboard loading state, note stream errors, add/edit favorite control, category bottom sheet, and profile initials.
  - Kept the screens aligned with the supplied note app references and PRD navigation.
- Design System + QA Agent review:
  - Confirmed `lib/utils/app_colors.dart` follows the PRD palette: off-white background `#F8F7F2`, sage primary `#6A9C89`, soft yellow secondary `#FFD66B`, dark text `#2F2F2F`, white cards, and soft red errors.
  - Tuned utility-level theme defaults for the reference screenshots: gray search/input fill, dark selected chips/navigation/FAB, pastel note colors, white bottom sheets/dialogs, readable text defaults, and accessible focus/error borders.
  - Kept edits inside `lib/utils/**`.

### Verification

- `C:\Users\sangh\flutter\bin\flutter.bat pub get` passed after allowing Flutter/Pub cache access.
- `C:\Users\sangh\flutter\bin\flutter.bat analyze` passed with no issues after all agent changes.
- `C:\Users\sangh\flutter\bin\flutter.bat test` passed with 2 tests and 0 failures after all agent changes.
- `C:\Users\sangh\flutter\bin\flutter.bat build apk` passed after stopping stale Gradle daemons.
- Release APK produced: `build\app\outputs\flutter-apk\app-release.apk` (49.3 MB).
- After Firebase configuration:
  - `C:\Users\sangh\flutter\bin\flutter.bat analyze` passed with no issues.
  - `C:\Users\sangh\flutter\bin\flutter.bat test` passed with 2 tests and 0 failures.
  - `C:\Users\sangh\flutter\bin\flutter.bat build apk` passed and rebuilt `build\app\outputs\flutter-apk\app-release.apk`.
  - Rebuilt APK size: 51,709,509 bytes.

### Design System + QA Status

- Environment:
  - Current Codex shell did not initially inherit Flutter from PATH: `where.exe flutter` returned `INFO: Could not find files for the given pattern(s).`
  - After reloading Machine/User PATH, PowerShell resolved Flutter at `C:\Users\sangh\flutter\bin\flutter.bat`.
  - `C:\Users\sangh\flutter\bin\flutter.bat --version` passed outside the sandbox: Flutter 3.41.6 stable, Dart 3.11.4.
- Commands run:
  - `C:\Users\sangh\flutter\bin\dart.bat format lib\utils` passed; formatted `lib\utils\app_theme.dart`.
  - `C:\Users\sangh\flutter\bin\flutter.bat pub get` passed.
  - `C:\Users\sangh\flutter\bin\flutter.bat analyze` passed with no issues after all changes.
  - `C:\Users\sangh\flutter\bin\flutter.bat test` passed: 2 tests, 0 failures.
  - `C:\Users\sangh\flutter\bin\flutter.bat build apk` passed after stopping stale Gradle daemons.
- APK artifact:
  - Built `build\app\outputs\flutter-apk\app-release.apk`.
  - Artifact size reported by Flutter: 49.3 MB.
- QA checklist:
  - PRD palette constants aligned: done.
  - Reference-inspired global component styling aligned: done.
  - Flutter formatting for owned utility files: done.
  - Unit tests: passed.
  - APK build artifact: produced.
  - Runtime Firestore database availability: checked; `(default)` database exists in `asia-southeast2`.
  - Runtime Firebase Auth provider testing: still requires verifying Email/Password sign-in is enabled in Firebase Authentication.

### Firebase Configuration

- Attempting to create project ID `noted` failed because Firebase project IDs must be at least 6 characters.
- Attempting to create a new longer project hit the account's Google Cloud project quota.
- Configured this app against the existing Firebase project `superheromood-54691`.
- Registered Android app:
  - Package: `com.noted.app`
  - App ID: `1:106507286538:android:df35eaf526f31c75abc7f3`
- Generated/updated:
  - `lib/firebase_options.dart`
  - `android/app/google-services.json`
- Removed placeholder non-Android Firebase options from `lib/firebase_options.dart`; Firebase is currently configured for Android only.
- Firestore check:
  - `(default)` database exists.
  - Location: `asia-southeast2`.
  - Mode: `FIRESTORE_NATIVE`.

### Next Steps

- Enable or verify Firebase Authentication Email/Password sign-in in the Firebase console before testing sign up/sign in.
- Firebase CLI project creation note:
  - `flutterfire configure` failed when creating project ID `noted`.
  - `firebase-debug.log` shows the root cause: `project_id must be at least 6 characters long`.
  - Retry with a longer globally unique project ID, for example `noted-app-sangh` or `noted-notes-2026`, while keeping the visible app name as `Noted`.
- Firebase Auth provider note:
  - Firebase CLI 15.19.0 lists Auth import/export commands, but no Email/Password provider enable command.
  - `gcloud` is not installed in this shell.
  - If sign up/sign in fails with provider-disabled errors, enable Email/Password in Firebase Console > Authentication > Sign-in method.

### App Name Correction

- Corrected visible app name from `Noted,` to `Noted`.
- Updated welcome page text, Material app title, Android launcher label, README, AGENTS context, and package description.
- Rebuilt release APK after the label change.

### Feature Upgrade: Connections, Sharing, Formatting, Theme

- Added email-based connection requests with pending, accepted, and rejected states.
- Added a Connections tab for adding users by email, accepting/rejecting requests, and viewing accepted connections.
- Added note sharing from Note Detail to accepted connections.
- Notes now support `sharedWithUserIds`, `ownerName`, and `ownerEmail` metadata.
- Notes list now watches both owned notes and notes shared with the active user.
- Added formatting controls in Add/Edit Note for bold, italic, underline, bullets, and numbering.
- Added Markdown-style rendering for formatted note content.
- Added light/dark mode toggle in Profile using `ThemeViewModel`.
- Added local `firestore.rules` and linked it from `firebase.json`; rules are not deployed automatically.
- Verification after feature upgrade:
  - `flutter test` passed: 6 tests, 0 failures.
  - `flutter analyze` passed with no issues.
  - `flutter build apk` passed and produced `build\app\outputs\flutter-apk\app-release.apk` (49.8 MB).

### Connection Request Crash Fix

- Fixed Flutter framework assertion shown when sending a connection request.
- Root cause: connection request submission could notify Provider while the Add Connection dialog route was still closing, and proxy-provider user binding also notified during provider update.
- Fix:
  - Dialog now returns the email first, closes, then sends the request from the page context.
  - `ConnectionViewModel.bindUser` and `NoteViewModel.bindUser` calls from proxy providers are deferred with `Future.microtask`.
- Verification:
  - `flutter test` passed: 6 tests, 0 failures.
  - `flutter analyze` passed with no issues.
  - `flutter build apk` passed and rebuilt `build\app\outputs\flutter-apk\app-release.apk` (49.8 MB).

### Connection Request Crash Fix Follow-up

- User still reproduced Flutter framework assertion `'_dependents.isEmpty': is not true` when sending an Add Connection request.
- Current Connections UI is an inline panel rather than a dialog, so the remaining likely lifecycle issue was Provider notifications during request submission and proxy-provider update.
- Changed connection provider binding:
  - `ConnectionViewModel.bindUser` now accepts `notifyOnBind`.
  - `ChangeNotifierProxyProvider` binds the auth user with `notifyOnBind: false` to avoid notifying dependents during provider update.
  - `ConnectionViewModel` now guards notifications after disposal.
- Changed connection request submission:
  - `sendRequest` no longer emits an eager global loading notification on success.
  - `ConnectionsPage` owns local send progress with `_isSendingRequest`.
  - Request dispatch waits for `WidgetsBinding.instance.endOfFrame` after focus/UI settling before reading the provider and calling Firestore.
- Added regression tests in `test/connection_viewmodel_test.dart` for send-request notification behavior and repository error reporting.
- Verification blocker in Codex shell:
  - `dart format lib\main.dart lib\views\connections_page.dart lib\viewmodels\connection_viewmodel.dart test\connection_viewmodel_test.dart` timed out after 5 minutes.
  - `flutter test` timed out after 2 minutes.
  - `dart --version`, `flutter --version`, direct `dart.bat --version`, direct `flutter.bat --version`, and analytics-disabled variants all timed out before output.
  - `Get-Command` confirmed `flutter.bat` and `dart.bat` resolve to `C:\Users\sangh\flutter\bin`.

### Connection, Dark Mode, and Editor Follow-up Verification

- Replaced the Add Connection dialog flow with an inline panel so request sending no longer depends on route/dialog teardown.
- Captured Provider and ScaffoldMessenger dependencies before async request dispatch to satisfy Flutter context lifecycle rules.
- Kept connection request progress local to `ConnectionsPage` through `_isSendingRequest`.
- Fixed dark-mode surfaces and contrast across shared widgets:
  - Dashboard stat cards now use theme surface, border, and text colors.
  - Home date strip now uses theme-aware visible text in dark mode.
  - Category chips, custom buttons, empty states, profile metrics, note detail chips, and category sheets now use theme colors instead of fixed light surfaces.
  - Note-card metadata/date chips use stronger contrast on pastel cards.
  - Notes search field now uses theme input fill/focus colors.
- Improved editor formatting behavior:
  - Bold, italic, and underline now act as tap-on/tap-off inline typing modes.
  - Bullet and numbering modes continue on new lines until toggled off.
  - Empty-editor bullet/numbering activation no longer throws a range error.
- Added `test/formatting_toolbar_test.dart` for toolbar-level formatting behavior.
- Verification:
  - Focused formatter test initially failed because formatter APIs for inline typing/list continuation were missing.
  - `flutter test test\feature_upgrade_test.dart` passed after formatter fixes.
  - `flutter test test\formatting_toolbar_test.dart` initially failed on empty-editor bullet activation, then passed after fixing line-range handling.
  - `flutter test` passed: 15 tests, 0 failures.
  - `flutter analyze` initially reported 3 issues, then passed with no issues after cleanup.
  - `flutter build apk` passed and produced `build\app\outputs\flutter-apk\app-release.apk` (49.8 MB).
  - A final extra `flutter test` rerun after the analyzer cleanup was attempted but blocked by Codex usage limits; no workaround was attempted.

### Share Flow Refactor and Remove Connection

- Deployed `firestore.rules` to Firebase (rules were previously only local, causing permission denied errors when testing).
- Refactored the Note Sharing logic to a "Copy-Paste" model:
  - Previously, accepting a shared note granted access to the original document, which prevented the receiver from editing it due to Firestore rules.
  - Now, accepting a shared note creates a brand-new, independent copy of the note owned by the receiver.
  - Simplified Firestore rules and `NoteRepository` queries since `sharedWithUserIds` is no longer needed.
- Added a "Remove Connection" feature:
  - Implemented `removeConnection` in `ConnectionRepository` and `ConnectionViewModel`.
  - Updated `firestore.rules` to allow connection deletion by involved users.
  - Added a remove button (trash icon) with a confirmation dialog to the accepted connections list in the UI.
- Verification:
  - Fixed `_FakeNoteRepository` and `_FakeConnectionRepository` to match the new behavior and signatures in the test suite.
  - `flutter test` passed: 17 tests, 0 failures.
  - `flutter analyze` passed with no issues.
  - `flutter build apk` passed and produced an updated release APK.

### Editor Inline Formatting Behavior Revert

- Changed Bold, Italic, and Underline back to one-shot formatting buttons.
- These buttons no longer stay active after tapping and no longer require a second tap to turn off.
- Bullets and numbering remain continuous modes and still continue on new lines until toggled off.
- Updated `test/formatting_toolbar_test.dart` to cover one-shot Bold behavior while keeping the continuous bullet test.
- Verification:
  - `flutter test test\formatting_toolbar_test.dart` first failed against the old toggle behavior, then passed after the toolbar update.
  - `flutter test` passed: 17 tests, 0 failures.
  - `flutter analyze` passed with no issues.
