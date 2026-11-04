# Issue #52 — initial pending shared-note preview evidence

Date: 2026-11-04 (Asia/Jakarta). **Historical initial run.** The media-copy gate below was subsequently resolved on isolated staging; see [completed follow-up verification](staging/report.md), completed 2026-11-05.

## Source and artifact

- Implementation: `acd0785688a7df23185219728b4d76641a0d7b43`.
- Branch: `codex/issue-52-pending-preview`, based on current `origin/main` at
  `e85cd258d13fed4327a5bc2325514d9f5cc383c8` (earlier issues #54 and #51 merged).
- APK: Noted `2.0.0 (3)`, release, `com.noted.app`, 64.4 MB.
- APK SHA-256: `9CE804ED4D0209F1CB0735CBC06223D283BF6675F5358502CB959D366FF25FF3`.
- Built with the approved existing ignored Supabase configuration and upload
  signing material through local links. No configuration or signing files committed.
- Installed with `adb install -r` on `Maestro_ANDROID_pixel_6_android-33`,
  `sdk_gphone64_x86_64`, Android 13 / API 33, 1080×2400 / 420 dpi.
- The tested Dart files are identical to the implementation commit. The subsequent
  evidence commit changes only this report, redacted state and screenshots.

## Confirmed root cause and scope

The live issue was open with no comments. All four attached screenshots were
inspected. Current main still had only Decline and Accept copy on `_PendingCopy`.
Activity fetched the authorized note and opened the editor surface, including
irrelevant owner actions for pending recipients. The November 4 investigation was
used as a lead, then checked against current main.

Library now offers Preview, preserving its direct decisions. Both entry points use
`openNote` to select a dedicated read-only route for pending recipients. That route
re-fetches through the existing authorized repository, uses a server-only watcher,
rejects cached/outbox fallback, hides content on errors or lost invitation access,
and rechecks on resume. It renders the original Quill document and existing private
media widgets without editor, save, formatting, image movement or owner controls.
Accept/Decline share the existing ViewModel/repository operations, serialize repeated
input while busy, show errors inline and refresh Library after success.

No migrations, RLS changes, dependencies, Edge Functions or production deployments
are part of this patch. Authentication is checked again after asynchronous reads.
Route selection remains fixed across account changes, and a late action response
cannot pop the Library after the user has left the preview.

## Actual automated results

| Check | Result |
|---|---|
| `npm test` in `tools/migration` | 100 passed, 0 failed |
| `flutter pub get` | Passed; lockfile unchanged |
| `flutter analyze` | 0 issues |
| `flutter test` | 197 passed, 0 failed, including existing goldens |
| `flutter test --no-pub test/shared_note_preview_test.dart` | 19 passed, 0 failed |
| `flutter build apk --release --dart-define-from-file=.env.supabase.json` | Passed; final build 152.4 seconds |
| `git diff --check` | Passed |

The first regression failed on main because zero Preview controls existed. A later
controlled action/Back regression failed because the underlying Library route was
popped; it passes with the route-currentness guard. Focused coverage also exercises
real repository/VM/navigation/Quill behavior through a controlled HTTP boundary:
formatting and no mutations on read/leave; both decisions on card and preview;
repeated taps while an action future is held; action failure/retry; deletion and
revocation before/during preview; network failure without cache revival; account
switch while a response is held; Activity route rebuilding after account switch;
lifecycle resume; media-signing completion after revocation; light/dark semantics
and 360px layout. Scheduling races use explicit completers and the fake clock.

A read-only code review identified the two navigation races above. Both were fixed,
regression-tested and re-reviewed with no remaining important findings. This is not
a submitted GitHub approval. No main branch protection/rules requiring reviews were
reported by GitHub's branch-protection and branch-rules APIs at inspection time.

## Android and live server evidence

Only dedicated QA accounts and newly created synthetic `QA52` notes were changed.
Private image fixtures use the app's public logo, not user media. Screenshots contain
synthetic content only. Server probes used ordinary authenticated sessions/RLS, not
a service-role bypass. No real users' notes were modified.

| Scenario | Observed result | Evidence |
|---|---|---|
| Library preview without notification | Deleted only the synthetic note's notification first; server count 0. Preview opened from Library with full text, bold text and bullet list. | `01`, `02` |
| Open, read, tap body, leave | Source content and owner unchanged; revision 0 before/after; invitation still pending; owned-copy count 0. No editor/owner actions or keyboard editing path. | `02`, redacted server state |
| Preview Accept, repeated input and retries | Exactly one recipient-owned copy; canonical content/ownership unchanged; pending invitation removed. Two later API retries returned 403; copy count stayed 1. **Inline-media independence failed; see gate below.** | redacted server state |
| Preview Decline | Invitation removed, zero copies, canonical content unchanged; returned to Library. | `03` |
| Direct card Accept/Decline | Both worked and refreshed Library. Accept produced one owned copy; Decline produced no copy. The same inline-media issue affected direct Accept. | `01`, redacted server state |
| Invitation removal after listing | A second recipient session called the existing `decline_note_share` RPC after listing. Opening the stale card showed unavailable; recipient SELECT returned zero rows. | `04` |
| Invitation removal while open | Requeued the synthetic invitation, opened it, then removed it from the second session. The open preview cleared content and decisions; a subsequent recipient SELECT returned zero rows. | `05` |
| Owner soft-delete after listing | Stale card opened unavailable; recipient SELECT returned zero rows, no copy created. | `10` |
| Owner soft-delete while open | Full text was visible before deletion. The open preview became unavailable; zero readable source rows and zero copies at the later observation (35 seconds after deletion). | `11` |
| Activity opening and authorized private image | A pending recipient who also already had a view role opened the copy notification into the same read-only preview. Private image, formatted text and final paragraph rendered. | `06`, `09` |
| Offline loading/error/retry | Emulator Wi-Fi/data disabled before opening; semantics exposed `Loading shared note`, then error and Retry, with no content. Reconnect + Retry restored authorized content; revision remained 0, still pending, no owned copy. | `08`, `09`, `12` |
| Accessibility and themes | UI Automator exposed Preview, Back, Accept copy, Decline, Loading shared note and Retry labels; full document text was readable through semantics. Light and dark layouts inspected with persistent decisions. | `01`–`12`, focused semantics tests |
| Stranger / anonymous / pending edit attempts | Anonymous and stranger SELECTs returned zero source rows. Pending recipient PATCH affected zero rows; `commit_note_revision` returned 403 / `42501`. Canonical title/content/revision stayed unchanged. | live RLS probes |

Numbers above refer to the screenshot filename prefixes in this directory.
Invitation-removal testing exercises loss of pending authorization using the existing
recipient RPC; it does not claim a new owner-side revoke control. The existing watcher
uses Realtime plus a 30-second polling fallback. These checks do not promise immediate
server invalidation of signed URLs that were already issued.

### Existing private-media policy

Storage RLS uses `is_note_member`, which permits owners and active live members,
not pending-only recipients. Live signing requests confirmed:

- pending-only recipient: HTTP 400 / Object not found;
- stranger: HTTP 400 / Object not found;
- pending recipient with an existing view role: HTTP 200 and image rendered.

The preview respects this boundary: pending-only media shows Image unavailable,
while already-authorized media renders. No view/edit membership is granted by opening
preview, and no Storage or note RLS policy was broadened.

## Initial blocking acceptance gate — resolved by the follow-up

The configured backend accepted two inline-only synthetic notes but retained each
sender/source-note private image URI inside the recipient's content. Neither copy
contained a rewritten URI under its own note ID. Copy ownership and exactly-once
creation passed, but **independent private media did not**. This happened through both
the unchanged direct-card action and the new preview action.

Current main already passes canonical content to `copyAttachmentsForNote` and rewrites
inline-only media; its backend regression tests pass. The running backend's behavior
therefore appears inconsistent with current main (the earlier #51 fix), but its exact
deployed version was not established. No backend deployment was performed to hide or
bypass the failure. `redacted-server-state.json` records the actual persisted mismatch
without content, account IDs, tokens or signed URLs.

Initial next action (now completed in the follow-up): provide an authorized staging backend running the current
`note-sharing` implementation (including #51), build against its approved local
configuration, and repeat the Android inline-only Accept/direct-card/retry scenarios.
Confirm exactly one independently owned copy **and** independently copied private media,
then rerun affected checks/CI against the final PR head. A successful local mock suite
or APK build does not resolve this gate. No Docker or Supabase CLI executable was on
PATH for constructing a replacement local environment in this session.

At the time of this initial run, the PR was kept draft and #52 open until that gate and required CI/reviews were
satisfied. This initial evidence alone did not authorize success or closure. See the follow-up report for the completed staging verification and current delivery gates.

## Cleanup and preserved work

The separate deletion-fixture sender account and its notes were deleted through the
existing authenticated account endpoint; its temporary local credential file was
removed. QA device network access was re-enabled and its original light theme restored.
Synthetic first-sender fixtures/copies remain for backend investigation. The original
checkout's pre-existing changes were preserved; the generated plugin registrant was
not staged. No goldens were updated.
