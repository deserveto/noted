# Design System: Noted

> **Source of truth.** Every value in this document was extracted from the implemented code:
> `lib/utils/app_colors.dart`, `lib/utils/app_theme.dart`, and the widgets/views under `lib/widgets/` and `lib/views/`.
> Values marked **"(recommended, not yet in code)"** are proposals and have no backing source yet.
> If code and this document disagree, the code wins — then update this file.

| Who reads this | When |
|---|---|
| AI agents extending the UI | Before creating any new screen, widget, color, or text style |
| Developers | Before adding UI code, and when reviewing UI PRs |
| Modifiers | Change tokens in `app_colors.dart` / `app_theme.dart` **first**, then update the matching row here. Never hardcode the old value in widgets. |

---

## 1. Visual Theme & Atmosphere

A **calm, minimal, soft-academic** mobile interface: warm off-white paper (`#F8F7F2`), compact rounded controls, and note tiles in muted pastel colors, like a tidy desk planner. Density is **balanced (5/10)**, variance is **low (3/10)** — predictable symmetric layouts, no decorative noise. Motion is **restrained (3/10)**: Flutter default Material 3 transitions only; no custom animation system exists in code.

Keywords: paper, planner, ink, pastel tile, flat (elevation 0 everywhere except FAB/snackbar).

**Firmly banned:** neon/purple gradients, pure black (`#000000`), decorative hero imagery on productivity screens, custom mouse-cursor effects, more than one strong accent per screen. The identity is carried by the pastel note-tile palette + dark ink controls, not by glow or shadow.

---

## 2. Color Palette & Roles

All tokens below exist in code in `lib/utils/app_colors.dart` (`AppColors`).

### Surfaces & neutrals — Light

| Token | Hex | Role |
|---|---|---|
| `AppColors.background` | `#F8F7F2` | Scaffold/app-bar background (warm paper) |
| `AppColors.surface` | `#FAF9F5` | Near-white surface variant (rarely used directly) |
| `AppColors.card` | `#FFFFFF` | Card, bottom sheet, dialog, nav-bar background |
| `AppColors.searchFill` | `#E9E7E1` | Text-field fill (search bar, inputs) |
| `AppColors.border` | `#E4E0D7` | Dividers, card borders, chip outlines |
| `AppColors.text` | `#2F2F2F` | Primary text (soft charcoal; never `#000`) |
| `AppColors.mutedText` | `#6F6F6F` | Secondary text, hints, icons |
| `AppColors.ink` | `#242424` | "Ink" controls: FAB (light), selected chip, primary buttons, snackbar |
| `AppColors.disabled` | `#BDB8AD` | Disabled chip state |

### Surfaces & neutrals — Dark

| Token | Hex | Role |
|---|---|---|
| `AppColors.darkBackground` | `#161817` | Scaffold/app-bar background |
| `AppColors.darkSurface` | `#202421` | Dark surface variant |
| `AppColors.darkCard` | `#252B27` | Cards, sheets, dialogs, nav bar |
| `AppColors.darkSearchFill` | `#303630` | Text-field fill |
| `AppColors.darkBorder` | `#3D443F` | Dividers/borders |
| `AppColors.darkText` | `#F3F1EA` | Primary text (warm white) |
| `AppColors.darkMutedText` | `#C0BDB4` | Secondary text, hints, icons |

### Brand accents

| Token | Hex | Role |
|---|---|---|
| `AppColors.primary` | `#6A9C89` | Selected chips, week-strip today, stat icons, FAB (dark), Edit button |
| `AppColors.primaryDark` | `#4F7E6C` | Darker primary variant (spare; rarely used) |
| `AppColors.secondary` | `#FFD66B` | Amber accent: focused-border/floating-label (dark inputs), progress indicator (dark) |
| `AppColors.error` | `#E57373` | Error text/borders, delete actions |

### Note-tile pastel palettes (`AppColors.noteColors` / `darkNoteColors`, cycled by `AppColors.noteColorFor(brightness, index)`)

| Index | Light | Dark |
|---|---|---|
| 0 | `#CFE6FF` sky blue | `#24425E` deep blue |
| 1 | `#FFC5D7` rose | `#5B2B3B` dark rose |
| 2 | `#D6F8D4` mint | `#294C35` deep green |
| 3 | `#FFEDAD` butter | `#5A4822` dark olive |
| 4 | `#FFD5C8` peach | `#56372D` dark clay |
| 5 | `#D9CCFF` lavender | `#3D315E` deep violet |

