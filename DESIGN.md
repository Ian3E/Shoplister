---
name: Shoplister
description: Native iOS grocery list — system lists, user accent tint, scannable catalog rows
colors:
  accent-default: "#007AFF"
  accent-orange: "#FF9500"
  accent-red: "#FF3B30"
  accent-green: "#34C759"
  accent-pink: "#FF59B8"
  accent-purple: "#AF52DE"
  surface-list: "#FFFFFF"
  surface-list-dark: "#000000"
  surface-grouped: "#F2F2F7"
  label-primary: "#000000"
  label-secondary: "#3C3C43"
  label-tertiary: "#3C3C4399"
  label-quaternary: "#3C3C434D"
  section-title: "#474747"
  section-title-dimmed: "#B8B8B8"
  divider: "#D6D6D6"
  pill-surface-light: "#FFFFFF"
  pill-surface-dark: "#1A1A1A"
typography:
  group-header:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "20pt"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "normal"
  row-title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "17pt"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "normal"
  row-quantity:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "17pt"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "normal"
  nav-title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "15pt"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  nav-subtitle:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13pt"
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: "normal"
rounded:
  pill: "9999px"
  settings-icon: "8px"
spacing:
  row-horizontal: "16px"
  row-vertical-inset: "8px"
  group-gap-after-items: "12px"
  group-gap-before-title: "16px"
  chevron-column: "22px"
  min-touch-row: "44px"
components:
  list-row:
    backgroundColor: "{colors.surface-list}"
    typography: "{typography.row-title}"
    padding: "8px 16px"
  group-header:
    backgroundColor: "{colors.surface-list}"
    textColor: "{colors.section-title}"
    typography: "{typography.group-header}"
  quantity-pill:
    backgroundColor: "{colors.pill-surface-light}"
    textColor: "{colors.accent-default}"
    rounded: "{rounded.pill}"
    padding: "6px 16px"
  toolbar-button:
    backgroundColor: "transparent"
    textColor: "{colors.accent-default}"
    size: "44px"
---

# Design System: Shoplister

## 1. Overview

**Creative North Star: "The Native Aisle"**

Shoplister looks and behaves like a first-party iOS utility: plain lists, system navigation, semantic labels, and a single user-chosen accent that marks interactive quantity and selection chrome—not decorative marketing color. Density scales with the in-app text size setting; bilingual layout mirrors cleanly for Hebrew RTL.

The system rejects web-ported patterns, card stacks, and AI-default warm neutrals. Depth comes from separators, label hierarchy, and one restrained shadow on the quantity pill—not layered cards or glassmorphism for its own sake. Home’s section title bar may use Liquid Glass where the platform provides it; Store lists stay flat on `systemBackground`.

**Key Characteristics:**

- **Semantic surfaces** — `systemBackground` / `systemGroupedBackground` and UIKit label colors adapt to light, dark, and increased contrast automatically.
- **One accent voice** — User theme tint (`AppTheme`, default blue `#007AFF`) on pills, checkmarks, counts, and key actions; never splashed across full screens.
- **List-first layout** — Home and Store are grouped `List` rows with shared header typography (`.title3.weight(.heavy)`).
- **Quiet completion** — All-checked store sections use dimmed header color (`quaternaryLabel` / `#B8B8B8` light) so remaining work stays obvious.
- **Motion with restraint** — Snappy springs for collapse/expand; `.snappy` for list mutations; honor Reduce Motion for empty-state and pull gestures.

## 2. Colors

A **system-native neutral base** plus **one user-selected accent**. No fixed marketing palette on surfaces.

### Primary

- **Accent Tint (default Shoplister Blue)** (`#007AFF`): User-configurable via Settings → Appearance. Drives quantity pill text/icons, theme-colored row labels on Home, unchecked counts, and interactive emphasis. Presets: red `#FF3B30`, orange `#FF9500`, green `#34C759`, blue `#007AFF`, purple `#AF52DE`, pink `#FF59B8`, or custom hex.

### Neutral

- **List Surface** (`systemBackground` / `#FFFFFF` light): Plain Home catalog and Store shopping list backgrounds (`Color.shoppingListBackground`).
- **Grouped Surface** (`systemGroupedBackground` / `#F2F2F7` light): Settings and grouped contexts where UIKit grouped style applies.
- **Primary Label** (`label` / `#000000` light): Active section titles, navigation principal text, primary row content.
- **Secondary Label** (`secondaryLabel`): Store group headers in light mode (`#474747` custom gray), nav subtitles, de-emphasized chrome.
- **Tertiary / Quaternary Label**: Inactive Home section tabs (`#C7C7CC` light approx.), dimmed all-checked store section titles.
- **Divider** (`#D6D6D6` light / white 12% dark): Inter-group hairlines (`HomeCatalogListDividerChrome.sectionLineColor`).

### Named Rules

**The One Tint Rule.** The accent color appears on controls and quantities, not on list backgrounds or section fills. If more than ~10% of a screen reads as accent, pull back.

**The Semantic Label Rule.** Prefer `UIColor.label`, `.secondaryLabel`, `.tertiaryLabel`, `.quaternaryLabel` over hard-coded grays except where the codebase already tunes store headers for legibility in light mode.

## 3. Typography

**Display Font:** SF Pro (system) — not used for marketing display; app has no hero typography.

**Body Font:** SF Pro via SwiftUI system text styles (`DynamicTypeSize` mapped from `AppTextSize`: xSmall → xLarge).

