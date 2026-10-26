# Noted Project Context

## Project Overview

Noted is a Flutter mobile note-taking app for personal and business use: capture notes, organize them by category, mark favorites, connect with colleagues and collaborators by email, and share note copies with accepted connections. Built with MVVM architecture and Provider state management, backed by Firebase Authentication and Cloud Firestore.

Verified environment: Flutter 3.41.6 (stable) / Dart 3.11.4 on Windows. `flutter` and `dart` are on `PATH`.

The repository is a git repo (remote: `https://github.com/deserveto/noted.git`, `main` branch).

## Current Features (verified in code)

- **Auth**: email/password sign up, sign in, logout; active-user display via `AuthViewModel` + `AuthRepository` (Firebase Auth).
- **Notes CRUD**: title, Markdown content, category, favorite flag, `createdAt`/`updatedAt`; persisted in Cloud Firestore via `NoteRepository`.
- **Markdown support**: bold/italic/underline/bullet/numbered formatting via `utils/markdown_formatter.dart` + `widgets/formatting_toolbar.dart` in the editor, rendered through `widgets/markdown_content.dart`.
- **Search**: by title or content (`NoteViewModel.searchQuery`).
- **Category filtering**: dynamic category chips derived from user notes (`widgets/category_chips.dart`).
- **Favorites**: pinned notes page + dashboard counts.
- **Dashboard/home summary**: note and favorite stats (`widgets/stat_card.dart`).
- **Connections**: send requests by email, accept/reject, incoming/outgoing pending lists (`ConnectionModel` with `pending/accepted/rejected` status).
- **Note sharing**: notes carry `sharedWithUserIds` / `pendingSharedWithUserIds` — sharing note copies with accepted connections.
- **Theme switching**: light/dark via `ThemeViewModel` and `ThemeMode` in `app.dart`; full dark palette in `AppColors`.
- **Navigation**: 5-destination bottom `NavigationBar` in `main_shell.dart`: Home, Notes, Favorites, Connections, Profile (keep-all `IndexedStack`).

## Architecture

Actual `lib/` structure (follow it; keep responsibilities clear):

```text
lib/
  main.dart          # Firebase init + MultiProvider wiring (viewmodels bound to auth user)
  app.dart           # MaterialApp, named routes, AuthGate
  firebase_options.dart
  models/            # plain data + Firestore mapping: note_model, user_model, connection_model
  repositories/      # Firestore/Firebase Auth access: auth_repository, note_repository, connection_repository
  services/
  utils/             # app_colors, app_theme, app_routes, validators, markdown_formatter
  viewmodels/        # Provider ChangeNotifiers: auth, note, connection, theme
  views/             # screens: welcome, sign_in/up, main_shell, home, notes, favorites, connections, profile, add_edit_note, note_detail
  widgets/           # note_card, category_chips, markdown_content, formatting_toolbar, custom_button/text_field, empty_state, stat_card
```

Key patterns:

- `main.dart` wires `ChangeNotifierProxyProvider`s so `NoteViewModel`/`ConnectionViewModel` rebind to the current auth user.
- Routes are named constants in `utils/app_routes.dart`; `AuthGate` in `app.dart` decides Welcome vs. MainShell.
- Repositories construct viewmodels directly (no DI container). Don't introduce heavyweight frameworks.
- Colors live in `utils/app_colors.dart` as `const`s; both light and dark palettes are defined there.

## Design Direction

- Minimal, soft academic notes app: off-white background, compact rounded search field and category chips, colored note cards, dark floating circular add button, bottom-sheet category/edit affordances, calm Roboto typography.
- Base palette: Background `#F8F7F2`, Primary `#6A9C89`, Secondary `#FFD66B`, Text `#2F2F2F`, Card `#FFFFFF`, Error/Delete `#E57373`
- Note card colors are cycled from `AppColors.noteColors` / `darkNoteColors` per note index via `noteColorFor(Brightness, int)`.
- Keep light/dark in sync: any color change needs both variants.
- Detailed design tokens and further guidelines live in `DESIGN.md` at the repo root — consult it before UI work.

## Stale or Removed References

- `docs/` now contains **only `docs/Logo.png`** (referenced by `pubspec.yaml` and `README.md`). The PRD, design-reference screenshots, `superpowers/`, and `IMPLEMENTATION_LOG.md` were **deleted** — do not cite them or expect them to exist.
- The app is branded for **personal and business usage** (not student-only). Keep this framing when writing copy, examples, or new screens.

## Verification Expectations

Flutter toolchain is available. Before claiming completion, run from the repo root:

- `flutter pub get`
- `flutter analyze` — must be clean (verified 2026-10-26: 0 issues)
- `flutter test` — tests live in `test/` (note_model, connection_viewmodel, formatting_toolbar, feature_upgrade tests)
- `flutter build apk` for full build verification, if appropriate

Report exact commands and failures if any step fails.
