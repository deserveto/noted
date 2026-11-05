# Issue 55 device verification

Date: 2026-11-05

## Build

- Branch: `codex/fix-55-connection-request-refresh`
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`
- APK size: 64.5 MB
- APK SHA-256:
  `80604158C9EC771525196BA2A14218C2F2F6FF5E1AF748B008040AF54C67CACE`
- Backend: configured Supabase Cloud test backend loaded from the ignored
  environment file.

## Devices

- Account A: Pixel 6 Google APIs emulator, Android 13 / API 33
  (`emulator-5554`).
- Account B: isolated Pixel 6 Google APIs emulator, Android 13 / API 33
  (`emulator-5556`).
- Both app instances were kept running and foregrounded during the primary
  notification journey.
- Account A was an existing synthetic QA identity. Account B was created
  solely for this verification. Credentials and exact account identifiers are
  intentionally omitted.

## Automated verification

| Check | Result |
| --- | --- |
| `npm test` in `tools/migration` | 100 passed, 0 failed |
| `flutter analyze --no-pub` | 0 issues |
| `flutter test --no-pub` | 236 passed, 0 failed |
| `flutter build apk --release --dart-define-from-file=.env.supabase.json` | Passed |

## Live workflow

### Activity notification to pending request

1. Kept both signed-in apps foregrounded.
2. Sent an invitation from Account A to Account B.
3. Verified Account B's unread Activity indicator.
4. Opened Activity, tapped the connection notification, and observed
   Connections without restarting or manually refreshing.
5. Confirmed the request section showed one request plus `Accept` and the
   user-specific `Decline` action
   were immediately visible.

Outcome: passed.

### Accept

1. Tapped `Accept` on Account B.
2. Confirmed the connected toast, accepted connection card, and removal of the
   pending request.
3. Confirmed Account A showed Account B under `Your connections` with no
   remaining `Sent requests`.

Outcome: passed on both accounts.

### Decline

1. Removed the accepted connection from Account B.
2. Sent a fresh request from Account B to Account A.
3. Opened the request from Account A's Activity notification.
4. Tapped `Decline`.
5. Confirmed the declined toast and removal of the incoming request on Account
   A, followed by removal of Account B's sent request.

Outcome: passed on both accounts.

### Missed-event recovery

1. Force-stopped Account A so its Realtime subscription could not receive the
   new request.
2. Sent a fresh request from Account B.
3. Reopened Account A and entered Connections directly, without using the
   Activity notification.
4. Confirmed the pending request and both decision controls appeared.

Outcome: passed.

### Refresh failure recovery

1. Enabled airplane mode on Account A.
2. Entered Connections and confirmed the visible `Retry` error state rather
   than an indefinite loading state.
3. Restored connectivity.
4. Confirmed the error cleared and the connection view recovered.

The automatic recovery completed before the Retry control needed a second tap.
Flutter tests separately cover explicit Retry, stream close, and failed-refresh
recovery.

## Notes

- No RLS, schema, Edge Function authorization, or storage policy was changed.
- Maestro used composed accessibility labels. Initial selector-only mismatches
  were corrected with stable point or regex selectors; no product failure was
  observed.
- No release or published APK was created for this fix.
