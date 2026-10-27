# Noted design system

The approved reference is `C:/dev/NotedUIRevised`, supplied on 2026-10-26. Its layout, typography and interaction direction replace the former Roboto/pin/circular-FAB design. Keep the original `docs/Logo.png`, the Noted name, and personal/business positioning.

## Tokens

| Role | Light | Dark |
|---|---|---|
| Background | #F8F7F2 | #1B1E1C |
| Surface | #FFFFFF | #242926 |
| Text | #2F2F2F | #F1EEE4 |
| Muted | #6F6F6F | #A3A89F |
| Border | #E4E0D7 | #343A36 |
| Sage | #6A9C89 | #86B7A3 |
| Sage action | #4F7E6C | #86B7A3 |
| Soft | #EFEDE5 | #2C322E |
| Yellow | #FFD66B | #FFD66B |
| Danger | #E57373 | #E57373 |

Color keys are `blue`, `pink`, `mint`, `yellow`, `peach`, `lav`. Light: #CFE6FF, #FFC5D7, #D6F8D4, #FFEDAD, #FFD5C8, #D9CCFF. Dark: #2F3C48, #47343B, #2F4232, #45402B, #48372F, #3A3549. Favorite stars use #E8A93A. Current-user fallback avatar uses yellow; collaborators derive stable pastel colors from their UID. Real photos take precedence.

All colors live in `lib/utils/app_colors.dart`; both themes are composed in `app_theme.dart`. Use semantic ColorScheme roles in views. Persist a note's color; do not change it when sorting/filtering.

## Type and shape

DM Sans is the bundled UI font. Newsreader italic is reserved for headline accent words and quotations. Font licenses are in `assets/fonts/`. Page headings: 32px/600/-0.8px; hero:34px/600; body:15px; metadata:12–13px. Editor body uses the user's 14–20px preference, line height1.7. H3:19px/600. Use Theme text styles.

Main gutters24px; sheets20px. Note radii16px, surfaces18px, inputs/buttons16px, icon buttons12px, sheet top corners28px, pills fully rounded. Icon targets44px minimum. The shell FAB is56px with radius18px. Use the exact reference SVG paths in `widgets/reference_icon.dart`; Live always uses the broadcast path. New media play/pause/clock/numbering paths extend the reference set.

## Navigation and components

Tabs: Home, Notes, AI, Connections, Profile. AI can be disabled in Settings. Favorites live inside Notes' All/Favorites/Live control. The FAB appears on Home/Notes. Main content is full width on phones, centered to700px on larger displays, without a fake device bezel. Editors/settings are routes; calendar/share/AI/recording/drawing/choice flows use sheets. Native shared-note links are `noted://app/notes/<id>` and remain member-only; auth recovery links use `noted://app/auth-callback`.

Reuse `noted_ui.dart`, `NoteCard`, `NotesMasonry`, `CategoryChips`, `EmptyState` and `ReferenceIcon`. Cards show category, title, plain-text preview, relative edit time, favorite star and real collaborator avatars. Presence dots reflect expiring server records. Do not add hardcoded users, note content, notifications or AI answers to production. Decorative onboarding example cards are the sole exception.

Sheets rely on Flutter modal focus, dismissal and back behavior. All icon controls have tooltips; counts/save status use live semantics. Respect MediaQuery.disableAnimations and the user's Reduce motion setting. Prefer quiet200–240ms motion; skeleton pulses use1200ms and flashcards300ms. The calendar supports tab traversal and arrow keys. Library results use a two-column masonry layout or a list.

## Rich documents and persistence

The editor is WYSIWYG using Quill, with a compact insert/formatting toolbar above the keyboard. Never show Markdown syntax as the writing UI. Existing Markdown remains readable and imports without a destructive bulk migration; actual edits save a versioned Delta envelope through DocumentCodec. Use codec methods for previews, search, word counts and HTML exports. Attachments upload to private Supabase Storage (`note-media` and `avatars` buckets) and resolve via short-lived signed URLs. Autosave serializes writes, queues offline edits per account, and preserves later typing; live edits use Delta operational transformation with atomic revision-checked RPCs (`commit_note_revision`). Competing metadata changes preserve both versions for review.

Theme, density, week start, calendar dots, editor text size and related preferences come from SettingsViewModel. Notes and connections remain in their existing repositories/viewmodels. AI and email credentials belong only to Supabase Edge Functions. App lock wraps the Navigator and preserves all routes/drafts while obscured.

## Verification

Check light/dark at360,390,430px. Golden fixtures belong only to tests. Golden images are local Flutter render references, not proof of pixel equality against the React prototype. Inspect screenshots when updating them. Run pub get, analyze, tests, APK build and Supabase SQL/Edge Function/migration tests before reporting completion. Device-only audio, gallery, biometrics, external deep links and multi-device sync require device/staging acceptance checks.
