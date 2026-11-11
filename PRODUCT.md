# Product

## Register

product

## Platform

ios

## Users

Primary users are people who manage grocery shopping for themselves or their household—often while moving through a store or planning at home. Many users work in **English or Hebrew** (including RTL layout), and expect the app to feel native on iPhone rather than like a ported website.

The job to be done: maintain a personal item library (Home), build and use a store-organized shopping list (Store), check items off while shopping, and optionally save or reuse lists (recipes). Secondary use includes sharing plain-text lists into the app via the share extension and backing up or restoring library data on device.

## Product Purpose

Shoplister is a grocery list and item library for iOS. Users catalog items by home location, add them to a store-section shopping list, check items off while shopping, clear completed lines, and manage settings (text size, appearance, language, backup). Data stays on device; there is no account or cloud sync in the core product loop.

Success looks like: fast add-to-list from Home, scannable Store list grouped by store sections, reliable check-off and quantity adjustment, and low friction for bilingual and accessibility needs (Dynamic Type, dark mode, reduced motion).

## Positioning

The practical native grocery list that respects how people actually shop—library at home, list at the store—with bilingual support and on-device privacy built in, not bolted on.

## Brand Personality

Calm, capable, and familiar—**native iOS first**, not flashy. Voice is direct and helpful (settings labels, explainers, empty states). The accent color is user-chosen but UI chrome stays system-native (lists, navigation, materials). Emotional goal: **confidence and clarity** in a repetitive weekly task, not delight-for-delight's sake.

## Anti-references

- Generic SaaS dashboards, card-heavy admin UIs, or marketing landing-page patterns inside the app shell
- Web-ported navigation (custom global nav, hover-dependent affordances, non-system controls)
- AI-default visual tropes: cream/sand body backgrounds, gradient text, decorative glassmorphism, identical icon+title card grids, uppercase tracked eyebrows on every section
- Over-animation or bounce-heavy motion that fights iOS system transitions
- Cluttered shopping lists that hide the primary task (check off, adjust quantity) behind chrome

## Design Principles

1. **Platform-native structure** — Store list as the root with Home (All Items) pushed on top (no tab bar), system lists, toolbars, sheets, and alerts; depart from HIG only when the shopping workflow clearly benefits.
2. **Task-first Store** — Checking items, quantities, and section grouping stay visually and motorically primary; settings and power features stay reachable but secondary.
3. **Readable at arm's length** — Dynamic Type, contrast-safe labels, and list density that scales with user text size preferences.
4. **Bilingual by default** — Layout mirroring and copy work equally in English and Hebrew; RTL is not an afterthought.
5. **Quiet completion** — Checked and all-done states recede (dimmed section titles, collapsible completed sections) so remaining work stays obvious.

## Accessibility & Inclusion

- Support **Dynamic Type** via app text size settings and system text styles where applicable.
- Respect **Reduce Motion** for animations (empty-state reveals, quantity pill, pull gestures).
- Maintain sufficient contrast for list labels and interactive controls in light and dark mode.
- VoiceOver labels on toolbars, explainers, and non-obvious gestures (e.g. pull-to-add, pull-to-clear).
- No WCAG web conformance target applies directly; follow **Apple HIG accessibility** expectations for native iOS.
