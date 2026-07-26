import SwiftUI
import UIKit

/// Catalog list layout (Home / Store rows) follows **library language**.
/// App chrome follows **phone language** via the root `layoutDirection` in `GroceryListApp`.
enum CatalogLayoutMirroring {
    static func catalogLayoutDirection(for catalogLanguage: AppContentLanguage) -> LayoutDirection {
        catalogLanguage == .hebrew ? .rightToLeft : .leftToRight
    }

    /// Manual row/header mirroring when Hebrew catalog is shown inside an LTR layout subtree.
    static func usesManualCatalogMirror(
        catalogLanguage: AppContentLanguage,
        layoutDirection: LayoutDirection
    ) -> Bool {
        catalogLanguage == .hebrew && layoutDirection == .leftToRight
    }

    /// Catalog lists apply `catalogListLayoutDirection()`, so this follows catalog direction
    /// (and is false for Hebrew lists already in an RTL container).
    static func catalogListUsesManualMirror(for catalogLanguage: AppContentLanguage) -> Bool {
        usesManualCatalogMirror(
            catalogLanguage: catalogLanguage,
            layoutDirection: catalogLayoutDirection(for: catalogLanguage)
        )
    }

    static func rowContentAlignment(
        catalogLanguage: AppContentLanguage,
        layoutDirection: LayoutDirection
    ) -> Alignment {
        usesManualCatalogMirror(catalogLanguage: catalogLanguage, layoutDirection: layoutDirection)
            ? .trailing
            : .leading
    }

    /// Physical screen edge for the catalog quantity pill (UIKit coordinates).
    static func quantityPillOnPhysicalLeadingEdge(
        catalogLanguage: AppContentLanguage,
        layoutDirection: LayoutDirection
    ) -> Bool {
        layoutDirection == .rightToLeft
    }

    static func quantityPillOnPhysicalLeadingEdge(for catalogLanguage: AppContentLanguage) -> Bool {
        catalogLayoutDirection(for: catalogLanguage) == .rightToLeft
    }

    /// Phone layout and catalog layout disagree — UIKit `EditMode` chrome still follows the phone.
    static func phoneCatalogLayoutDirectionMismatched(for catalogLanguage: AppContentLanguage) -> Bool {
        catalogLayoutDirection(for: catalogLanguage) != AppSystemLocale.interfaceLayoutDirection
    }

    /// Keep UIKit semantic attribute aligned when phone/library disagree. Does not fix edit
    /// indent by itself (SwiftUI List ignores it for accessories); safe and transform-free.
    static func uiKitListSemanticContentAttribute(
        for catalogLanguage: AppContentLanguage
    ) -> UISemanticContentAttribute {
        guard phoneCatalogLayoutDirectionMismatched(for: catalogLanguage) else { return .unspecified }
        return catalogLayoutDirection(for: catalogLanguage) == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
    }

    static func applyUIKitListChromeDirectionIfNeeded(
        to scrollView: UIScrollView,
        catalogLanguage: AppContentLanguage
    ) {
        // Clear leftover flips from earlier mirror experiments.
        if scrollView.transform != .identity {
            scrollView.transform = .identity
        }

        let attribute = uiKitListSemanticContentAttribute(for: catalogLanguage)
        if scrollView.semanticContentAttribute != attribute {
            scrollView.semanticContentAttribute = attribute
        }

        if let collectionView = scrollView as? UICollectionView {
            for cell in collectionView.visibleCells {
                clearLegacyMirrorTransform(on: cell)
                if cell.semanticContentAttribute != attribute {
                    cell.semanticContentAttribute = attribute
                }
                if cell.contentView.semanticContentAttribute != attribute {
                    cell.contentView.semanticContentAttribute = attribute
                }
            }
        } else if let tableView = scrollView as? UITableView {
            for cell in tableView.visibleCells {
                clearLegacyMirrorTransform(on: cell)
                if cell.semanticContentAttribute != attribute {
                    cell.semanticContentAttribute = attribute
                }
                if cell.contentView.semanticContentAttribute != attribute {
                    cell.contentView.semanticContentAttribute = attribute
                }
            }
        }
    }

    private static func clearLegacyMirrorTransform(on cell: UIView) {
        if cell.transform != .identity {
            cell.transform = .identity
        }
        if let listCell = cell as? UICollectionViewCell {
            if listCell.contentView.transform != .identity {
                listCell.contentView.transform = .identity
            }
        } else if let tableCell = cell as? UITableViewCell {
            if tableCell.contentView.transform != .identity {
                tableCell.contentView.transform = .identity
            }
        }
    }
}

private struct CatalogListLayoutDirectionModifier: ViewModifier {
    @Environment(\.appContentLanguage) private var catalogLanguage

    func body(content: Content) -> some View {
        let direction = CatalogLayoutMirroring.catalogLayoutDirection(for: catalogLanguage)
        content
            .environment(\.layoutDirection, direction)
            // UITableView-backed List can keep a horizontal flip after RTL→LTR until remounted
            // (force-quit clears it). Identity on direction forces a clean layout pass.
            .id(direction)
            .background(CatalogListUIKitChromeDirectionSync(catalogLanguage: catalogLanguage))
    }
}

/// Clears legacy UIKit transforms and keeps semantic attributes aligned with catalog language.
private struct CatalogListUIKitChromeDirectionSync: UIViewRepresentable {
    let catalogLanguage: AppContentLanguage

    func makeUIView(context: Context) -> CatalogListUIKitChromeDirectionEnforcer {
        let view = CatalogListUIKitChromeDirectionEnforcer()
        view.catalogLanguage = catalogLanguage
        return view
    }

    func updateUIView(_ uiView: CatalogListUIKitChromeDirectionEnforcer, context: Context) {
        uiView.catalogLanguage = catalogLanguage
        DispatchQueue.main.async {
            uiView.applyIfNeeded()
        }
    }
}

private final class CatalogListUIKitChromeDirectionEnforcer: UIView {
    var catalogLanguage: AppContentLanguage = .english

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applyIfNeeded()
        }
    }

    func applyIfNeeded() {
        guard window != nil else { return }
        var ancestor: UIView? = superview
        for _ in 0..<8 {
            guard let container = ancestor else { break }
            if let collectionView = Self.firstDescendant(ofType: UICollectionView.self, in: container) {
                CatalogLayoutMirroring.applyUIKitListChromeDirectionIfNeeded(
                    to: collectionView,
                    catalogLanguage: catalogLanguage
                )
                return
            }
            if let tableView = Self.firstDescendant(ofType: UITableView.self, in: container) {
                CatalogLayoutMirroring.applyUIKitListChromeDirectionIfNeeded(
                    to: tableView,
                    catalogLanguage: catalogLanguage
                )
                return
            }
            ancestor = container.superview
        }
    }

    private static func firstDescendant<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = firstDescendant(ofType: type, in: subview) { return found }
        }
        return nil
    }
}

extension View {
    /// Home / Store list content: RTL for Hebrew library, LTR for English library.
    func catalogListLayoutDirection() -> some View {
        modifier(CatalogListLayoutDirectionModifier())
    }
}
