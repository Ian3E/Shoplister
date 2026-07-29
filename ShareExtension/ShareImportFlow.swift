import SwiftUI
import UIKit

// MARK: - Catalog language (mirrors `AppContentLanguage` raw values written by the host)

private enum ShareCatalogLanguage: String {
    case english
    case hebrew

    static func fromSuite() -> ShareCatalogLanguage {
        let raw = UserDefaults(suiteName: ShareAppGroup.identifier)?.string(forKey: ShareAppGroup.catalogLanguageKey)
        return ShareCatalogLanguage(rawValue: raw ?? "") ?? .english
    }
}

// MARK: - App group (must match `ShareExtensionAppGroupSupport` in the host target)

private enum ShareAppGroup {
    static let identifier = "group.com.byteloft.apps.shoplister"
    static let catalogSnapshotFileName = "share_catalog_snapshot.json"
    static let pendingShoppingOpsFileName = "pending_share_shopping_ops.json"
    static let catalogLanguageKey = "app.catalogContentLanguage"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

// MARK: - Snapshot + ops (JSON shape must match the host writer)

private struct SnapshotItem: Codable, Hashable {
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

// MARK: - Matching

private enum ShareLineMatcher {
    static func matchedRows(sharedText: String, snapshot: SnapshotRoot) -> [ShareImportRowModel] {
        let language = ShareCatalogLanguage.fromSuite()
        let pool = language == .hebrew ? snapshot.hebrew : snapshot.english

        var ordered: [UUID] = []
        var counts: [UUID: Int] = [:]
        var titles: [UUID: String] = [:]

        for fragment in CatalogSearchNormalization.shareImportItemFragments(from: sharedText) {
            let matches = pool.filter { item in
                CatalogSearchNormalization.localizedCaseInsensitiveEquals(
                    item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    fragment
                )
            }
            for item in matches {
                if counts[item.id] == nil {
                    ordered.append(item.id)
                    titles[item.id] = item.name
                }
                counts[item.id, default: 0] += 1
            }
        }

        return ordered.compactMap { id -> ShareImportRowModel? in
            guard let qty = counts[id], qty > 0, let title = titles[id] else { return nil }
            return ShareImportRowModel(id: UUID(), itemID: id, title: title, quantity: qty, isSelected: true)
        }
    }
}

// MARK: - SwiftUI review UI (checkbox style like the shopping list)

struct ShareImportRowModel: Identifiable, Equatable {
    let id: UUID
    let itemID: UUID
    let title: String
    let quantity: Int
    var isSelected: Bool
}

@MainActor
private final class ShareImportDraft: ObservableObject {
    @Published var rows: [ShareImportRowModel]

    init(rows: [ShareImportRowModel]) {
        self.rows = rows
    }

    var hasMatches: Bool { !rows.isEmpty }

    func toggle(rowID: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == rowID }) else { return }
        var next = rows
        next[i].isSelected.toggle()
        rows = next
    }
}

private struct ShareImportReviewRootView: View {
    @ObservedObject var draft: ShareImportDraft
    let catalogLanguage: ShareCatalogLanguage
    let onCancel: () -> Void
    let onAdd: () -> Void

    private var appCatalogLanguage: AppContentLanguage {
        catalogLanguage == .hebrew ? .hebrew : .english
    }