**On-tile text rule (in code, `note_card.dart`):** compute `baseColor.computeLuminance() > 0.45` → text uses `AppColors.text` (`#2F2F2F`) on light tiles, `AppColors.darkText` (`#F3F1EA`) on dark tiles. Meta chips on tiles: light tile → `Colors.white` at 78% alpha; dark tile → `Colors.black` at 20% alpha.

### ColorScheme wiring (in code)

`AppTheme` builds `ColorScheme.fromSeed(seedColor: primary)` then overrides: `primary → AppColors.primary`, `onPrimary → white`, `secondary → AppColors.secondary`, `onSecondary → AppColors.text`, `error → AppColors.error`, `surface → card / darkCard`, `onSurface → text / darkText`. Widgets should read semantic roles from `Theme.of(context).colorScheme` / `theme.dividerColor` — access `AppColors` directly only for effects the ColorScheme can't express (e.g., the ink FAB/primary button, the note-tile palettes).

---

## 3. Typography Rules

- **Family:** `Roboto` (Flutter default, set via `fontFamily: 'Roboto'` in both themes in `app_theme.dart`). No custom fonts are registered in `pubspec.yaml`.
- **Hierarchy via weight + color, not size inflation.** Titles jump to heavy weights (w700–w900); body stays regular. Never introduce an unguarded font family (recommended: any new custom font must be added as a named flutter font + wired through `fontFamily` in both light and dark themes — recommended, not yet in code).

### TextTheme (in code, identical structure light/dark)

| Role | Token | Weight | Color | Other |
|---|---|---|---|---|
| App-bar title | `appBarTheme.titleTextStyle` | w700 | text | size 22, left-aligned (`centerTitle: false`) |
| Display / page titles | `textTheme.displaySmall` / `headlineMedium` | w700 | text | pages override size to 28–34 & w900 |
| Section titles | `textTheme.titleLarge` / `titleMedium` | w700 | text | `titleLarge` pages override to 21/w900 |
| Body | `textTheme.bodyLarge`, `bodyMedium` | regular | text | height 1.35 |
| Caption / meta | `textTheme.bodySmall` | regular | mutedText | height 1.3 |
| Button label | `textTheme.labelLarge` | w700 | (per component) | — |

### Page-heading conventions (in code pattern across views)

| Context | Size | Weight | Source |
|---|---|---|---|
| Auth heading ("Welcome Back") | 34 | w900 | `sign_in_page.dart` |
| Page title ("Notes", "Profile") | 32 | w900 | `notes_page.dart`, `profile_page.dart` |
| Greeting ("Hello, …") | 32 | w900 | `home_page.dart` |
| Note detail title | 28 | w900 | `note_detail_page.dart` |
| Note card title | 15 | w900 | `note_card.dart` |
| Stat value | 28 | w900 | `stat_card.dart` |
| Empty-state title | 18 | w800 | `empty_state.dart` |
| Toolbar button letter | 14 (default) | w900 / italic | `formatting_toolbar.dart` |
| Meta chip | 11 | w700 | `note_card.dart` `_MetaChip` |

Rule: these literal `TextStyle(fontSize: …, fontWeight: …)` usages exist in code; new code should prefer `theme.textTheme.<role>?.copyWith(...)` over raw `TextStyle()` — but keep the exact size/weight numbers above for consistency.

---

## 4. Spacing, Radius, Elevation

### Screen padding (in code)

| Context | Value |
|---|---|
| Standard page edge padding | 20 (`EdgeInsets.all(20)` / `fromLTRB(20, 18, 20, 0)`) |
| Auth screens (`sign_in`, `sign_up`, `profile`) | 24 |
| Note detail | 22 |
| List content bottom clearance above FAB + nav bar | 96 |

### Vertical rhythm (in code)

| Gap | Usage |
|---|---|
| 4–8 | Micro: label→subtitle, chip internals |
| 10–14 | Between related blocks (search→chips, card title→content) |
| 16–18 | Form fields, toolbar→content, logout spacing |
| 22–34 | Section breaks (stats→section title, heading→profile avatar) |

Recommended scale for new screens: `4 / 8 / 12 / 16 / 24 / 32` (recommended, not yet in code — currently a looser mix of literal 6, 10, 14, 18, 22, 34).

### Radius scale (in code)

