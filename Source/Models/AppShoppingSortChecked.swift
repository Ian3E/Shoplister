import Foundation

enum AppShoppingSortChecked {
    /// When **on**, checked shopping rows are listed in a bottom **Checked** / **סומנו** section instead of staying in their tag groups.
    static let storageKey = "app.shoppingSortCheckedItems"
}

enum AppShoppingCollapseCompletedSections {
    /// When **on**, completed shopping sections start collapsed (checked pseudo-section or all-checked tag groups).
    static let storageKey = "app.shoppingCollapseCompletedSections"
}

enum AppShoppingHideStoreGroupNames {
    /// When **on**, the Store list keeps tag grouping and inter-section dividers but hides section header rows (including **Checked**).
    static let storageKey = "app.shoppingHideStoreGroupNames"
}

/// What tapping, or touching and holding, the shopping list + does (Settings → List → + Button).
/// Pulling down on the list always opens Add item, whatever is chosen here.
enum PlusButtonAction: String, CaseIterable, Identifiable {
    case menu
    case addItem
    case allItems
    case savedLists
    case createItem

    var id: String { rawValue }

    /// Same names as the + menu rows.
    var title: String {
        switch self {
        case .menu: return LocalizedCopy.menu
        case .addItem: return LocalizedCopy.addItem
        case .allItems: return LocalizedCopy.homeLibrary
        case .savedLists: return LocalizedCopy.savedLists
        case .createItem: return LocalizedCopy.createItem
        }
    }
}

enum AppPlusButtonTap {
    static let storageKey = "app.plusButtonTapAction"
    static let options: [PlusButtonAction] = [.addItem, .allItems]

    /// The old "Shortcut to All Items" switch (1.2) carries over: on → tap opens All Items.
    private static let legacyOpensAllItemsKey = "app.shoppingPlusOpensAllItems"

    static var defaultRawValue: String {
        UserDefaults.standard.bool(forKey: legacyOpensAllItemsKey)
            ? PlusButtonAction.allItems.rawValue
            : PlusButtonAction.addItem.rawValue
    }
}

enum AppPlusButtonHold {
    static let storageKey = "app.plusButtonHoldAction"
    static let options: [PlusButtonAction] = [.menu, .addItem, .allItems, .savedLists, .createItem]
    static let defaultRawValue = PlusButtonAction.menu.rawValue
}

enum AppShoppingConfirmClearWhenAllChecked {
    /// When **on**, checking the last item asks to keep or clear the list; when **off**, the list clears automatically.
    static let storageKey = "app.shoppingConfirmClearWhenAllChecked"
}
