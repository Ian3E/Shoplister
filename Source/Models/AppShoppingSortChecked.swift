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

enum AppShoppingPlusOpensAllItems {
    /// When **on**, the shopping list’s + button opens All Items instead of the pull-to-add sheet.
    /// Pulling down on the list always opens pull-to-add. Default **off**.
    static let storageKey = "app.shoppingPlusOpensAllItems"
}

enum AppShoppingConfirmClearWhenAllChecked {
    /// When **on**, checking the last item asks to keep or clear the list; when **off**, the list clears automatically.
    static let storageKey = "app.shoppingConfirmClearWhenAllChecked"
}
