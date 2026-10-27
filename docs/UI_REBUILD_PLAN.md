# Noted reference rebuild — 2026-10-26

> [!NOTE]
> **Historical UI Milestone Record**: This document captures the 2026-10-26 UI rebuild on `feature/noted-ui-revised`. The application backend was subsequently migrated in full from Firebase to **Supabase** on `feature/supabase-migration` while preserving this exact UI, design system, and feature set. For current backend architecture and setup, see [SUPABASE_MIGRATION_PLAN.md](SUPABASE_MIGRATION_PLAN.md) and [SUPABASE_SETUP_AND_CUTOVER.md](SUPABASE_SETUP_AND_CUTOVER.md).

Branch: `feature/noted-ui-revised`. Reference: `C:/dev/NotedUIRevised`. Framework remains Flutter, MVVM/Provider, Firebase. Original `docs/Logo.png` remains the brand mark. Reference UI and supplied brief override older DESIGN.md visual rules.

## Feature reconciliation

| Feature | TARGET | REFERENCE | Action |
|---|---|---|---|
| Email/password auth | Real | Simulated | Retain Firebase, restyle, add onboarding/reset |
| Notes CRUD + Markdown | Real | HTML contenteditable | Preserve legacy data; display/edit visual rich text and add attachments |
| Favorites | Tab | Library filter | Move to All/Favorites/Live segmented control |
| Categories and search | Real | Library filters | Preserve custom categories, add debounce/sort/view |
| Home week strip | Current week | Full month sheet | Month browsing + dated creation + daily activity |
| Copy sharing | Independent accepted copies | Simulated | Preserve independent copy workflow, secure acceptance |
| Collaborative notes | Absent | Simulated | Firestore membership, edit/view roles, realtime snapshots and conflict protection |
| Connections/removal | Real | Simulated | Retain removal, add invitations/cancel/resend |
| Notifications | Absent | Hardcoded | Real Firestore feed + server event jobs |
| Profile | Real basic | Rich mock stats | Real stats/profile editing, move account controls to Settings |
| Theme | In-memory toggle | Session settings | Synced user preferences + device cache + System |
| AI | Absent | Curated fake answers | Server-only OpenRouter integration, real scoped retrieval/sources |
| Attachments | Absent | Simulated | Firebase Storage + device recording/image/drawing |
| Export/account deletion | Absent | Simulated | Real export/auth/backend cleanup |
| App lock | Absent | Simulated | Platform authentication gate |
| Existing formatting shortcuts | Real | Rich toolbar | Preserve formatter behavior/tests |
| Logo | Original PNG | New drawn mark | Keep original PNG per user instruction |

## Data mapping

Note.id→noteId, body→content (legacy Markdown is imported into visual rich text), cat→category, fav→isFavorite, created/edited→createdAt/updatedAt. Add backward-compatible color keys, live member IDs/role map, revision and deletedAt. Member→real Firebase uid + user profile and presence records. Settings→users/{uid}/settings/preferences with device cache. Chat→users/{uid}/chats/{chatId}/messages. `prepareNotedAccount` transactionally backfills missing deletedAt metadata; content remains untouched until an edit. New documents store a versioned Quill Delta envelope in content. Shared favorites are personal records under users/{uid}/favorites.

## Implementation and proof

- [x] Audit reference/core app and existing model/auth/rules/tests; create requested branch.
- [x] Port tokens/fonts/exact SVG paths, shared components, shell and onboarding.
- [x] Home/library/calendar + categories/favorites/live/search/sort/list.
- [x] Rich editor, sharing, attachments and transactional document merging implemented.
- [x] Settings/profile/account persistence and device integration code implemented.
- [x] Callable AI + invitations + activity + scheduled recap with security rules implemented.
- [x] Responsive/golden and targeted regression tests; see report for device acceptance still required.
- [x] Final Flutter checks, Android APK and backend emulator tests; results recorded in report.

Backend deployment, real-provider/email calls and real-device multi-user acceptance are separate outstanding rollout checks. They are not implied by implementation checkmarks.

Provider decision: OpenRouter, model `openrouter/free`. Server key configured outside source control. Email: Resend, credentials to follow. Deployment and external multi-user tests require configured Firebase project access; do not claim those checks from local build alone.