| Radius | Usage |
|---|---|
| 6 | Meta chips inside note tiles |
| 8 | Note cards, stat cards, buttons containers, error banner, week-strip cells (10 ≈ same family) |
| 10 | Primary/secondary custom buttons, week-strip today cell |
| 12 | Filter chips (ChipTheme + CategoryChips use 8–12), field containers, toolbar, pending-share card, snackbar 14≈ |
| 14 | Snackbar |
| 18 | Text fields (InputDecorationTheme), category bottom sheet (top) |
| 20 | Dialogs |
| 21 | Search field (pill, height 42) |
| 24 | Bottom sheets (top, global theme) |
| Circle | FAB (`CircleBorder()`) |

### Elevation (in code)

- Everything is **flat**: AppBar `elevation: 0`, `scrolledUnderElevation: 0`; NavigationBar, chips, cards — `elevation: 0`, `surfaceTintColor: Colors.transparent`.
- The only shadows in the codebase: the pending-share card (black @3% alpha, blur 4, offset (0,2)) in `notes_page.dart`.
- Recommended: keep it that way — express hierarchy with surface color, borders, and the pastel note-tile fills, not shadows (consistent with code).

---

## 5. Component Stylings

Components live in `lib/widgets/`. Reuse them; do not rebuild variants per screen.