**Label/Mono Font:** SF Pro with `.monospacedDigit()` on quantity columns and collapsed counts.

**Character:** Utilitarian and legible at arm’s length in a store aisle. Weight contrast separates group headers (heavy title3) from row body text.

### Hierarchy

- **Group header** (heavy title3, ~20pt): Home/Store section titles (`CatalogGroupHeaderChrome.titleFont`, Store `shoppingGroupHeaderTitleFont`).
- **Row title** (body, 17pt): Item names in catalog and shopping rows; bold when quantity pill expanded on Home.
- **Row quantity** (body bold, monospaced digits): Trailing store quantities (`ShoppingListChrome.trailingQuantityFont`).
- **Nav title** (subheadline semibold): Store toolbar principal (“Shopping list”).
- **Nav subtitle** (footnote regular): Remaining item count under nav title.
- **Quantity pill collapsed** (callout semibold); **expanded** (title3 number, title2 steppers per `QuantityPillLayoutMetrics.production`).

### Named Rules

**The Dynamic Type Rule.** Row height and spacing scale via `AppTextSize.listSpacingScale` (0.8–1.2); never hard-code point sizes for list content except pill layout metrics tied to text style slots.

**The SF System Rule.** UI chrome uses SwiftUI system fonts; custom font files are not part of this product.

## 4. Elevation

Flat-by-default lists. Depth is communicated through **separators**, **label steps**, and **section collapse**, not card elevation.

### Shadow Vocabulary

- **Quantity pill** (`shadow radius 2.5, y 1.5`, black 10% light / 45% dark): Only common persistent shadow; keeps the pill readable on white rows.
- **Liquid Glass** (Home section title safe area bar): Platform `.glassEffect(.regular)` — use only where already established; do not hand-roll blur stacks elsewhere.

### Named Rules

**The Flat List Rule.** No card containers for standard catalog or shopping rows. Settings may use grouped inset lists per HIG.

**The Resting Shadow Rule.** Shadows appear on the quantity pill capsule only; buttons and rows do not drop shadow at rest.

## 5. Components

### Lists (Home catalog & Store)

- **Style:** Plain `.listStyle(.plain)`, hidden scroll background, full-bleed rows with horizontal inset 16pt.
- **Row minimum height:** 44pt × `listSpacingScale` (`CatalogListRowDensity.systemListRowMinimumHeight`).
- **Separators:** Custom inter-group hairlines; section spacing from `ShoppingListMetrics` (12pt after last item, 16pt before next title).
- **Checked state:** Strikethrough/dim on shopping rows; optional “Sort checked items” moves checked rows to a bottom section.

### Group headers (Store)

- **Typography:** title3 heavy; active color `#474747` light / secondaryLabel dark; **dimmed when all items checked** (`#B8B8B8` light / quaternaryLabel dark).
- **Interaction:** Tap header to collapse/expand; chevron rotates; collapsed shows unchecked count in accent color.

### Home section title bar

- **Style:** Horizontal scroll of section names; active = label, inactive = tertiary gray; pinned with Liquid Glass safe area bar when enabled.
- **Spacing:** 24pt horizontal content margin; 26pt × scale between titles.

### Quantity pill (`ExpandableQuantityPill`)

- **Shape:** Continuous capsule (`9999px` radius).
- **Fill:** White (light) / `#1A1A1A` (dark); 1pt border (white 95% light / white 14% dark).
- **Text/icons:** Accent tint; expand inward from screen edge; spring `response 0.28, damping 0.82`.
- **Tap pulse:** 1.1× scale on +/- (not on remove-at-1).
- **Auto-collapse:** 2s after expand unless `schedulesAutoCollapse` disabled.

### Toolbars & settings

- **Toolbar buttons:** Borderless, semibold label on Done; circular tap targets for gear/ellipsis (`catalogToolbarCircularTapTarget`).
- **Settings root rows:** 30×30pt rounded (8pt) gradient icon tiles per section category.

### Navigation

- **Pattern:** Single `NavigationStack` (no tab bar): Store shopping list is the root (bottom-trailing theme + opens pull-to-add); All Items is pushed from the pull-to-add sheet’s **All Items** button and returns via its bottom-leading list button or swipe-back; sheets for settings, new item, recipes; full-window overlays for explainers and photo preview.

## 6. Do's and Don'ts

### Do:

- **Do** use system semantic colors and Dynamic Type for all new screens.
- **Do** apply the user accent tint only to interactive emphasis (pill, counts, checkmarks, key labels).
- **Do** dim completed store section titles when every row in the section is checked.
- **Do** mirror layout for Hebrew (`CatalogLayoutMirroring`, RTL section title scroll anchors).
- **Do** use `.snappy` or documented spring constants for list mutations; gate motion on `accessibilityReduceMotion`.
- **Do** keep minimum 44×44pt tap targets for toolbar and pill controls.

### Don't:

- **Don't** use generic SaaS dashboards, card-heavy admin UIs, or marketing landing-page patterns inside the app shell.
- **Don't** port web navigation (custom global nav, hover-dependent affordances, non-system controls).
- **Don't** use AI-default visual tropes: cream/sand body backgrounds, gradient text, decorative glassmorphism, identical icon+title card grids, uppercase tracked eyebrows on every section.
- **Don't** use over-animation or bounce-heavy motion that fights iOS system transitions.
- **Don't** clutter the Store list—checking items and quantities stay the primary task.
- **Don't** splash accent color across full-screen backgrounds or section fills.
- **Don't** add nested cards or side-stripe accent borders on list rows.
