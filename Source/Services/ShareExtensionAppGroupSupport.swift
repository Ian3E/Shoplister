import Foundation

extension Notification.Name {
    /// Posted when the main app merges shopping ops written by the share extension (`userInfo` may include `addedOpCount`).
    static let shareExtensionShoppingOpsMerged = Notification.Name("ShareExtension.shoppingOpsMerged")
    /// Posted after pending shopping ops are written to the app group (Shortcuts); host should merge into its live store.
    static let shareExtensionPendingShoppingOpsEnqueued = Notification.Name("ShareExtension.pendingShoppingOpsEnqueued")
}

enum ShareExtensionAppGroupSupport {
    static let appGroupIdentifier = "group.com.byteloft.apps.shoplister"
    static let catalogSnapshotFileName = "share_catalog_snapshot.json"
    static let pendingShoppingOpsFileName = "pending_share_shopping_ops.json"

    static let mergedOpCountUserInfoKey = "addedOpCount"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(catalogSnapshotFileName, isDirectory: false)
    }

    private static var pendingOpsURL: URL? {
        containerURL?.appendingPathComponent(pendingShoppingOpsFileName, isDirectory: false)
    }

    private struct SnapshotItem: Codable {
        let id: UUID
        let name: String
    }

    private struct SnapshotRoot: Codable {
        var english: [SnapshotItem]
        var hebrew: [SnapshotItem]
    }

    private struct PendingOp: Codable {
        let itemID: UUID
        let quantity: Int
    }

    private struct PendingOpsEnvelope: Codable {
        var ops: [PendingOp]
    }

    /// Writes both language catalogs so the share extension can match lines without running the host app.
    static func writeCatalogSnapshotToAppGroup(englishCatalog: [GroceryItem], hebrewCatalog: [GroceryItem]) {
        guard let url = snapshotURL else { return }
        let root = SnapshotRoot(
            english: englishCatalog.map { SnapshotItem(id: $0.id, name: $0.name) },
            hebrew: hebrewCatalog.map { SnapshotItem(id: $0.id, name: $0.name) }
        )
        guard let data = try? JSONEncoder().encode(root) else { return }
        try? data.write(to: url, options: .atomic)
        mirrorCatalogLanguagePreferenceToSuite()
    }

    /// Keeps `UserDefaults(suiteName:)` in sync so the extension matches using the same catalog language as the host.
    static func mirrorCatalogLanguagePreferenceToSuite() {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let raw = UserDefaults.standard.string(forKey: AppContentLanguage.storageKey) ?? AppContentLanguage.english.rawValue
        suite.set(raw, forKey: AppContentLanguage.storageKey)
    }

    /// Matches share/Shortcuts text and writes pending ops for the host to merge (same path as the share sheet).
    static func enqueuePendingShoppingOps(matchingText text: String) -> Int {
        let ops = pendingShoppingOps(matchingText: text)
        guard !ops.isEmpty else { return 0 }
        writePendingShoppingOps(ops)
        return ops.count
    }

    private static func pendingShoppingOps(matchingText text: String) -> [PendingOp] {
        guard let pool = catalogPoolFromSnapshot() else { return [] }
        var ordered: [UUID] = []
        var counts: [UUID: Int] = [:]

        for fragment in CatalogSearchNormalization.shareImportItemFragments(from: text) {
            let matches = pool.filter { item in
                CatalogSearchNormalization.localizedCaseInsensitiveEquals(
                    item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    fragment
                )
            }
            for item in matches {
                if counts[item.id] == nil {
                    ordered.append(item.id)
                }
                counts[item.id, default: 0] += 1
            }
        }

        return ordered.compactMap { id in
            guard let qty = counts[id], qty > 0 else { return nil }
            return PendingOp(itemID: id, quantity: qty)
        }
    }

    private static func writePendingShoppingOps(_ ops: [PendingOp]) {
        guard !ops.isEmpty, let url = pendingOpsURL else { return }
        var combined = ops
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode(PendingOpsEnvelope.self, from: data),
           !existing.ops.isEmpty
        {
            combined = existing.ops + ops
        }
        guard let encoded = try? JSONEncoder().encode(PendingOpsEnvelope(ops: combined)) else { return }
        try? encoded.write(to: url, options: .atomic)
        NotificationCenter.default.post(name: .shareExtensionPendingShoppingOpsEnqueued, object: nil)
    }

    private static func catalogPoolFromSnapshot() -> [SnapshotItem]? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SnapshotRoot.self, from: data)
        else { return nil }
        let raw = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: AppContentLanguage.storageKey)
        let language = AppContentLanguage(rawValue: raw ?? "") ?? .english
        return language == .hebrew ? snapshot.hebrew : snapshot.english
    }

    /// Applies shopping additions written by the share extension, then removes the ops file.
    /// - Returns: Number of `addToShopping` calls applied (each op is one call, quantity folded into `addToShopping`).
    @MainActor
    static func mergePendingShoppingOpsFromAppGroup(into store: GroceryStore) -> Int {
        guard let url = pendingOpsURL, FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let data = try? Data(contentsOf: url) else {
            try? FileManager.default.removeItem(at: url)
            return 0
        }
        try? FileManager.default.removeItem(at: url)
        guard let envelope = try? JSONDecoder().decode(PendingOpsEnvelope.self, from: data), !envelope.ops.isEmpty else { return 0 }
        let validOps = envelope.ops.filter { store.item(for: $0.itemID) != nil }
        guard !validOps.isEmpty else { return 0 }
        var applied = 0
        for (index, op) in validOps.enumerated() {
            let last = index == validOps.count - 1
            store.addToShopping(itemID: op.itemID, quantity: op.quantity, playHaptic: last)
            applied += 1
        }
        if applied > 0 {
            NotificationCenter.default.post(
                name: .shareExtensionShoppingOpsMerged,
                object: nil,
                userInfo: [mergedOpCountUserInfoKey: applied]
            )
        }
        return applied
    }
}
