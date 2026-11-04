# Issue #52 — completed isolated-staging verification

Completed: **2026-11-05, Asia/Jakarta**. The initial backend gate is resolved.
This report supplements, rather than replaces, the original failed-run evidence.

## Source, environment and artifact

- Implementation commit: `acd0785688a7df23185219728b4d76641a0d7b43`.
- App, test and backend source are unchanged from that tested implementation.
- Staging was a new local Supabase stack in WSL, project `noted-issue52-staging`,
  created from the committed functions and all **13 migrations**. Only three new
  synthetic accounts and synthetic `QA52` notes were used. No hosted project was
  deployed, reset or modified during this follow-up.
- Supabase CLI `3.0.0`; Docker Engine `29.1.3`; real PostgreSQL, Auth, Storage,
  Realtime and Edge Runtime services. No mocked backend or unrestricted endpoint.
- Both `avatars` and `note-media` buckets remained private. Existing note and
  Storage RLS policies were unchanged.
- The staged media helper matches the committed source after CRLF/LF normalization:
  SHA-256 `b9ad29160a080527cdbf0f8db3054ed887e8df354948d766c50674f8eb840a57`.
- Signed release APK: Noted **2.0.0 (3)**, `com.noted.app`, 64.4 MB.
- APK SHA-256: `08ECC2ECD3277348A37A381EB2B2D9EB84171B374D33775D5FBECB40D80F6D33`.
- Device: `Maestro_ANDROID_pixel_6_android-33`, `sdk_gphone64_x86_64`, Android 13,
  API 33, 1080×2400 / 420 dpi. The same installed APK hash was checked after resume.
- The APK used an ignored local staging configuration containing only the client
  URL and anonymous key, plus the existing approved upload signing setup. No
  server/service-role key, password, token or signed URL is committed here.

## Confirmed cause of the earlier media failure

Read-only download of the configured hosted `note-sharing` source confirmed that
its media helper lacked `inlineMediaPaths` and returned immediately when
`attachments` was empty. Its SHA-256 was
`D7F3ADF6038DD1FB7CC1C718C7E53AC64A4976B0916EDD4CE12B61BABCCC9E68`.
This explains why the original inline-only copies retained sender references.

Current main already contains the #51 fix. Running that exact backend source in
isolated staging resolved the failure without another product change or a production
deployment. Production rollout remains a separate activity; this verification does
not imply the hosted function or a store build was released.

## Automated checks against the final implementation

| Command | Actual result |
|---|---|
| `npm test` in `tools/migration` | **100 passed**, 0 failed |
| `flutter pub get` | Passed; lockfile unchanged |
| `flutter analyze` | **0 issues** (151.5 seconds) |
| `flutter test` | **197 passed**, including goldens (59 seconds) |
| Focused preview regression file | **19 passed**, 0 failed |
| `flutter build apk --release --dart-define-from-file=.env.supabase.json` | Passed against staging (284.9 seconds) |
| Source comparison with the implementation commit | No changes in `lib/`, `test/` or `supabase/` |

These checks ran on the immutable source used for the installed artifact. The final
PR-head CI results are recorded in the PR checks and final verification comment.
No golden baselines were changed. The prior read-only code review's navigation
findings were fixed and re-reviewed; no GitHub approval is implied by that review.

## Android and persisted-state results

Detailed redacted results are in [redacted-staging-results.json](redacted-staging-results.json).
Screenshots below use only synthetic content and the public Noted logo.

