# Shoplister

**Shoplister** is a grocery list and item library for iOS — English/Hebrew support, saved lists, and on-device backup.

The Xcode project is **`Shoplister.xcodeproj`**; the main app target and on-device name are **Shoplister**.

| | Value |
|---|---|
| Project | `Shoplister.xcodeproj` |
| Bundle ID | `com.ianengelman.shoplister` |
| Share extension | `com.ianengelman.shoplister.ShareExtension` |
| App Group | `group.com.ianengelman.shoplister` |

Register the App Group on both App IDs in your Apple Developer account if signing fails.

## Open & run

1. Open **`Shoplister.xcodeproj`** in Xcode.
2. Select the **Shoplister** scheme (main app).
3. Build and run on a simulator or device.

The app entry point is `ShoplisterApp` (`Source/ShoplisterApp.swift`). Resources such as `seed-library-backup-en.txt` / `seed-library-backup-he.txt` must be included in the app target for first-launch seeding.

## Layout

| Path | Role |
|------|------|
| `Source/` | Main app Swift code |
| `Shoplister/` | Info.plist, entitlements, assets, launch screen |
| `ShareExtension/` | Share extension |
| `Shoplister.xcodeproj` | Xcode project |

## Features

| Area | Notes |
|------|--------|
| **Home** | Catalog grouped by home location; toolbar search; add to shopping list |
| **Store** | Shopping list by store sections; check off items; clear checked / clear all |
| **Share extension** | Plain text shared into Shoplister is matched to the catalog; pending ops merge when the main app opens |
| **Settings** | Text size, appearance, language, backup/restore, etc. |

## Privacy policy (GitHub Pages)

The privacy policy lives at [`docs/privacy.html`](docs/privacy.html). The app links to:

**https://ian3e.github.io/Shoplister/privacy.html**

To publish after pushing to GitHub:

1. Open the repo on GitHub → **Settings** → **Pages**
2. Under **Build and deployment**, set **Source** to **Deploy from a branch**
3. Choose branch **main** and folder **/docs**
4. Save; GitHub will serve the site at `https://ian3e.github.io/Shoplister/`

Use the same URL in **App Store Connect** → App Privacy → Privacy Policy URL.

## App Store submission checklist

Complete these steps in [Apple Developer](https://developer.apple.com) and [App Store Connect](https://appstoreconnect.apple.com) after archiving from Xcode.

### Developer Portal (signing)

- App IDs: `com.ianengelman.shoplister` and `com.ianengelman.shoplister.ShareExtension`
- App Group `group.com.ianengelman.shoplister` enabled on **both** App IDs
- Provisioning profiles regenerate cleanly; **Product → Archive** succeeds for Release / Any iOS Device

### App Store Connect (new listing)

Create a **new app** for bundle ID `com.ianengelman.shoplister`.

| Field | Value |
|-------|--------|
| Privacy Policy URL | `https://ian3e.github.io/Shoplister/privacy.html` |
| Support | `support.shoplister@gmail.com` |

**App Privacy questionnaire (summary):**

- Grocery/library data: **not collected** (on device only)
- Photos: used for app functionality, not linked to identity, not for tracking
- No third-party SDK data collection

**Before submit:**

1. Age rating questionnaire (likely 4+)
2. iPhone portrait screenshots
3. Description, subtitle, keywords
4. Archive → Upload → TestFlight → Submit for Review
5. Export compliance: with `ITSAppUsesNonExemptEncryption` = false in Info.plist, answer **No** to custom encryption
