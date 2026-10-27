# Combined UI and Supabase PR review — October 27, 2026

## Scope and branch history

The review covers the complete tracked/untracked working tree against `11239a483fa3b5d3967a17df8d3273e54fa3d34d` (`main`). Both local feature branches originally pointed at that same commit; the UI work was not a separately committed ancestor. The reviewed result therefore belongs in one combined feature PR, from `feature/supabase-migration` to `main`.

The user authorized review, necessary corrections, commit and a PR for their review. Pushing the feature branch is necessary to create that PR. `main` must not be merged, pushed or have auto-merge enabled until the user approves the concrete PR.

## Review coverage

- Flutter screens/widgets, navigation, editor/autosave, AI, view models, account switching, offline/media integration, theme/tokens and responsive/golden coverage.
- Supabase repositories/services, schema/RLS/RPCs, five Edge Functions, auth/privacy, concurrency, cleanup, Android deep links and signing.
- Legacy export/import/validation/rollback, actual Firebase collection/document shapes, Auth status fidelity, retained historical source, documentation, licenses and commit inventory.
- Three separate reviewers used **Terra 6.1 High**; the coordinating review reproduced findings, inspected fixes and visually inspected representative rendered goldens.

The visual sample included [welcome/light](../test/goldens/welcome_390_light.png), [library/dark](../test/goldens/library_390_dark.png), [editor/light](../test/goldens/editor_390_light.png) and [settings/privacy/dark](../test/goldens/settings_360_dark_privacy.png). The bundled logo and DM Sans/Newsreader fonts/licenses are retained. Existing tests cover 360/390/430 light/dark layouts. This is not a pixel-equivalence claim against the prototype or a replacement for device acceptance.

## Findings corrected during this review

| Finding | Correction and regression proof |
|---|---|
| A slow account-A profile read can overwrite sign-out or account B | Session generations discard stale loads; identity changes clear old UI state. Delayed reads, profile updates, errors, sign-in, sign-out/deletion completion and replacement-session logout have targeted tests. |
| Deleting a new note while its create is pending leaves a saved note behind | Deletion waits for the in-flight save and deletes the resulting ID. Delayed-create widget regression reproduced the previous failure. |
| Home library shortcuts reset results while stale search text remains visible | Search revisions synchronize the controller and cancel pending debounce, including an already-empty view-model query. Widget regressions cover ordinary and immediate/debounced resets. |
| A slow Stop request can discard a newer AI answer | Cancellation invalidates the captured request immediately and cannot clear a subsequent generation. Delayed-cancel widget regression passes. |
| Duplicate can commit after membership revocation or source change | New locked duplicate RPC reauthorizes source membership, deletion state and revision before insertion; rejected copies clean up their blobs through existing durable reservations. SQL/handler regressions cover revoked/stale sources. |
| Clear history can be undone by an in-flight AI commit | Request cancellation, completion and history clearing serialize with exchange commit under shared account/request coordination. SQL tests cover clear-before-commit and completed-commit-then-clear. |
| Export reads `connection_requests`, omitting actual legacy `connectionRequests` | Export now reads the real collection; bundle filenames remain compatible. A faithful fake-export test asserts the requested path and preserved row. |
| Import confirms every email and re-enables disabled accounts | Import/checksums/parity preserve verification and disabled states. Source-disabled accounts are banned for 100 years. Confirmed-to-unverified target mismatches block manual resolution because the Admin API cannot unconfirm them. Dry-run remains write-free. |
| Setup docs mix historical smoke claims, stale SMTP status and unsafe rollback instructions | Setup guide now distinguishes source/live versions, Auth SMTP from Resend activity mail, guarded partial rollback and its opt-in seal, cryptographic secret generation, signing and release gates. |

The added regression tests were run red before their responsible fixes and green afterward. Source-only review cannot prove that no defects remain.

## Verification of the PR source

- `flutter pub get`: passed.
- Backend/migration suite: **89 passed**.
- Flutter unit/widget/golden suite: **115 passed**, including all original golden references.
- Deno checks: all five Edge Function entry points passed.
- `flutter analyze --no-pub`: **no issues**.
- Signed release APK with the configured Supabase environment: **built, 63.7 MB**; upload-certificate verification passed.

A candidate-file scan also checks known credential/private-key patterns and confirms local environment/signing files remain ignored; this is a bounded scan, not a guarantee against every possible secret format.

## Deployment and release boundary

- Existing live backend: migrations 1–10 and the previously deployed five functions.
- Proposed source: migration 11 plus the corresponding AI/sharing function updates. These review changes are not deployed while the user is reviewing the PR. Deploy migration 11 and the matching functions together after approval; the old AI RPC signature is removed, so mismatched versions temporarily fail closed.
- Gmail Auth SMTP is configured. The latest read-only check still shows email confirmation off; SMTP password validity and actual delivery are not proven by saved settings. Test delivery and enable confirmation before public rollout.
- Activity invitations/recaps still use Resend and its sender/domain remains unresolved. Gmail Auth SMTP does not replace that integration.
- Physical two-phone editing, offline/reconnect/revocation, microphone/camera/biometrics and cold-start external auth/note links remain acceptance checks.
- Legacy import is intentionally not executed for the fresh-data rollout. Guarded rollback is database-only and retains Auth/profile/settings/media; full environment restoration requires a reviewed backup procedure.
- Historical Firebase files are retained and are not deployed. Some differ from baseline because they were inherited working-tree work; do not describe them as byte-for-byte unchanged baseline artifacts.

No merge to `main`, release publication, test email, legacy Firebase write or deployment of migration 11 was performed during this PR preparation.
