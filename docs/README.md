# Noted documentation

Start with the [project overview](../README.md) for screenshots, features, and local setup. This index separates current operational guidance from the planning and audit record.

## Use today

| Guide | What you will find |
|---|---|
| [Supabase setup & cutover](SUPABASE_SETUP_AND_CUTOVER.md) | Client/server configuration, Auth and activity email, migrations/functions, schedules, signing, and release checks |
| [Backend overview](../supabase/README.md) | Services, functions, authorization boundaries, and verification |
| [Design system](../DESIGN.md) | Color/type tokens, shared components, navigation, accessibility, and document behavior |
| [Migration tools](../tools/migration/README.md) | Optional legacy export/import, account state preservation, parity checks, and guarded database-only rollback |
| [Combined change review](FULL_CHANGE_REVIEW.md) | UI/backend/tooling coverage, corrected findings, regression evidence, and deployment limits for PR #50 |

## Review and history

These documents capture decisions and findings at their original milestones. Their historical status statements do not supersede the setup guide or prove the current live environment.

| Record | Context |
|---|---|
| [Migration plan](SUPABASE_MIGRATION_PLAN.md) | Original Firebase-to-Supabase scope and implementation approach |
| [Migration audit](SUPABASE_MIGRATION_AUDIT.md) | Findings and evidence from the migration audit |
| [Remediation report](SUPABASE_REMEDIATION_REPORT.md) | Earlier fixes, deployment checks, and signing work |
| [UI rebuild plan](UI_REBUILD_PLAN.md) | Interface rebuild scope and reference direction |
| [UI rebuild report](UI_REBUILD_REPORT.md) | UI implementation milestone and verification |
| [Audit remediation plan](superpowers/plans/2026-10-27-migration-audit-remediation.md) | Sequencing of the audit follow-up work |
| [Merged PR #50](https://github.com/deserveto/noted/pull/50) | Combined UI/backend source change and review discussion |

## Visual assets

The project icon is [`Logo.png`](Logo.png). The README's original vector banners live in [`assets/`](assets/); app screenshots reference the checked-in [Flutter golden fixtures](../test/goldens/) directly. They show fixture data, not production-user screenshots.

Update visuals when the interface changes, inspect light and dark variants, and keep screenshots aligned with the matching tests. Font attribution is retained in the [DM Sans](../assets/fonts/DMSans-LICENSE.txt) and [Newsreader](../assets/fonts/Newsreader-LICENSE.txt) licenses.
