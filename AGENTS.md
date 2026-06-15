# Noted Project Context

## Product Source Of Truth

- Primary requirements live in `docs/Noted_PRD_dan_Kerangka_Desain.md`.
- The app name is `Noted`, even though the PRD draft uses `StudyNote`.
- Design references are `docs/1.webp`, `docs/2.webp`, and `docs/3.webp`.
- Logo asset is `docs/Logo.png`.

## Build Goal

Build a Flutter mobile note-taking app for students with:

- Sign up, sign in, active user display, profile, and logout.
- Firebase Authentication for user accounts.
- Cloud Firestore for network database persistence.
- CRUD notes with title, content, category, favorite status, created date, and updated date.
- Search by title or content.
- Category filtering.
- Favorites page.
- Dashboard/home summary.
- MVVM architecture with Provider state management.

## Architecture Expectations

Use this structure unless a later requirement clearly supersedes it:

```text
lib/
  main.dart
  app.dart
  models/
  repositories/
  services/
  utils/
  viewmodels/
  views/
  widgets/
```

Keep responsibilities clear:

- `models/`: plain app data objects and Firestore mapping.
- `repositories/`: Firebase Authentication and Firestore access.
- `viewmodels/`: Provider-backed UI state and actions.
- `views/`: screens/pages.
- `widgets/`: reusable UI pieces.
- `utils/`: constants, routes, theme, validation helpers.

## Design Direction

The visual style should follow the reference screenshots:

- Minimal, soft academic notes app.
- Off-white background.
- Compact rounded search and category chips.
- Colored note tiles/cards in a staggered or grid-like notes layout where practical.
- Dark floating add button.
- Bottom-sheet style category and edit affordances.
- Calm typography, readable spacing, and simple navigation.

Use the PRD palette as a base:

- Background: `#F8F7F2`
- Primary: `#6A9C89`
- Secondary: `#FFD66B`
- Main text: `#2F2F2F`
- Card: `#FFFFFF`
- Delete/error: `#E57373`

## Agent Roles Requested

The user requested subagents for:

1. Core + Firebase Agent
2. Frontend/UI Agent
3. Design System + QA Agent

If subagents are used, keep file ownership disjoint where possible and do not revert another agent's changes.

## Current Environment Notes

- This workspace initially contained only `docs/`.
- The workspace was not a git repository when implementation started.
- `flutter` and `dart` were not available on `PATH` during initial setup checks.
- Verification may be limited until Flutter is configured in the active shell.

## Verification Expectations

Before claiming completion, run whatever is available in the current environment:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk`

If Flutter is unavailable, document that blocker in `docs/IMPLEMENTATION_LOG.md` with the exact command and failure.
