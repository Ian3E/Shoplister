# Household sync plan (CloudKit)

> **Scope:** Sync the item library, shopping list, sections, and saved lists across a user's own devices, then share them with a household.
> **Status:** Phase 0 implemented and tested (November 2026), shipping as 1.2. Phases 1–3 not started. Replaces the June 2026 plan and `MultiUserSharingPlan.md`.
> **Priorities:** simplicity and reliability over features.

---

## Product decisions (confirmed)

| Decision | Detail |
|---|---|
| Local-only is the default | Sharing requires iCloud. Without iCloud the app works exactly as today. |
| One household per user | Simplifies share ownership, Settings UI, and the share-extension snapshot. |
| One library language per household | All members share one catalog + list in one language. The inactive language's library stays local on each device. |
| Language change = household-wide reset | Same destructive reset as today, applied to everyone. **Only the owner can change it.** Members see the language as read-only. |
| Photos come last | Data sync ships and stabilizes first; item photos sync in the final phase. |

---

## Technical approach

### One sync technology: CKSyncEngine

| Option | Household sharing | Verdict |
|---|---|---|
| SwiftData + CloudKit | Not supported (`ModelConfiguration.CloudKitDatabase` is private-only) | Ruled out |
| SwiftData sync + a manual CKShare layer | Possible, fragile | Two sync systems over one store — avoid |
| Core Data + `NSPersistentCloudKitContainer` sharing | Supported | Requires rewriting the model layer into Core Data; sync is opaque and hard to debug |
| **CKSyncEngine** (iOS 17+) | Supported (private + shared databases) | **Chosen.** Keeps our Codable models and own persistence; the engine handles scheduling, push, retries, and change tokens. We own record mapping and conflict rules. |

### Data layout

- **One custom record zone per household**, `Household`, in the owner's private database.
- **Zone-wide sharing:** `CKShare(recordZoneID:)` shares the entire zone. No root/child record references; anything added to the zone is shared automatically. (Also avoids the root-record `CKShare(rootRecord:)` path, which has had iOS 26.x regressions reported.)
- **One CKRecord per object** (never a single blob, which would make every edit overwrite the whole list):

```
HouseholdInfo  — libraryLanguage, name                       (one record)
Item           — name, inventoryTagID, shoppingTagID, sortOrder, hasImage, modifiedAt
Section        — kind (inventory|shopping), title, sortOrder, modifiedAt
ShoppingEntry  — itemID, quantity, isChecked, addedAt, modifiedAt
SavedList      — name, sortOrder, lines (encoded), modifiedAt
ItemPhoto      — itemID, asset (CKAsset)                     (final phase)
```

- **Record names are our existing UUIDs**, so local IDs and CloudKit IDs never drift. (Backups already preserve item IDs.)
- **Each local object stores its CKRecord system fields** (archived change tag) so saves are conflict-aware.

### Engines

