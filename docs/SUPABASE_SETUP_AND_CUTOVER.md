# Noted — Supabase setup, cutover and release guide

The application uses Supabase Auth, PostgreSQL/RLS, Realtime, private Storage and five Edge Functions. Firebase files are historical reference and export inputs: do not deploy or modify the legacy Firebase project during this cutover.

## Current source and live deployment

As last verified on October 27, 2026, migrations 1–10 and all five functions are live. Migration `20261027000011_pr_review_concurrency.sql` and its updated AI/sharing functions were merged in [PR #50](https://github.com/deserveto/noted/pull/50), but have **not** been deployed in the last recorded environment state. It changes the AI RPC signature: apply migration 11 and deploy `noted-ai` and `note-sharing` as a coordinated release. AI calls fail closed if the old function runs against the new RPC during the deployment gap.

The combined UI/backend review is in [FULL_CHANGE_REVIEW.md](FULL_CHANGE_REVIEW.md); previous audit/remediation evidence is in [SUPABASE_REMEDIATION_REPORT.md](SUPABASE_REMEDIATION_REPORT.md). PR #50 is merged into `main`. The fully merged feature branches were subsequently removed after checking for unique commits and worktree/stash leftovers. Their source remains in Git history; branch deletion does not deploy the backend.

## 1. Public client configuration

Create ignored `.env.supabase.json` from `.env.supabase.example.json`:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<publishable-or-anon-key>",
  "NOTED_AUTH_REDIRECT_URL": "noted://app/auth-callback",
  "NOTED_FEEDBACK_EMAIL": ""
}
```

Never put a service-role key, SMTP password, database password or AI/email-provider secret in Flutter, Git or chat. Pass `--dart-define-from-file=.env.supabase.json` when running/building.

## 2. Authentication and email

Allow these Auth redirects:

- `noted://app/auth-callback`
- `noted://app/notes/**`

Gmail custom SMTP is configured on the linked project, with `smtp.gmail.com`, port 465 and sender name `Noted`. Email confirmation was still off at the latest read-only check. Saved SMTP settings do not prove password validity or delivery. Test password reset with an existing app account and check inbox/spam; then enable **Confirm email** before public rollout.

A free low-volume Auth setup can use a dedicated Gmail account with 2-Step Verification and a Google App Password. Enter its full address as SMTP username and sender, and its App Password directly in Supabase's SMTP settings. Do not paste it into chat. Gmail and Supabase rate limits apply. See [Supabase SMTP](https://supabase.com/docs/guides/auth/auth-smtp) and [Google App Passwords](https://support.google.com/mail/answer/185833?hl=en).

**Auth SMTP does not configure app activity emails.** Invitations, activity mail and recaps still use Resend. That sender remains a placeholder and its domain is unverified. Configure a verified Resend sender, or implement and test a separate provider adapter before promising those outbound emails to users. In-app activity remains available independently.

The repository's `supabase/config.toml` contains local development defaults, including confirmation off. Do not push it wholesale over reviewed production Auth/SMTP settings.

## 3. Schema and functions

From the repository root, for the reviewed target environment:

```powershell
npx supabase login
npx supabase link --project-ref <project-ref>
npx supabase db push --linked --dry-run
npx supabase db push --linked
```

There are **eleven versioned migrations** in the merged source: the original schema/RLS/storage schedules, audit corrections, guarded rollback, deletion claims, account write barriers, copy cleanup reservations/sweeps, atomic AI commits, the email queue cursor, and the PR-review concurrency correction. Never rewrite an already applied migration or reset the live database.

Functions validate user JWTs internally with `auth.getUser`; maintenance validates its cron secret. Deploy the matching sources:

```powershell
$projectRef = '<project-ref>'
foreach ($functionName in @('noted-ai','note-sharing','connections','account','scheduled-maintenance')) {
  npx supabase functions deploy $functionName --project-ref $projectRef --no-verify-jwt
  if ($LASTEXITCODE -ne 0) { throw "Deployment failed for $functionName" }
}
```