    var body: some View {
        NavigationStack {
            Group {
                if draft.hasMatches {
                    List {
                        ForEach(draft.rows) { row in
                            Button {
                                draft.toggle(rowID: row.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.blue)
                                        .symbolRenderingMode(.monochrome)
                                    Text(row.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if row.quantity > 1 {
                                        Text("\(row.quantity)")
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(row.isSelected ? .secondary : .primary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .catalogListRowSeparatorFullWidth(true)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.appContentLanguage, appCatalogLanguage)
                    .catalogListLayoutDirection()
                } else {
                    ContentUnavailableView(
                        LocalizedCopy.shareNoItemsFound,
                        systemImage: "magnifyingglass",
                        description: Text(LocalizedCopy.shareNoMatchesDescription)
                    )
                }
            }
            .navigationTitle(LocalizedCopy.addItems)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if draft.hasMatches {
                        Button(LocalizedCopy.cancel, action: onCancel)
                    } else {
                        Button(LocalizedCopy.done, action: onCancel)
                    }
                }
                if draft.hasMatches {
                    // Match RecipeApplySheet “Add” (saved list): prominent glass, blue tint.
                    // Keep Cancel on the default (non-tinted) cancellation style.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LocalizedCopy.add, action: onAdd)
                            .font(.body.weight(.semibold))
                            .buttonStyle(.glassProminent)
                            .tint(.blue)
                            .disabled(!draft.rows.contains(where: \.isSelected))
                    }
                }
            }
        }
    }
}

// MARK: - Present from the share view controller

enum ShareImportFlow {
    private static let snapshotPrefetchLock = NSLock()
    private static var prefetchedSnapshotRoot: SnapshotRoot?

    /// Decode the catalog snapshot on a background queue so it can overlap the share-sheet animation and `loadItem`.
    static func beginPrefetchCatalogSnapshot() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let root = loadCatalogSnapshotRoot() else { return }
            snapshotPrefetchLock.lock()
            prefetchedSnapshotRoot = root
            snapshotPrefetchLock.unlock()
        }
    }

    private static func loadCatalogSnapshotRoot() -> SnapshotRoot? {
        guard let snapURL = ShareAppGroup.containerURL?.appendingPathComponent(ShareAppGroup.catalogSnapshotFileName),
              let data = try? Data(contentsOf: snapURL),
              let snapshot = try? JSONDecoder().decode(SnapshotRoot.self, from: data)
        else { return nil }
        return snapshot
    }

    private static func takePrefetchedOrLoadCatalogSnapshotRoot() -> SnapshotRoot? {
        snapshotPrefetchLock.lock()
        let cached = prefetchedSnapshotRoot
        prefetchedSnapshotRoot = nil
        snapshotPrefetchLock.unlock()
        if let cached { return cached }
        return loadCatalogSnapshotRoot()
    }

    @MainActor
    static func presentReview(
        from viewController: ShareViewController,
        sharedText: String,
        onFinish: @escaping () -> Void
    ) {
        guard let snapshot = takePrefetchedOrLoadCatalogSnapshotRoot() else {
            let alert = UIAlertController(
                title: LocalizedCopy.libraryNotSyncedTitle,
                message: LocalizedCopy.libraryNotSyncedMessage,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: LocalizedCopy.ok, style: .default) { _ in onFinish() })
            viewController.present(alert, animated: true)
            return
        }

        let rows = ShareLineMatcher.matchedRows(sharedText: sharedText, snapshot: snapshot)

        let draft = ShareImportDraft(rows: rows)
        let root = ShareImportReviewRootView(
            draft: draft,
            catalogLanguage: ShareCatalogLanguage.fromSuite(),
            onCancel: {
                viewController.detachReviewHostingThenRun(onFinish)
            },
            onAdd: {
                let selected = draft.rows.filter(\.isSelected)
                guard !selected.isEmpty else { return }
                let envelope = PendingOpsEnvelope(ops: selected.map { PendingOp(itemID: $0.itemID, quantity: $0.quantity) })
                if let encoded = try? JSONEncoder().encode(envelope),
                   let opsURL = ShareAppGroup.containerURL?.appendingPathComponent(ShareAppGroup.pendingShoppingOpsFileName)
                {
                    try? encoded.write(to: opsURL, options: .atomic)
                }
                viewController.detachReviewHostingThenRun(onFinish)
            }
        )

        let host = UIHostingController(rootView: AnyView(root))
        viewController.attachReviewHosting(host)
    }
}
