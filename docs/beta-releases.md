# Android beta releases outside Google Play

Noted's direct APK channel is an **open-enrollment beta**. Every signed-in Noted account, including a newly registered account, can read published compatible beta metadata and request a download. No individual enrollment or tester list is required. The dedicated `app-releases` Storage bucket remains private: anonymous users cannot request metadata or downloads, and the server validates every account's bearer token. The app never receives a service-role key and cannot publish releases. A client-supplied channel is a query parameter, not authorization.

Updates are advisory. There is no minimum supported build or forced-update gate. Update checks cannot clear notes, authentication, drafts, attachments, or the offline outbox. Latest available build and minimum supported build are deliberately separate concepts; any future minimum policy needs a separately reviewed offline-safe, reversible design.

## Initial operator setup

Review and deploy the versioned app-release migration and `app-updates` Edge Function through the normal approved Supabase deployment process. No deployment or real release is performed by adding this implementation. The function uses existing server-side Supabase credentials and independently validates the bearer token; it does not rely on the gateway's legacy JWT verification. Verify the private bucket and RLS in staging before production.

Account eligibility uses the existing Supabase Auth signup/sign-in flow. No `release_testers` table or onboarding administration is needed. Anyone able to create a Noted account can join this beta. Do not weaken the project's existing signup, email verification or abuse-prevention settings for distribution. Already-issued URLs remain usable for 15 minutes; signed-in distribution does not prevent recipients from copying the binary or link. In-app APK download issuance is open to registered users rather than publicly anonymous.

The initial updater-enabled `2.0.1` build `4` is also distributed as a **public bootstrap APK** through the repository's GitHub prerelease. Anyone can download that initial binary without an account, then install it and sign up. This is deliberately public distribution of that APK; it does not make Supabase release storage or any tester/account data public. Subsequent in-app updates use the authenticated download flow. Retain the bootstrap so new testers can join without operator enrollment.

The build channel uses `--dart-define=NOTED_UPDATE_CHANNEL=beta`, independently of `.env.supabase.json`. Only public Supabase configuration belongs in that JSON file. Service-role credentials belong in a protected operator environment or CI secret only. Never paste credentials into commands, shell history, Git, changelogs, crash reports, or chat.

Existing testers must **manually install one updater-enabled build** from a trusted operator delivery channel. Older builds cannot discover updates retroactively. The bootstrap build must have the same Android application ID and signing certificate as the installed app to support an in-place upgrade. Do not ask testers to uninstall as an update step.

## Signing continuity

The package remains `com.noted.app`. Existing Gradle configuration reads ignored `android/key.properties` and refuses a release build without it. Keep the established keystore, alias, and passwords backed up encrypted in at least two controlled locations. Test recovery of the key and certificate fingerprint. Do not generate a new key for each beta. Record the **signing certificate SHA-256**, not the APK hash, from an independently trusted previously distributed signed APK or controlled key record.

The release tool runs Android SDK `aapt dump badging` and `java -jar .../apksigner.jar verify --verbose --print-certs -Werr` against a temporary snapshot of the exact bytes it will upload. A concurrent build replacing the original APK cannot change the verified upload. The snapshot is removed after success or failure. It checks the application ID, explicit version/build, minimum SDK, all three supported APK ABIs (`armeabi-v7a`, `arm64-v8a`, `x86_64`), and one pinned release signing certificate. It rejects debug certificates, `REQUEST_INSTALL_PACKAGES`, and APKs with a maximum SDK limit. Version names use three numeric components with a total maximum of 40 characters. The first version supports the **universal APK**, not split APKs or signing-key rotation. APK minimum SDK must be at least 24; actual artifact metadata determines compatibility.

The beta project's global Storage limit also applies; the per-bucket limit cannot bypass it. The publisher defaults to a 50 MiB maximum APK size and rejects oversized files before SDK inspection or upload. `NOTED_MAX_APK_BYTES` may override that only after verifying the project's actual global limit; it must be a positive integer no larger than 512 MiB. The workflow defaults to 52,428,800 bytes. Android's supported `useLegacyPackaging` option compresses native libraries in the direct APK, keeping one universal APK below the current limit. Android extracts the libraries during installation, trading additional installed storage for a smaller download. Reevaluate this packaging choice for a future Play/App Bundle distribution.

Keep Android signing identity aligned with a future Google Play release. Play App Signing may use an app-signing key different from an upload key; a Play-signed app cannot necessarily replace a sideloaded APK with a different certificate. Decide enrollment/import of the existing app-signing key with the Play signing documentation and test both upgrade directions before switching distribution. Preserve package name, monotonically increasing version codes, and upgrade-compatible certificates. Do not rotate keys casually.

## Prepare and verify a release locally

Start from reviewed source. Assign a unique build number greater than **every reserved beta build**, including drafts and withdrawn releases. `2.0.0+3` was the pre-updater source version; `2.0.1+5` below is an example only. Version strings are display labels; Android and Noted compare integer builds. Never reuse a published path, build, or binary identity.

Run all required checks before building:

```powershell
npm ci --prefix tools/migration
npm test --prefix tools/migration
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=.env.supabase.json
```

