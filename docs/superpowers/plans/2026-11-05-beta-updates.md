# Beta updates implementation plan

Goal: private, advisory Android APK updates with safe lifecycle prompts and repeatable verified publication.
Architecture: validated release model, lazy Supabase repository, installed-build/browser service, Provider viewmodel, route/lifecycle coordinator, themed dialogs and Settings history. Server-validated account sessions and service-only publication isolate release authority.
Spec: user beta update system request, 2026-11-05.

Decisions: open enrollment with private APK storage; beta channel explicitly supplied by NOTED_UPDATE_CHANNEL independently from backend environment; no forced updates; 24-hour reminders; six-hour foreground-check cooldown; 15-minute download grants; main-shell-only automatic prompts. No update telemetry. Never touch note persistence. Fresh installs establish an installed-build baseline; subsequent upgrades fetch exact-build notes asynchronously.

- [x] Backend: app_releases migration, private bucket, authenticated app-updates check/history/download, service-only final publication RPC. Tests: RLS, filtering, account authorization, unavailable objects, immutable identities.
- [x] Flutter: AppRelease model, UpdateRepository, UpdateService and UpdateViewModel. Tests: malformed data, integer builds, coalescing, cooldown/manual bypass, browser failures, installed baseline and upgrades.
- [x] Integration: Navigator observer plus AppLockGate visibility signal, foreground coordinator, safe root route only, Settings check/history. Tests: editor/modal/lock deferral, narrow light/dark UI.
- [x] Release tooling: inspect signed APK identity/certificate, immutable upload, draft validation, downloaded hash verification, final publication. Failure tests and operator/device documentation.
- [x] Verify: npm test, flutter pub get/analyze/test, configured signed release APK build; review diff and report external setup/device limitations.

Review focus: auth changes invalidate in-flight results; SDK/version failures stay quiet automatically; app backgrounding never bypasses lock; dismissals persist per account/channel/build; download attempts never imply installation; installed notes stay pending offline and never block startup.



2026-11-05 follow-up: the user authorized end-to-end setup and chose open enrollment for all signed-in accounts. Remove individual tester membership; retain authenticated metadata/download issuance and private storage. Release from current main, verify prior signed certificate continuity, deploy only the updater migration/function, publish after readback, and configure protected future manual release dispatch.