| User | Engine(s) |
|---|---|
| Solo / household owner | One CKSyncEngine on the **private** database (owns the `Household` zone) |
| Household member | One CKSyncEngine on the **shared** database (the owner's zone, via the share) |

Phase 1 (own devices) and Phase 2 (household) use the **same zone and record code**; Phase 2 only adds sharing and the shared-database engine.

### Conflict rules (v1)

| Case | Rule |
|---|---|
| Most fields | Last write wins by `modifiedAt` |
| Shopping quantity / checked | Per field, last write wins |
| Same item added twice | Merge into one entry, sum quantities |
| Delete vs edit | Delete wins; deleting an item removes its shopping entries and saved-list lines |
| Reorder | Last write wins on `sortOrder` |
| Language reset (owner) | Owner deletes all zone records, reseeds, updates `HouseholdInfo.libraryLanguage`; members apply it on next fetch |

No CRDTs unless real-world use shows a need.

### Unchanged

- Share extension + Shortcuts intent keep enqueueing ops in the App Group; the host app applies them (and from Phase 1, syncs them).
- Backup export/import stays as the manual escape hatch.

---

## Phases

### Phase 0 — Storage move (no cloud) → ship as 1.2

Goal: get off UserDefaults and give sync a single mutation path, with **no visible behavior change**. Shipping this alone proves the migration on real installs before CloudKit is involved.

**0a. Library files**
- Store each language's library as JSON in the App Group container: `Library/english.json`, `Library/hebrew.json` (atomic writes).
- First launch after update: if the files don't exist, read the existing `grocery.v3.english` / `grocery.v3.hebrew` UserDefaults data, write the files, then continue from files.
- **Dual-write for one release:** 1.2 keeps writing UserDefaults too, so a fallback is always current. 1.3 removes it.
- If a file fails to decode: don't overwrite it; move it aside (`*.corrupt-<timestamp>.json`) and fall back to the UserDefaults copy.
- Share-extension catalog snapshot keeps working unchanged.

**0b. One mutation path in `GroceryStore`**
- Replace the duplicated `if hebrew { … } else { … }` branches (36 sites) with one helper that edits the *active* bundle, then sorts, saves, and republishes.
- Public API unchanged — no view changes.
- This becomes the single place where Phase 1 records "these objects changed" for sync.

**0c. Photos untouched** — still JPEGs in Application Support.

**Test before shipping**
- Upgrade: install 1.1 with real data (items, sections, list, saved lists, photos), install the 1.2 build over it, verify everything is intact; relaunch twice.
- Fresh install: seeded library appears in both languages.
- Language switch, clear library, reset to defaults.
- Backup export → import round-trip.
- Share extension and Shortcuts import.
- Kill the app right after an edit; relaunch; edit is there.

### Phase 1 — Sync across your own devices

- Apple setup: iCloud capability + CloudKit container **`iCloud.com.byteloft.apps.shoplister`** (container IDs are permanent), Push Notifications, Background Modes → Remote notifications.
- `SyncService` wrapping one CKSyncEngine (private DB), persisted engine state, `Household` zone.
- Map local objects ↔ CKRecords; send changes from the Phase 0b mutation path; apply fetched changes; conflict rules above; tombstones for deletes.
- First enable: upload the active-language library into the zone.
- Settings: iCloud status, last synced time, "Sync now", error state.
- **Done when:** an edit on one device appears on another with the same Apple ID.

### Phase 2 — Household sharing

- Create household = create `CKShare(recordZoneID:)` for the zone; invite with `UICloudSharingController`.
- Accept invite (`CKShare.Metadata`); prompt before replacing the member's local library (offer backup first); start the shared-DB engine.
- Leave (member), stop sharing / delete household (owner).
- Owner-only language change with a household-wide warning; members see it read-only.
- Settings → **Household** section: members, invite, leave/delete.
- **Done when:** two different Apple IDs see each other's changes.

### Phase 3 — Photos and polish → App Store

- Item photos as CKAssets (compressed), downloaded lazily.
- Share extension / Shortcuts ops flow through sync.
- Offline messaging ("changes will sync when you're online").
- Deploy CloudKit schema Development → Production.
- Update App Privacy answers (data now stored in the user's iCloud and shared with household members) and `privacy.html`.

---

## Testing setup

- Paid Apple Developer Program membership (CloudKit isn't available to free personal teams).
- **Phase 1:** two devices on the same Apple ID (or a device + Simulator signed into iCloud).
- **Phase 2:** a second Apple ID (a regular one — App Store sandbox testers are for purchases, not iCloud). Cheapest: two Simulators on one Mac, each signed into a different Apple ID; confirm on real devices.
- Xcode debug builds use the CloudKit **Development** environment; TestFlight/App Store use **Production**.
- CloudKit Console (icloud.developer.apple.com): inspect records/zones, logs, reset Development data.
- Final check: TestFlight build used by a real household on a real shopping trip.

**Scenario checklist (each phase):** simultaneous edits on two devices · offline edits then reconnect · app killed mid-sync · delete on one device while the other checks it off · iCloud signed out · member leaves · owner deletes household · owner changes language.

---

## Risks

| Risk | Mitigation |
|---|---|
| Data loss during storage migration | Phase 0 ships alone; dual-write fallback; corrupt files moved aside, never overwritten |
| iOS 26 CloudKit sharing regressions | Zone-wide sharing; budget real-device testing with two Apple IDs |
| Destructive household language reset | Owner-only, strong confirmation, offer backup first |
| `GroceryStore` size / EN–HE duplication | Phase 0b collapses it before sync code is added |
| Photo bandwidth / storage | Compress, lazy download, final phase only |

---

## Checklist

- [x] Phase 0a: library JSON files + migration + dual-write
- [x] Phase 0b: single mutation path in `GroceryStore`
- [x] Phase 0: test pass
- [ ] Phase 0: ship 1.2
- [ ] 1.3: remove the UserDefaults dual-write and the "prefer a differing UserDefaults copy" check in `GroceryStore.loadBundle`
- [ ] Apple setup: CloudKit container `iCloud.com.byteloft.apps.shoplister`, push, background modes
- [ ] Phase 1: CKSyncEngine (private DB), record mapping, conflict rules, Settings sync status
- [ ] Phase 2: zone share, invite/accept/leave/delete, owner-only language, Household settings
- [ ] Phase 3: photo sync, extension through sync, schema to Production, privacy updates
