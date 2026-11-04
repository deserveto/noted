# Issue 53 Android acceptance evidence

Date: 2026-11-05

## Build identity

- App: Noted 2.0.0 (version code 3), signed release APK.
- Base commit: `712b85e9a1cb006fd55bca5fbacd3fe9c0bfe780`.
- Implementation commit: `3219897`.
- APK: `build/app/outputs/flutter-apk/app-release.apk` (64.5 MB).
- APK SHA-256: `17A4C00E40A1344AE2EC112202C32DB39CC9EF3F30CE5198474B8E79FBDDE84B`.
- Device: Android emulator `sdk_gphone64_x86_64`, Android 13 / API 33
  (`emulator-5554`).
- Backend: configured Supabase cloud test project using the existing synthetic
  QA account. No real user data was modified.

## Scenarios

- Opened Library and confirmed `All workspaces`, `Default`, and named-workspace
  choices are present with accessible button semantics.
- Selected an empty named workspace. The screen showed `0 notes`, zero scoped
  All/Favorites/Live counts, the workspace-specific empty state, and a
  `Show all workspaces` reset action.
- Assigned a synthetic note to a named workspace in the editor. The
  `Workspace updated` confirmation appeared and Library then showed that one
  note with `All 1`, `Favorites 0`, and `Live 0`.
- Entered a non-matching search while the named workspace was selected and
  confirmed the displayed count changed to zero.
- Selected Favorites with no scoped favorites and confirmed the scoped
  zero-result state.
- Changed sort to `Title A-Z` and confirmed the chosen sort remained active
  with the workspace filter.
- Renamed the selected workspace. Library updated the selector label without
  losing the assigned note.
- Deleted the selected workspace. Selection reset to `All workspaces`; selecting
  `Default` showed all six QA notes, including the formerly assigned note.
- Force-stopped and relaunched the signed release. `Default` selection was
  restored and all six cached/server notes rendered.
- Disabled emulator networking, force-stopped, and relaunched. Library showed
  cached assignments with the explicit message `Using saved workspace
  assignments. Showing saved workspace data.`, a `Retry` action, and six
  browsable cached notes.
- Reviewed the Library selector in light and dark themes. Labels, counts,
  buttons, empty state, and offline state remained readable.
- Restored networking and light theme, selected `All workspaces`, and removed
  the synthetic acceptance workspaces.

## Automated coverage for remaining matrix

- 1,001 assignment mappings loaded in three requests, proving the Library does
  not issue one request per note.
- All/Default/named/empty/reset, composed search/category/favorites/live/sort,
  assignment changes, rename, selected deletion, cache/restart, assignment-read
  failure, account-switch stale responses, and two-user shared-note
  organizational separation are covered by Flutter tests.
- Personal assignment RLS and Default-on-workspace-deletion semantics are
  covered by the PGlite SQL suite.

## Limitation

The physical journey used one Android emulator and one synthetic account. The
two-account shared-note case and account-switch races are automated/backend
verified but were not repeated on a second physical device. This evidence does
not represent a store release or production rollout.
