# Issue #54: delete/Undo ordering verification

Date: 2026-11-04. Branch: `codex/issue-54-delete-undo-ordering`, based on
`d519f53c0cc2e3fb3a69f451bfb93923c62ee5c1`. Scope: issue #54 only.

## Root cause and behavior

The previous online delete did not remove the note from the durable active
cache. A cached stream emission could therefore retain the deleted card/count
while an authoritative refresh was slow or unavailable. Online restore also
bypassed earlier queued writes: an older offline delete could replay after
Undo and delete the restored note again. Neither path checked zero-row writes.

Delete and restore now use the same durable ordered path, carrying the note
snapshot and updating active/trash projections before requesting local refresh.
Restore remains after earlier delete replay. Replayed writes verify an affected
authorized row; definitive failures surface while recovery data remains queued.
Account-keyed storage and authenticated replay checks remain in place. No schema,
RLS, media, Quill encoding, UI labels, dependencies, or Provider ownership changed.

Initial cached subscription emission is not duplicated by the optimistic refresh;
the existing revoked-note regression test remains unchanged and passes.

## Widget-runner investigation

No production change was made to work around the runner stall.

- Three old issue-worktree tester processes had absent parents and were stopped
  individually. New diagnostic runs used expanded output and explicit stages.
- Initial render, bounded frame pumps, delete completion, and deleted-card/count
  assertions completed. The next stall was awaiting the trash stream's `.first`.
- Bounded fake-clock pumps did not complete that await. `tester.runAsync` did;
  restore and its assertions then completed, exposing pending SDK timers at the
  binding's end-of-body invariant check.
- With socket subscriptions disabled in the test, an additional stage trace
  reached `vm.dispose()` and stalled in `client.dispose()`. Supabase starts its
  JSON worker isolate from the client constructor. Creating the client in real
  async time, using real async for stream-first reads/disposal, and disposing
  before binding invariant checks resolved the stall. The final widget test
  completed in 2 seconds.
- Diagnostic tester CPU stayed at only a few CPU-seconds with approximately
  250–275 MB working sets despite the waits. This was not a minutes-long compile
  or evidence of a repository serialization deadlock. Socket retries/timers were
  also inappropriate for a mocked HTTP-only widget test; its silent channel
  explicitly tests local refresh independently of server push.

Temporary probe logging was removed. The committed widget test uses the real
NotesPage, NoteViewModel, NoteRepository and offline store with mock transport;
it does not replace the repository or introduce production delays/reloads.

## Automated verification

| Gate | Result |
| --- | --- |
| `npm ci`, then `npm test` in `tools/migration` | 99 passed |
| `flutter pub get` | Passed; lockfile/dependencies unchanged |
| Focused delete/restore, Library widget, offline reliability tests | 20 passed |
| `flutter analyze --no-pub` | No issues (167.8 seconds) |
| `flutter test --no-pub --reporter expanded` | 162 passed, including goldens |
| `flutter build apk --release --dart-define-from-file=<approved-local-config>` | Passed; 64.2 MB APK |
| `git diff --check` | Passed |

The first npm attempt lacked worktree-local installed packages; `npm ci` resolved
that. The first release attempt lacked ignored worktree signing configuration;
the existing approved local signing configuration was reused without modifying
tracked build files or committing secrets. The final release build includes the
initial-emission regression fix.

APK SHA-256:
`3A432687C7F96E4832CE3F24104C50DAD5319374F32E1B717B6FDD07AB183B7F`.

Repository regressions cover online delete/Undo, offline delete then online Undo,
in-flight replay, delayed acknowledgements, rapid alternating intents, slow/failed
refresh, zero-row failure, failed restore recovery, queued edits before deletion,
unrelated-note preservation, account switching, and replay/repository recreation.
The original implementation's 6/9 failing reproduction was recorded in the
preceding investigation; the current normal suite contains positive regressions,
not assertions that preserve the bug.

## Installed-device acceptance

Device: `emulator-5554`, Pixel 6 Android 13 / API 33 AVD
(`sdk_gphone64_x86_64`). Installed the final signed release APK using
`adb install -r`; installation succeeded. Existing authenticated local QA session
was reused; no credentials were extracted or added to the repository.

Only a newly created synthetic Personal-category note was mutated. It has an
empty title displayed as **Untitled** and body **Issue54 QA synthetic body**.
Four original active notes were left unchanged.

| Scenario | Observed result |
| --- | --- |
| Notes → All → synthetic note → More actions → Delete note → confirm | Deleted snackbar/Undo verified through UI hierarchy; only synthetic card absent; header and visible count 5 → 4 |
| Tap Undo | Same synthetic Untitled card returns once; count 4 → 5 |
| Force-stop and relaunch, return to Notes, reopen restored note | Same card/count remain; body visibly intact in the Quill editor |
| Disable Wi-Fi and mobile data, delete; re-enable both before Undo | Offline delete removes card/count; Undo restores same card/count |
| Reconnect and force-stop/relaunch after offline cycle | Restored card remains exactly once, count 5; no reversed deletion |
| Repeat with Title A–Z sorting | Delete/Undo card/count assertions pass again; another force-stop/relaunch retains restored card |
| Cleanup | Only the synthetic fixture moved to trash; original active count returned to 4 |

No second-account device sign-in or live-server RLS penetration test was
performed; account/RLS coverage is from the automated repository/backend suites.
No direct production database inspection is claimed. Device assertions use UI
hierarchy/card identity, navigation, connectivity changes and fresh app launches.

## Redacted evidence

Unrelated note cards and user-defined category names are masked. Only the
synthetic note is exposed. Screenshots are supporting evidence; the transient
Deleted snackbar was asserted from the UI hierarchy before Undo, not claimed to
be visible in every screenshot.

- [Online deletion: count 4](online-deleted.png)
- [Online Undo: synthetic card and count 5](online-restored.png)
- [Reopened note after restart: body preserved](reopened-after-restart.png)
- [Offline deletion: count 4](offline-deleted.png)
- [Undo after re-enabling networking: count 5](offline-restored.png)
- [Offline cycle after restart: synthetic card/count retained](offline-restarted.png)
