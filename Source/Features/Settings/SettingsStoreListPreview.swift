import SwiftUI
import UIKit

/// Store-list walkthrough preview for Settings screens (text size, theme).
struct SettingsStoreListPreview: View {
    let textSize: AppTextSize

    @AppStorage(AppContentLanguage.storageKey) private var catalogLanguageRaw: String = AppContentLanguage.english.rawValue

    private var catalogLanguage: AppContentLanguage {
        AppContentLanguage(rawValue: catalogLanguageRaw) ?? .english
    }

    /// Height of the demo list rows and section headers (medium scale).
    static func contentHeight(for textSize: AppTextSize) -> CGFloat {
        contentHeight(for: textSize, catalogLanguage: .english)
    }

    static func contentHeight(for textSize: AppTextSize, catalogLanguage: AppContentLanguage) -> CGFloat {
        let scale = textSize.listSpacingScale
        let titleLineHeight = UIFont.preferredFont(forTextStyle: .title3).lineHeight * scale
        let separatorBlock = ShoppingListMetrics.gapAfterLastItem(scale: scale)
            + 1
            + ShoppingListMetrics.gapBeforeNextTitle(scale: scale)
        let headerVertical = ShoppingListMetrics.groupHeaderTopInset(scale: scale)
            + ShoppingListMetrics.groupHeaderBottomInset(scale: scale)
        let groupHeaderHeight = separatorBlock + titleLineHeight + headerVertical
        let itemRowHeight = ShoppingListMetrics.minimumListRowHeight(scale: scale)
        let sections = SettingsWalkthroughShoppingPreview.sections(for: catalogLanguage)
        let groupCount = CGFloat(sections.count)
        let itemCount = CGFloat(
            sections.reduce(0) { $0 + $1.rows.count }
        )
        return groupCount * groupHeaderHeight + itemCount * itemRowHeight
    }

