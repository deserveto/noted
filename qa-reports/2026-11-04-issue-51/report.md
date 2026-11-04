# Issue #51 verification — image placement and movement

Date: 2026-11-04  
Branch: `codex/issue-51-image-placement`  
Implementation commit: `fecfa1acabad934b25d2583ad6e097e4ea22e127`  
APK: `build/app/outputs/flutter-apk/app-release.apk` (64.4 MB, version `2.0.0 (3)`)  
Device: `Maestro_ANDROID_pixel_6_android-33` emulator, Android 13 (API 33), 1080×2400, 420 dpi  
Backend: authorized QA test account in the configured Supabase project; synthetic note only

## What changed

- New gallery images are uploaded to the private `note-media` bucket and inserted as
  `BlockEmbed.image` operations in the canonical Quill Delta at the cursor anchor.
- The anchor is tracked through local typing, selection changes and remote document
  replacements while the picker/upload is in flight.
- Inline images and legacy trailing image/doodle attachments expose an explicit,
  accessible **Move image** control. The user taps the destination and confirms
  **Move here**; the move is one atomic Quill change.
- Legacy image metadata is retained. Attachments whose private reference is already
  inline are hidden to prevent duplicate rendering; undo removes the embed and the
  trailing attachment becomes visible again.
- Share/duplicate copies every inline private reference once, rewrites the Delta and
  attachment metadata to the recipient's independent storage prefix, and rolls back
  copied blobs on failure.
- HTML export preserves inline private image references and attribute-escapes them.
- Undo snackbars use `SnackBar.persist: false`, so they still time out when TalkBack
  or VoiceOver enables accessible navigation.

## Server state observed

Note `cd04678513e2a9fb`, revision 6 after the move/doodle scenarios. The canonical
content was read through the authorized test account (RLS-scoped REST read):

```json
{"notedDocument":1,"ops":[
  {"insert":"Alpha first paragraph.\n\n"},
  {"insert":{"image":"noted-media://note-media/users/<qa-uid>/notes/cd04678513e2a9fb/1793766381149869_scaled_noted-before.png"}},
  {"insert":"Beta second paragraph.\n\n"},
  {"insert":{"image":"noted-media://note-media/users/<qa-uid>/notes/cd04678513e2a9fb/1793766705448410_doodle.png"}},
  {"insert":{"image":"noted-media://note-media/users/<qa-uid>/notes/cd04678513e2a9fb/1793766432311051_scaled_noted-after.png"}},
  {"insert":"Gamma third paragraph."},
  {"insert":{"image":"noted-media://note-media/users/<qa-uid>/notes/cd04678513e2a9fb/1793766511353891_scaled_noted-before.png"}},
  {"insert":"\n"}
]}
```

The `attachments` array still contains the moved doodle metadata, so no stored
media was deleted. No signed URL or public bucket URL was written to the note.

## Android scenarios

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 1 | Insert image before the first paragraph | PASS — image is the first Delta op and renders above Alpha | `01-insert-before-dark.png` |
| 2 | Insert image between Beta and Gamma | PASS — image sits after the Beta paragraph and before Gamma | `02-insert-between-dark.png` |
| 3 | Insert image after Gamma | PASS — image follows the final paragraph | `03-insert-after-dark.png` |
| 4 | Move an inline image from before Alpha to between Alpha and Beta | PASS — exact Delta order updated; text preserved; server revision advanced | `04-move-inline-dark.png` |
| 5 | Move a legacy trailing doodle into the document | PASS — trailing card has `Move drawing into note`; moved image is inline; metadata retained; no duplicate card | `05-legacy-trailing-dark.png`, `06-legacy-moved-dark.png` |
| 6 | Force-stop, relaunch and reopen | PASS — all image positions and text persisted; revision 6 | `06-reopen-after-restart-dark.png` |
| 7 | Light theme presentation | PASS — image controls and move banner use theme colors | `07-light-controls.png`, `08-light-move-banner.png`, `09-light-bottom.png` |
| 8 | Cancel the Android photo picker | PASS — no new Delta op, no upload, server revision unchanged at 6 | `10-canceled-picker-light.png` |
| 9 | Accessible controls | PASS — UI Automator reports `Move image`, `Move image into note`, `Move drawing into note`, `Move here`, `Cancel`, and live-region banner text | UI dump during scenarios |
| 10 | Undo snackbar lifetime | PASS — `persist: false`; snackbar dismissed automatically on device and in the widget regression test | widget test |

The three-image order is visible across `01`–`03`; the final content above is the
authoritative exact placement check.

## Automated checks (final tree)

| Command | Result |
|---|---|
| `npm test` in `tools/migration` | **100 passed**, 0 failed |
| `flutter pub get` | passed |
| `flutter analyze` | **0 issues** |
| `flutter test` | **178 passed**, 0 failed (includes goldens) |
| `flutter build apk --release --dart-define-from-file=.env.supabase.json` | passed, 64.4 MB APK |

Focused coverage added:

- `test/note_image_document_test.dart`: exact before/between/after Delta placement,
  atomic move + undo/redo, insertion anchor through local/remote edits, image source
  invalidation after deletion.
- `test/note_image_placement_test.dart`: picker/upload widget flow, cancel, upload
  error, save error, typing/remote edit during upload, route disposal cleanup,
  legacy attachment move, reopen, denied media, dark/light rendering order.
- `test/collaborative_document_test.dart`: inline image survives a concurrent remote
  text insertion.
- `test/document_codec_test.dart`: inline private image HTML export and attribute
  escaping.
- `supabase/tests/edge_functions.test.mjs`: inline-only media copied once, independent
  references, content rewritten, rollback path retained.
- `test/snackbar_dismissal_test.dart`: Undo snackbar dismisses with
  `accessibleNavigation: true`.

## Limitations / not claimed

- No drag-and-drop, paste or cut/paste image support is advertised.
- Upload-error, remote-edit, save-error and disposal races are proven with
  deterministic widget tests, not a physical device failure injection.
- Signed-URL expiry and revoked-access behavior are covered by the existing
  `MediaUrlResolver` and PGlite RLS suites; no second physical device or live
  collaborator was used.
- Export was exercised through the unit HTML test; the Android share sheet was not
  used to save an export file.
- No production deployment or store release was performed.
