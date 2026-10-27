# Noted backend

**Supabase Auth · PostgreSQL/RLS · Realtime · private Storage · Edge Functions**

This is the active backend for [Noted](../README.md). Start with the [setup, cutover, and release guide](../docs/SUPABASE_SETUP_AND_CUTOVER.md) to provision an environment; this page explains the parts you will deploy and verify.

## Backend map

| Component | Responsibility | Source |
|---|---|---|
| Auth | Sessions, account identity, password recovery | [Flutter auth repository](../lib/repositories/auth_repository.dart) |
| PostgreSQL | Notes, roles, profiles, preferences, activity, AI provenance | [Versioned migrations](migrations/) |
| RLS and RPCs | Per-account access and atomic authorization/concurrency checks | [Migrations](migrations/) · [SQL tests](tests/rls_and_rpcs.test.mjs) |
| Realtime | Note updates and expiring collaboration presence | [Collaboration service](../lib/services/collaboration_service.dart) |
| Private Storage | `note-media` and `avatars`, signed URLs, independent copies | [Media resolver](../lib/services/media_url_resolver.dart) |
| Edge Functions | Privileged operations and external provider requests | [functions/](functions/) |
| Scheduled maintenance | Trash purge, queued mail, cleanup, weekly recaps | [Maintenance handler](functions/scheduled-maintenance/handler.ts) |

## Five Edge Functions

| Function | Purpose | Authorization |
|---|---|---|
| [`noted-ai`](functions/noted-ai/) | Scoped note retrieval, AI requests, validated sources, chat history, cancellation and feedback | User JWT, revalidated note access |
| [`note-sharing`](functions/note-sharing/) | Invitations, membership changes, independent copies and private media duplication | User JWT and operation-specific access checks |
| [`connections`](functions/connections/) | Email lookup/privacy checks, connection requests and responses | User JWT and connection/privacy rules |
| [`account`](functions/account/) | Account export and deletion with media cleanup | User JWT; password verification for deletion |
| [`scheduled-maintenance`](functions/scheduled-maintenance/) | Claimed trash purge, queued mail/recaps, abandoned-copy cleanup | Server-only cron secret |

Gateway JWT verification is disabled in `config.toml`. User-facing handlers validate sessions internally with `auth.getUser`; maintenance validates its cron secret. Preserve those checks when changing deployment configuration.

## Configuration belongs at the right boundary

| Configuration | Location | Used by |
|---|---|---|
| Project URL, public client key, redirect URL | Ignored root `.env.supabase.json` | Flutter build/run |
| AI adapter/model/key, Resend sender/key, app URL, cron secret | Ignored `supabase/.env` → Edge secrets | Edge Functions |
| Custom SMTP and confirmation policy | Supabase Auth settings | Auth emails |
| Upload keystore and passwords | Outside Git; ignored `android/key.properties` references the key | Android release signing |

Auth SMTP and Resend app mail are separate integrations. AI uses an OpenAI-compatible adapter, defaulting to OpenRouter's `openrouter/free`; provider limits and availability still apply. Never put service-role credentials in Flutter or commit environment values.

## Migration discipline

There are **11 versioned migrations** in the merged source. Preview pending changes with `npx supabase db push --linked --dry-run` before applying them, and keep applied migration files immutable. Do not reset a live database to reproduce a local setup.

**Deployment follow-up:** migration `20261027000011_pr_review_concurrency.sql` and its matching `noted-ai` / `note-sharing` updates remain pending in the last recorded live environment. Deploy them together: the revised AI commit RPC removes the old signature, so mismatched versions fail closed during the gap. A Git merge is not a backend deployment.

`config.toml` describes local defaults, including email confirmation off. It is not a reason to overwrite reviewed production Auth or SMTP settings. The [operational guide](../docs/SUPABASE_SETUP_AND_CUTOVER.md#3-schema-and-functions) contains the deployment sequence, secrets, schedules, and acceptance checks.

## Verify before rollout

From the repository root:

```powershell
Set-Location tools/migration
npm ci
npm test
Set-Location ../..

deno check supabase/functions/account/index.ts supabase/functions/connections/index.ts supabase/functions/note-sharing/index.ts supabase/functions/noted-ai/index.ts supabase/functions/scheduled-maintenance/index.ts
```

The full backend suite currently has **89 tests** across SQL/RLS, controlled Edge handler fixtures, concurrency, cleanup, and migration tooling. PGlite supplies the local PostgreSQL test environment; no production credentials are required. This suite does not spin up or prove a full hosted Supabase project.

On staging/devices, verify signed-in and anonymous access, owner/editor/viewer/revoked access, private media, concurrent edits, offline replay, account deletion, external auth/note links, and actual email delivery. Scheduled-job dispatch alone does not prove the downstream HTTP operation succeeded.

## Further reading

- [Setup, deployment, email, schedules, and signing](../docs/SUPABASE_SETUP_AND_CUTOVER.md)
- [Combined review: fixes, evidence, and remaining gates](../docs/FULL_CHANGE_REVIEW.md)
- [Optional historical Firebase import and guarded rollback](../tools/migration/README.md)
- [Documentation index and historical audit trail](../docs/README.md)