For the intended beta release, explicitly set version and channel even when the source `pubspec.yaml` differs:

```powershell
flutter build apk --release --dart-define-from-file=.env.supabase.json --dart-define=NOTED_UPDATE_CHANNEL=beta --build-name 2.0.1 --build-number 5
```

Use Android SDK Build Tools and Java on `PATH`. Set `NOTED_SIGNING_CERT_SHA256` to the previously verified signing certificate fingerprint in the process environment; colon-separated and plain hex fingerprints are accepted. Do not obtain the pin from the very APK being approved. The Build Tools directory contains `aapt.exe` and `lib/apksigner.jar` on Windows. Choose an installed stable version:

```powershell
$betaBuildTools = 'C:/Users/your-user/AppData/Local/Android/Sdk/build-tools/36.0.0'
node tools/releases/release.mjs verify --apk build/app/outputs/flutter-apk/app-release.apk --version 2.0.1 --build 5 --build-tools $betaBuildTools
```

`verify` needs no Supabase administrator credentials and performs no network writes. It prints the validated version, build, minimum SDK, byte size, and APK SHA-256. Retain these values in the release record. The certificate pin and APK hash serve different purposes: Android verifies signing identity during installation; SHA-256 supports operator/readback verification. The app does **not** verify the binary downloaded by the external browser.

Copy `tools/releases/changelog.example.json` to a reviewed, release-specific JSON file. Use an array of 1–30 entries, each containing only `type` (`added`, `changed`, or `fixed`) and `text` (1–500 characters). Text is plain readable release notes, not HTML or Markdown:

```json
[
  { "type": "added", "text": "Check for beta updates from Settings." },
  { "type": "fixed", "text": "Describe the user-visible fix shipped in this binary." }
]
```

## Upload, verify, publish