### NoteCard (`widgets/note_card.dart`)
- Structure: pastel fill (from note palette), radius 8, padding 14; title (15/w900, 1–2 lines, compact mode → 1) + pin toggle (Icons.push_pin / outlined, size 20) row → content preview (13, height 1.35, 2–7 lines) → `Wrap` of meta chips (#category, "By {owner}", `dd MMM yyyy` date), chip gap 6.
- Meta chip: radius 6, h8/v5 padding, 11/w700, overlaid translucent white/black per luminance rule (§2).
- States: tap → open detail (InkWell ripple); pin tap toggles favorite; `compact: true` for tight contexts (1 title / 2 content lines).
- Use for: every note representation in a grid/list. Note color must come from `AppColors.noteColorFor(brightness, index)` — never hardcode.

### CategoryChips (`widgets/category_chips.dart`)
- `ChoiceChip` row in a 38px-high horizontal `ListView`, 8px gaps, radius 8–12 (r8 inline vs ChipTheme r12), padding h8, `showCheckmark: false`.
- Resting: surface bg, divider border, w500 onSurface label. Selected: primary fill, white w700 label, primary border.
- Always prepend the literal `'All'` category and route selection through the ViewModel.

### StatCard (`widgets/stat_card.dart`)
- Surface fill + 1px divider border, radius 8, padding 16. Icon (primary) → 16 gap → value (28/w900) → 2 gap → label (bodyMedium). Always used inside a `Row` as `Expanded` with 12px gaps.

### CustomButton (`widgets/custom_button.dart`)
- Full-width, height 54, `FilledButton.icon`, radius 10, label 16/w700, trailing icon (default `Icons.arrow_forward_rounded`).
- Primary: `AppColors.ink` (light) / `colorScheme.primary` (dark), white foreground. Secondary (`isSecondary: true`): surface fill, divider border, onSurface foreground. Loading: replaces icon with 18px/2-width spinner, disables press. Disabled: fill at 55% alpha.
- Note: the fixed dark FAB/primary-ink behavior is a deliberate "ink on paper" affordance — don't replace `CustomButton` with a bare `FilledButton` on new screens.

### CustomTextField (`widgets/custom_text_field.dart`)
- Thin wrapper over `TextFormField` + global `InputDecorationTheme`: filled, `searchFill`/`darkSearchFill` fill, **no resting border**, radius 18, padding h18/v14, muted label/hint/icons.
- Focus: 1.2px border — `ink` (light) / `secondary` (dark). Error: 1.2 (focused 1.4) `error` border. Floating label: `ink` (light) / `secondary` (dark).

### EmptyState (`widgets/empty_state.dart`)
- Centered, padding 32: icon 52 (onSurface @58%) → 18 gap → title 18/w800 → 8 gap → message bodyMedium @58%, height 1.4. Use for every empty list/grid — with a guiding message (e.g., "Tap the add button to create your first note.").

### FormattingToolbar (`widgets/formatting_toolbar.dart`)
- Markdown edit toolbar above the content field (used only in `add_edit_note_page.dart`). Surface container, radius 12, divider border, padding 8, `Wrap` 8/8.
- Buttons: 48×48, radius 12. Inactive: `surfaceContainerHighest` bg / onSurface fg. Active: primary bg / white fg. Inline buttons show literal styled letters (B / I / U); list buttons are filled-tonal icons with tooltips.

### Bottom sheets (in code pattern)
- Global theme: card bg, transparent surface tint, top radius 24. Category picker (`add_edit_note_page.dart`): `isScrollControlled`, top radius 18, padding L/R 20, T 18, B + viewInsets, max height 0.72 of screen; 18/w800 centered title + close IconButton; input → divider-separated dense ListTiles with check-circle icons → full-width `CustomButton`. All selection affordances (category, share) must be sheets, never new routes.

### FloatingActionButton
- Circular, ink bg (light) / primary bg (dark), white `Icons.add_rounded` size 32. One per scaffold on Home/Notes screens; pushes `AddEditNotePage`. Do not restyle per screen.

### NavigationBar (MainShell)
- Height 68, card/darkCard bg, flat, `surfaceTintColor` transparent. Indicator: ink (light) / primary (dark); selected icon **white**. Labels: 12px — selected w700 text, unselected w500 muted. Tabs: Home, Notes, Favorites, Connections, Profile with outline→filled icon pairs; screens kept alive via `IndexedStack` (views must read `Theme.of(context)` to rebuild on theme change — see comment in `notes_page.dart`).

### SnackBar
- Floating, ink bg (light) / darkText bg (dark), radius 14, radius shape; content white / text color. Use for save/share confirmations.

### Detail chips & profile ("ink-on-surface" rows)
- Note detail: `Wrap` of icon+label chips (8/8 gaps), title 28/w900, Markdown body 16 / height 1.65, action row = primary `FilledButton` (52 min height) + `OutlinedButton` beside it.
- Profile rows/metrics: surface containers, radius 8, 1px divider border, padding 18; label w700 left, value 18/w900 right; switches in `SwitchListTile` with `AppColors.ink` active thumb (in code, add-edit page; dark page uses default).

---

## 6. Layout Principles & Screen Anatomy

- **Grid:** All screens are single-`Scrollable`+boxed columns (`Padding(LT20R/K…)` → `Column`). Note grids: **2 columns**, 12px cross/main spacing, `childAspectRatio: 0.78`, bottom padding 96. Notes are laid as uniform 2-up tiles on tinted pastels — "staggered" feel comes from cycling tile colors, not from masonry.
- **Scroll anatomy:** `CustomScrollView` with header `SliverToBoxAdapter` (Home) or plain `Column` + `Expanded` grid (Notes). Loading → centered `CircularProgressIndicator` swapping with the grid; empty → `EmptyState` in `SliverFillRemaining`/`Expanded`.
- **Navigation:** `MainShell` holds 5 tabs in an `IndexedStack` + `NavigationBar`; detail/editor push on top via `MaterialPageRoute`.
- One prominent dark action per screen (FAB or `CustomButton`); at most one other bordered surface button.

| Screen | Anatomy (in code) |
|---|---|
| **Home** (`home_page.dart`) | FAB · greeting (32/w900) + subtitle (@62%) · week strip (7 × 36 cells, radius 10, today = primary fill, white text) · StatCard row · "Recent Notes" (21/w900) · 2-up note grid |
| **Notes** (`notes_page.dart`) | FAB · title 32/w900 · search pill (h42, radius 21, clear) · CategoryChips · optional `_ErrorBanner` (error @12% fill / 40% border, radius 8, 12px text) · optional pending-shares 105px horizontal list (cards w250, radius 12, Accept/Decline) · 2-up grid |
| **Detail** (`note_detail_page.dart`) | App bar: pin / share / edit icon actions (owner-only enabled) · title 28/w900 · detail chips (`Wrap` 8/8) · MarkdownContent 16/1.65 · Edit `FilledButton` + secondary `OutlinedButton`, 52 height |
| **Add/Edit** (`add_edit_note_page.dart`) | App bar "Add/Edit Note" · Title field → Category `InputDecorator` (suffix down-arrow, opens sheet) → FormattingToolbar → Content field (maxLines 12) → Favorite `SwitchListTile` in bordered radius-8 container → `CustomButton` "Save". Form-validated via `Validators.requiredText` |
| **Auth** (`sign_in_page.dart`, `sign_up_page.dart`) | Padding 24 · heading 34/w900 · sub-line · `CustomTextField`s (16 gaps) · inline error text (`colorScheme.error`) · `CustomButton` · `TextButton` switch-auth link |
| **Profile** (`profile_page.dart`) | Title 32/w900 · avatar circle (radius 48, primary fill, white w900 initials) + name/email · bordered metric rows (18/w900 values) · Dark-mode `SwitchListTile` in bordered container · spacer · Logout `CustomButton` |

---

## 7. Motion & Interaction

- **In code:** only Flutter Material defaults — `InkWell`/`InkResponse` ripples (pin radius 20), sheet/scroll-into-view animations. No explicit animation controllers, springs, or stagger code exists. Theme switching is instant (`ThemeViewModel.setDarkMode` → `notifyListeners()`).
- Recommended (not yet in code): if motion is added, keep it subtle ≤200ms implicit animations on chips/sheets; do not introduce a global animation library.
- Dark mode is a persistent user setting (Profile switch), not system-followed (`ThemeMode` starts and stays on explicit light/dark).

---

## 8. Do & Don't for Agents Extending the UI

**DO**
1. Add every new color as a named `static const` in `app_colors.dart`, with both light & dark counterparts, and document it here.
2. Derive widget colors from `Theme.of(context).colorScheme` / `theme.textTheme` / `theme.dividerColor`; reach for `AppColors` only for ink controls & note palettes.
3. Reuse `lib/widgets/` components (NoteCard, CategoryChips, StatCard, CustomButton, CustomTextField, EmptyState) — extend them with parameters rather than cloning.
4. Match text sizes/weights to the tables in §3 (titles w900 at 28–34; body 1.35 height; meta 11/w700).
5. Use the radius scale in §4 and keep elevation 0.
6. Keep every new screen on the standard padding (20 / 24) and FAB clearance (bottom 96).
7. Gate destructive actions on `AppColors.error`, with confirm styles matching the existing delete affordances.
8. Add tooltips on icon-only actions (`tooltip:` — existing pattern) and keep the pin metaphor for favorites (never a heart/star).

**DON'T**
1. Don't hardcode `Color(0xFF…)`, `Colors.grey`, or raw `TextStyle(fontSize:)` without matching §3 values.
2. Don't introduce new fonts, emoji icons, image placeholders, or decorative gradients.
3. Don't add elevation/shadows (except the pending-share 3% card shadow pattern) or tinted (`surfaceTint`) elevation.
4. Don't use pure `#000000`/`#FFFFFF` text — text is `#2F2F2F`/`#F3F1EA` (with `Colors.white` only on primary/primary-dark filled controls, per code).
5. Don't create a second accent; primary `#6A9C89` + secondary `#FFD66B` is the entire accent budget.
6. Don't push modals as full screens — bottom sheets only (category/share pattern).
7. Don't bypass state: read/write via the existing `*_viewmodel.dart` classes with `context.watch`/`context.read`.

---

## 9. Asset Guidance

- **Logo:** `docs/Logo.png` — the only registered app asset (`pubspec.yaml` → `flutter.assets`). Use for the welcome/auth branding and future headers. Recommended, not yet in code: render at intrinsic proportions, tintable variants only if a monochrome version is added; do not recolor or distort the original.
- **Icons:** Material Symbols via `Icons.*_rounded` / `*_outlined` (filled variants for selected nav states). Never add icon packs or emoji.
- **Fonts:** none bundled (`fontFamily: 'Roboto'`).

---

## 10. How to Extend

Adding a **new token**: `app_colors.dart` (light + dark consts) → wire into `AppTheme.light`/`.dark` → add a row in §2 → use via theme.
Adding a **new screen**: Scaffold (background from theme) → padding 20/24 → heading per §3 → widgets from `lib/widgets/` → EmptyState when empty → FAB/bottom-sheet affordances → register route in `app_routes.dart` + `app.dart`.
Adding a **new widget**: one file in `lib/widgets/`, theme-driven colors, radius/spacing from §4, no per-call-site hardcoding → document here.
Adding a **new note-tile color**: append to both `noteColors` and `darkNoteColors` (keep indexes aligned — pairing is positional) and verify luminance contrast on both tile and meta chips.
Changing the theme system: `app_theme.dart` is the single seam — `MaterialApp` consumes `AppTheme.light/.dark` + `ThemeViewModel.themeMode` in `app.dart`; all screens must keep reading `Theme.of(context)` for rebuilds inside the `IndexedStack`.