    var body: some View {
        let spacingScale = textSize.listSpacingScale
        let previewSections = SettingsWalkthroughShoppingPreview.sections(for: catalogLanguage)
        VStack(spacing: 0) {
            ForEach(Array(previewSections.enumerated()), id: \.element.id) { index, section in
                SettingsStoreListPreviewGroupHeaderRow(
                    title: section.title,
                    showsVisibleGroupDivider: index > 0,
                    spacingScale: spacingScale
                )
                ForEach(section.rows) { row in
                    SettingsStoreListPreviewItemRow(spacingScale: spacingScale) {
                        ShoppingRowView(entry: row.entry, item: row.item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.shoppingListBackground)
        .environment(\.appContentLanguage, catalogLanguage)
        // Preview rows follow library language. Use SwiftUI direction only — the UIKit
        // list-chrome sync in `catalogListLayoutDirection()` can walk up and retarget the
        // theme color-picker List above this preview.
        .environment(
            \.layoutDirection,
            CatalogLayoutMirroring.catalogLayoutDirection(for: catalogLanguage)
        )
        .dynamicTypeSize(textSize.dynamicTypeSize)
        .allowsHitTesting(false)
    }
}

/// Item row chrome without `List` (host list cannot override draft `listSpacingScale` row floor).
struct SettingsStoreListPreviewItemRow<Content: View>: View {
    let spacingScale: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        let insets = ShoppingListMetrics.itemRowInsets(scale: spacingScale)
        content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(insets)
            .frame(
                minHeight: ShoppingListMetrics.minimumListRowHeight(scale: spacingScale),
                alignment: .leading
            )
            .background(Color.shoppingListBackground)
    }
}

struct SettingsStoreListPreviewGroupHeaderRow: View {
    let title: String
    let showsVisibleGroupDivider: Bool
    let spacingScale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            CatalogGroupHeaderSeparatorPrefix(
                showsVisibleDivider: showsVisibleGroupDivider,
                spacingScale: spacingScale
            )
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(CatalogGroupHeaderChrome.titleFont)
                    .foregroundStyle(CatalogGroupHeaderChrome.titleColor)
                Spacer(minLength: 0)
                previewDisclosureChevron(expanded: true, edgeChevron: .trailing)
                    .frame(width: ShoppingListChrome.chevronColumnWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(ShoppingListMetrics.groupHeaderRowInsets(scale: spacingScale))
        .background(Color.shoppingListBackground)
    }

    private func previewDisclosureChevron(expanded: Bool, edgeChevron: HorizontalEdge) -> some View {
        Image(systemName: "chevron.down")
            .font(CatalogGroupHeaderChrome.titleFont)
            .foregroundStyle(CatalogGroupHeaderChrome.titleColor)
            .rotationEffect(
                .degrees(
                    expanded
                        ? 0
                        : (edgeChevron == .leading ? 90 : -90)
                )
            )
    }
}

enum SettingsWalkthroughShoppingPreview {
    struct Section: Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    struct Row: Identifiable {
        let id: UUID
        let entry: ShoppingEntry
        let item: GroceryItem
    }

    static let englishSections: [Section] = [
        Section(
            id: "produce",
            title: "Produce",
            rows: [
                row(name: "Tomatoes", quantity: 3),
                row(name: "Cucumbers", quantity: 4),
            ]
        ),
        Section(
            id: "dairy",
            title: "Dairy & Eggs",
            rows: [
                row(name: "Milk", quantity: 2),
                row(name: "Eggs", quantity: 1, isChecked: true),
                row(name: "Cream cheese", quantity: 1, isChecked: true),
            ]
        ),
        Section(
            id: "bakery",
            title: "Bakery",
            rows: [
                row(name: "Bagels", quantity: 1),
            ]
        ),
    ]

    static let hebrewSections: [Section] = [
        Section(
            id: "produce",
            title: "ירקות ופירות",
            rows: [
                row(name: "עגבניות", quantity: 3),
                row(name: "מלפפונים", quantity: 4),
            ]
        ),
        Section(
            id: "dairy",
            title: "מוצרי חלב וביצים",
            rows: [
                row(name: "חלב", quantity: 2),
                row(name: "ביצים", quantity: 1, isChecked: true),
                row(name: "גבינת שמנת", quantity: 1, isChecked: true),
            ]
        ),
        Section(
            id: "bakery",
            title: "מאפייה",
            rows: [
                row(name: "פיתות", quantity: 1),
            ]
        ),
    ]

    static func sections(for language: AppContentLanguage) -> [Section] {
        switch language {
        case .english: return englishSections
        case .hebrew: return hebrewSections
        }
    }

    static let sections: [Section] = englishSections

    private static func row(name: String, quantity: Int, isChecked: Bool = false) -> Row {
        let itemID = previewItemID(name)
        let entry = ShoppingEntry(
            id: previewEntryID(name),
            itemID: itemID,
            quantity: quantity,
            isChecked: isChecked,
            addedAt: previewAddedAt(name)
        )
        let item = GroceryItem(
            id: itemID,
            name: name,
            inventoryTagID: previewPlaceholderTagID,
            shoppingTagID: previewPlaceholderTagID
        )
        return Row(id: itemID, entry: entry, item: item)
    }

    private static let previewPlaceholderTagID = UUID(uuidString: "A0A0A0A0-0000-4000-8000-000000000001")!

    private static func previewItemID(_ name: String) -> UUID {
        switch name {
        case "Bagels", "פיתות": return UUID(uuidString: "B0010001-0001-4001-8001-000000000001")!
        case "Milk", "חלב": return UUID(uuidString: "B0010001-0001-4001-8001-000000000002")!
        case "Eggs", "ביצים": return UUID(uuidString: "B0010001-0001-4001-8001-000000000003")!
        case "Tomatoes", "עגבניות": return UUID(uuidString: "B0010001-0001-4001-8001-000000000004")!
        case "Cucumbers", "מלפפונים": return UUID(uuidString: "B0010001-0001-4001-8001-000000000005")!
        case "Cream cheese", "גבינת שמנת": return UUID(uuidString: "B0010001-0001-4001-8001-000000000006")!
        default: return UUID()
        }
    }

    private static func previewEntryID(_ name: String) -> UUID {
        switch name {
        case "Bagels", "פיתות": return UUID(uuidString: "E0010001-0001-4001-8001-000000000001")!
        case "Milk", "חלב": return UUID(uuidString: "E0010001-0001-4001-8001-000000000002")!
        case "Eggs", "ביצים": return UUID(uuidString: "E0010001-0001-4001-8001-000000000003")!
        case "Tomatoes", "עגבניות": return UUID(uuidString: "E0010001-0001-4001-8001-000000000004")!
        case "Cucumbers", "מלפפונים": return UUID(uuidString: "E0010001-0001-4001-8001-000000000005")!
        case "Cream cheese", "גבינת שמנת": return UUID(uuidString: "E0010001-0001-4001-8001-000000000006")!
        default: return UUID()
        }
    }

    private static func previewAddedAt(_ name: String) -> Date {
        let interval: TimeInterval
        switch name {
        case "Bagels", "פיתות": interval = 0
        case "Milk", "חלב": interval = 1
        case "Eggs", "ביצים": interval = 2
        case "Tomatoes", "עגבניות": interval = 3
        case "Cucumbers", "מלפפונים": interval = 4
        case "Cream cheese", "גבינת שמנת": interval = 5
        default: interval = 0
        }
        return Date(timeIntervalSinceReferenceDate: 1_000_000 + interval)
    }
}