Only an operator authorized to publish should run this command. Provision `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and the independently pinned `NOTED_SIGNING_CERT_SHA256` in a private process environment. The URL must be the trusted HTTPS project origin. Do not pass the service-role key as a command-line argument. This command changes the selected backend:

```powershell
node tools/releases/release.mjs publish --apk build/app/outputs/flutter-apk/app-release.apk --version 2.0.1 --build 5 --changelog tools/releases/2.0.1-build-5.json --build-tools $betaBuildTools
```

The tool follows this order:

1. Verify the local APK identity and pinned signature; calculate size and SHA-256.
2. Check build-number reservations and any existing draft.
3. Upload with `upsert: false` to `app-releases/android/beta/2.0.1/5/noted-2.0.1-build-5.apk`.
4. Create draft metadata, or accept an exactly matching existing draft without overwriting storage.
5. Download the stored private object and compare the full binary's size and SHA-256.
6. Call service-only `publish_app_release(p_release_id, p_size_bytes, p_sha256)` as the final step. The server checks draft identity, object availability/size and monotonic publication, then records verification/publication timestamps.

An upload, signature, draft mismatch, readback or checksum failure stops the flow before publication is requested. The tool never uploads with overwrite enabled and never stores signed URLs in release metadata. Its stdout deliberately excludes credentials, signed URLs and raw provider errors. A network interruption during the final RPC can leave the outcome uncertain: inspect the release state through the trusted console before retrying. Do not assume an error means the server rolled back a request it already committed.

An interrupted upload/insert may leave an orphaned object. Leave it for operator inspection and use a higher build if it cannot be resumed as an identical draft. A matching draft can be retried safely: the tool verifies readback again before publishing. Do not manually edit hashes to bypass verification. Published and withdrawn artifacts are retained indefinitely by the initial implementation's storage guards; do not delete them. Any future cleanup policy must preserve objects for at least the full issued-link lifetime plus an operational grace period (recommend 24 hours).

## Optional GitHub manual release dispatch

`.github/workflows/beta-release.yml` is separate from ordinary CI and runs only by explicit manual dispatch on `main`. It runs backend and Flutter checks, creates an ephemeral signing configuration, builds a universal APK with explicit beta/version/build, verifies/readbacks the artifact, then publishes. It does not deploy migrations or functions. The workflow has not been executed against a live backend as part of local implementation.

The `beta-release` GitHub Environment uses required owner review and main-only deployment restrictions. This repository currently has one maintainer, so self-approval is allowed; a different reviewer with self-approval disabled is preferable when another maintainer joins. Reviewers must verify the selected source commit, changelog and build identity before granting secrets. Repository write access and workflow edits are privileged; a protected environment alone is not a substitute for reviewed source.

Configure protected environment secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`, and `SUPABASE_SERVICE_ROLE_KEY`. Configure environment variables `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable client key), and `NOTED_SIGNING_CERT_SHA256` (independently trusted certificate pin). The signing keystore is the existing authorized key encoded for transport, not a newly generated replacement. Only the final publication step receives the service-role key. The workflow removes ephemeral signing files in an always-run cleanup step.

Commit a release-specific changelog under `tools/releases/`, then use **Actions → Publish Android beta → Run workflow** on `main`, supplying version, build, and the committed changelog path. Publication is never triggered by every push. Concurrent manual releases are serialized; server monotonic checks remain the final protection. Review the successful metadata and perform device acceptance before inviting more testers.

## Withdraw and correct

Withdraw a published release by its trusted UUID. This immediately removes it from discovery/history and prevents new download issuance:

```powershell
node tools/releases/release.mjs withdraw --release-id 00000000-0000-4000-8000-000000000002
```

Already-issued links may work for the remaining 15-minute validity; withdrawal does not uninstall an app or retract a downloaded APK. Keep the object. Withdrawal is one-way: publish a corrected binary at a **higher build number**, with a new immutable path and accurate changelog. Do not republish the old release or overwrite its binary. Roll back server behavior compatibly if needed while clients receive the corrective update.

## Tester experience and installation

Create an account or sign in to Noted. Settings shows the current version/build/channel, **Check for updates**, and **Release history**. Automatic checks are quiet on failure and wait for App Lock to unlock and a safe app screen; manual checks offer feedback and bypass reminder suppression. **Later** suppresses the same release's automatic reminder for 24 hours while Settings remains available. Automatic foreground checks use a six-hour cooldown (configurable on `UpdateViewModel`) and concurrent checks are coalesced. Automatic prompts wait for the main shell: editors, recording sheets, settings, note links, authentication recovery and other modals defer them. No update telemetry is collected.

Release history shows at most the latest 50 compatible published builds. Upgrade notes use a separate exact-installed-build history lookup before that limit. The first observed installed build establishes a local baseline; an increased installed build queues “What’s new” until authorized notes can be fetched and shown safely. Offline fetch failures leave the notes pending. Reminder and installation bookkeeping use separate `updates.*` preference keys; they never modify note caches or the pending-write outbox. These noncritical preferences are best effort, so clearing app preferences resets the reminder/baseline.

Without an explicit beta build channel, automatic discovery is disabled and manual checks explain the missing configuration. The client only opens HTTPS URLs on the configured Supabase project's exact host/port and signed `app-releases` storage path. Custom download/CDN hosts require a reviewed validation change. No signed URL is stored locally or sent to analytics.

**Update now** requests a fresh authorized HTTPS link and opens the external browser. Android may ask the tester to allow **Install unknown apps** for that browser (wording varies by Android version/vendor). Allow only the trusted browser, open the downloaded APK, and complete Android's installer prompts. Android checks signing compatibility. Noted does not install silently or request `REQUEST_INSTALL_PACKAGES`. A browser handoff is a download attempt, not proof of installation; only a higher installed build observed on a later launch confirms an upgrade. A fresh installation is not treated as a confirmed upgrade.

If a link expires, return to Noted and request **Update now** again for a new link. If the release has been withdrawn or the account session is invalid, it cannot issue a new link; contact the beta operator. Canceling the browser download or Android installer leaves the installed app unchanged. Do not uninstall to resolve a routine update failure; preserve local notes and pending offline writes and report the signing/error details to the operator without sharing signed links.

## Compatibility and device acceptance

Keep backend changes compatible with older beta clients: additive fields/RPCs first, retain old behavior during rollout, and avoid destructive migrations. An updater-enabled binary does not authorize clearing client caches or converting pending writes. Raise APK minimum SDK only deliberately; an incompatible device should continue using its installed build and offline notes. New clients reject malformed metadata; operators should keep the documented schema stable. Distribution is one Android beta channel, with a universal APK and a single certificate; additional channels/platforms/signing lineages need separate implementation and acceptance.

Physical-device installation and OS/browser behavior must be tested separately. Local Flutter/SQL tests cannot prove signing continuity, OEM installer behavior, or persistence across an actual replacement install. Record device/Android version, old/new build, and results:

- Install a higher, identically signed APK over the older app; verify Android offers an update and installed build changes.
- Keep login, local notes, unsynced draft content, attachments and pending offline writes; reconnect and verify the outbox replays without loss.
- Cancel midway through browser download and cancel at the Android installation confirmation; reopen Noted and verify the old build and data.
- Return from the browser without installing; verify no false installation confirmation and no repeated immediate prompt.
- Launch fully offline; unlock and read/edit local notes without waiting for update infrastructure.
- Let a 15-minute link expire, confirm the browser failure, then request a fresh link; withdraw the release and verify new issuance is denied.
- Lock during a pending check; verify no prompt appears above App Lock, then unlock and reach the main screen.
- Edit a note and record audio with a pending update; verify prompting waits until those routes/sheets close and content remains durable.
- Open password recovery or another modal during a check; verify the prompt waits until the sensitive flow ends.
- After a real upgrade, see “What’s new” once when safe; restart and verify it does not repeat. A fresh installation must not show an upgrade confirmation.
- Check the smallest supported phone in light/dark mode with large text; scroll long release notes and activate both actions with accessibility services.

Official references used for release tooling: [Android apksigner](https://developer.android.com/tools/apksigner), [Flutter Android release signing](https://docs.flutter.dev/deployment/android), and [Supabase private downloads](https://supabase.com/docs/guides/storage/serving/downloads). Current API guidance was retrieved through Context7 during implementation.