| Scenario | Observed outcome | Screenshots |
|---|---|---|
| Library preview with no Activity notification | Notification count 0. Full text, bold text, list and already-authorized private image rendered; Accept/Decline remained available. | `01`, `02` |
| Read, tap body and leave without deciding | Source content and owner unchanged; revision 0 before/after; invitation still pending; owned-copy count 0; no editor or owner actions. | `02` |
| Preview Accept and retries | Exactly one recipient-owned copy; source content/owner/revision unchanged; invitation removed; both later API retries rejected with 403; copy count remained 1. | `03`, `04`, redacted state |
| Independent inline-only private media | Copy URI uses recipient UID and copy note ID, not the source prefix. Recipient downloaded the private copied object (200); its SHA-256 matched source bytes. | `05`, redacted state |
| Remove source image after acceptance | Only the synthetic source image was deliberately deleted after confirming acceptance left it unchanged. The independent copy still downloaded (200), matched the original bytes and rendered on Android. | `05` |
| Direct-card Accept and repeated input | Real staging Edge Runtime was paused before tapping, holding the request deterministically. Please wait was visible and both decisions disabled. Repeated inputs were ignored. After resuming the runtime, exactly one independent copy existed and its image bytes matched. | `06` |
| Direct-card Decline | Invitation/card removed; no owned copy. | redacted state |
| Preview Decline | Returned to Library; invitation removed, no copy, source content unchanged. | `07` |
| Activity opening and dark layout | The copy notification opened the same read-only preview with full formatted text and decision controls, without owner actions. | `08` |
| Owner deletion after listing | Opening the stale card showed unavailable; recipient SELECT returned zero rows; no copy was created. | `09` |
| Owner deletion while open | Full text was visible before deletion. New recipient reads returned zero rows immediately. The preview cleared content and decisions on the polling fallback; observed at 33 seconds. No copy. | `10` |
| Invitation removed after listing | Existing `decline_note_share` RPC from a second recipient session removed authorization. Stale-card preview showed unavailable; zero readable source rows and zero copies. | `11` |
| Invitation removed while open | Full text was visible before removal. New recipient reads returned zero rows immediately; open content and decisions cleared on the polling fallback, observed at 33 seconds. No copy. | `12` |
| Loading and backend error | The local API gateway was stopped before opening. Loading semantics appeared, followed by the error and Retry. Source content and decisions were absent; no cached content fallback. | `13`, `14` |
| Retry after recovery | Restarted the local gateway and tapped Retry. Authorized text, private image and decisions returned; source revision stayed 0, invitation remained pending, no copy. | `15` |
| Real Android account switch | Recipient signed out and stranger signed in. Stranger Library had no recipient titles or invitations. | `16` |
| Stranger direct link | Unavailable screen; no source title, text or image. Server SELECT returned zero rows and media signing was denied (400). | `17` |
| Anonymous/stranger and pending edit denial | Live ordinary-session API probes returned zero source rows for anonymous/stranger access. Pending recipient commit RPC returned 403. Authorized view-member media signed successfully (200); stranger signing was denied (400). | redacted state |

`01`–`17` refer to PNG filename prefixes in this directory. Preview, Back, Accept copy,
Decline, Please wait, Loading shared note and Retry labels were observed through UI
Automator. Busy and repeated-input scheduling used a paused local service, not sleeps.
Deletion/removal observations waited for the actual unavailable UI state.

## Permission and delivery boundaries

Pending-only recipients can read note text but cannot sign private media under the
existing Storage policy. Their preview correctly shows Image unavailable (`03`).
A recipient who already has a live view role can read that media (`02`, `15`). Opening
preview grants no role and changes no permissions. The watcher retains its existing
Realtime plus 30-second polling fallback; already-issued signed URLs are not claimed
to become immediately invalid on the server.

The product fix remains limited to #52: Library Preview, the shared read-only opening
path, server-only preview authorization and the existing decision operations. The
follow-up added evidence only; no dependency upgrade, RLS change or deployment.

All acceptance gates that blocked the draft are now satisfied on actual staging and
Android. Merge still requires successful checks on the final PR head and compliance
with the repository's current review policy. The final merged SHA and issue reply
belong in the PR/issue, not a self-referential evidence commit.

## Cleanup

The test account was signed out; the light theme and emulator network delay were
restored. The temporary local stack was stopped with its explicit project ID and
its synthetic data volumes removed. Its task-owned WSL workspace and temporary
account/configuration files were removed. Docker was stopped/disabled after confirming
no other containers were running; installed developer tooling was retained. The
original approved `.env.supabase.json` link was restored without changing its target.

The staging APK is retained only under ignored `build/qa-issue52/staging-release.apk`.
The original checkout's unrelated changes and generated plugin registrant were not
staged or committed. No production deployment or store release was performed.