Verify matching migration history, ACTIVE functions, private buckets, denied anonymous requests and a controlled staging flow. An ACTIVE function or passing local mock test alone is not end-to-end production proof.

## 4. Server-only secrets

Populate ignored `supabase/.env` from its example with `AI_API_KEY`, `AI_BASE_URL`, `AI_MODEL`, `RESEND_API_KEY`, `NOTED_EMAIL_FROM`, `NOTED_APP_URL` and `CRON_SECRET`. Apply with:

```powershell
npx supabase secrets set --env-file supabase/.env --project-ref <project-ref>
```

Use a cryptographic generator for a new cron secret, for example in local PowerShell:

```powershell
$cronBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($cronBytes)
[Convert]::ToHexString($cronBytes)
```

Store the result privately; never paste it into chat or commit it. Preserve an existing project's secret unless intentionally rotating it alongside both scheduled jobs.

## 5. Scheduled jobs

The linked project already has active `noted-hourly-maintenance` (`0 * * * *`) and `noted-daily-trash-purge` (`0 3 * * *`) jobs. Read their status without displaying command text/secrets:

```sql
SELECT jobname, schedule, active
FROM cron.job
WHERE jobname IN ('noted-hourly-maintenance','noted-daily-trash-purge');
```

For a new project only, enable `pg_cron`/`pg_net` and call `public.configure_noted_schedules(project_url, cron_secret)` privately in the Dashboard SQL editor. Database job success only proves dispatch; inspect `pg_net` HTTP outcomes and actual function/delivery results separately. Do not trigger send-bearing jobs against real recipients without authorization.

## 6. Optional legacy import and guarded rollback

This rollout intentionally starts fresh and does not import Firebase test data. For a future import, use read-only Firebase credentials outside Git and follow [tools/migration/README.md](../tools/migration/README.md). Export reads the actual legacy schema, including `connectionRequests` and `users/{uid}/settings/preferences`. Preserve existing IDs and validate all transformed content, memberships, account states, citations and media checksums.

Firebase password hashes are not automatically portable. Confirmed status is retained only for verified source emails; disabled users remain banned. A source-unverified account that is already confirmed in the target cannot be safely unconfirmed through the Admin API and blocks for manual resolution. The disabled-account ban is finite (100 years), as documented in the tooling.

```powershell
Set-Location tools/migration
npm ci
node export_firebase.mjs --project <legacy-project-id> --service-account <private-json-path> --include-media --out ./exports/bundle
node import_supabase.mjs --bundle ./exports/bundle --dry-run
# Supply SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY privately for live commands.
node import_supabase.mjs --bundle ./exports/bundle
node validate_migration.mjs --bundle ./exports/bundle
```

Rollback is **database-only**, not full Auth/Storage erasure. For an empty target in an offline import window, explicitly opt in during import with `--seal-rollback`; the source-validated snapshot is checked under locks before sealing. Old unsealed ledgers, changed state and unexpected dependents block rollback. Auth users/profiles/settings and media are intentionally retained to avoid unrecorded cascade deletion. Full environment restoration needs a verified backup and a separately reviewed restore procedure.

```powershell
# Only when importing into an entirely empty, offline target:
node import_supabase.mjs --bundle ./exports/bundle --seal-rollback
node rollback_supabase.mjs --dry-run
node rollback_supabase.mjs --confirm-rollback
```

Never use these examples to clear the current live project or overwrite native user activity.

## 7. Android signing and final gates

Release builds read ignored `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) with no debug-signing fallback. Keep and back up the authorized upload keystore outside Git; do not generate a replacement for a published signing identity. This workstation's signing material is described in the remediation report. A new certificate cannot update an existing debug-signed installation in place; preserve local drafts before manual installation changes.

Run backend tests, `flutter pub get`, `flutter analyze`, `flutter test`, Deno entry-point checks and the configured signed release APK build. Device acceptance still covers two-phone concurrent edits, offline restart/reconnect, revoke/trash races, external cold-start auth/note links, microphone/camera and biometrics. Local goldens cover responsive light/dark layouts but do not replace those device checks.
