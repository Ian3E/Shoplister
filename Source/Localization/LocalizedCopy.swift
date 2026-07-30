import Foundation

/// Centralized UI copy for app chrome (not catalog item/section content).
enum LocalizedCopy {
    // MARK: - Common

    static var settings: String {
        String(localized: "Settings", comment: "Settings screen title")
    }

    static var done: String {
        String(localized: "Done", comment: "Done button")
    }

    static var cancel: String {
        String(localized: "Cancel", comment: "Cancel button")
    }

    static var save: String {
        String(localized: "Save", comment: "Save button")
    }

    static var delete: String {
        String(localized: "Delete", comment: "Delete button")
    }

    static var add: String {
        String(localized: "Add", comment: "Add button")
    }

    static var edit: String {
        String(localized: "Edit", comment: "Edit button")
    }

    static var create: String {
        String(localized: "Create", comment: "Create button")
    }

    static var continueAction: String {
        String(localized: "Continue", comment: "Continue button")
    }

    static var replace: String {
        String(localized: "Replace", comment: "Replace button for destructive import")
    }

    static var ok: String {
        String(localized: "OK", comment: "OK button")
    }

    static var menu: String {
        String(localized: "Menu", comment: "Menu accessibility label")
    }

    static var preview: String {
        String(localized: "Preview", comment: "Preview section header")
    }

    static func appVersionLabel(version: String, build: String) -> String {
        String(
            format: String(localized: "Version %@ (%@)", comment: "App version label in Settings About"),
            version,
            build
        )
    }

    static var export: String {
        String(localized: "Export", comment: "Export backup button")
    }

    static var importAction: String {
        String(localized: "Import", comment: "Import backup button")
    }

    static var backup: String {
        String(localized: "Backup", comment: "Backup section title and error alert title")
    }

    // MARK: - Settings

    static var settingsItemLibrary: String {
        tabLibrary
    }

    static var settingsAbout: String {
        String(localized: "About", comment: "About settings section title")
    }

    static var appName: String {
        String(localized: "Shoplister", comment: "App name on About screen")
    }

    static var privacyPolicy: String {
        String(localized: "Privacy Policy", comment: "Privacy Policy row on About screen")
    }

    static var opensInBrowser: String {
        String(localized: "Opens in Safari", comment: "Accessibility hint for external policy link")
    }

    static var contactSupport: String {
        String(localized: "Contact Support", comment: "Contact Support row on About screen")
    }

    static var appFeatures: String {
        String(localized: "Tips & features", comment: "Tips and feature guide row and screen title on About screen")
    }

    static var appFeaturesShoppingListSection: String {
        String(localized: "Shopping list", comment: "App features section header for shopping list features")
    }

    static var appFeaturesItemLibrarySection: String {
        String(localized: "Item library", comment: "App features section header for item library features")
    }

    static var appFeaturesSavedListsSection: String {
        String(localized: "Saved lists", comment: "App features section header for saved lists features")
    }

    static var appFeaturesPersonalizationSection: String {
        String(localized: "Personalization", comment: "App features section header for personalization features")
    }

    static var appFeaturesDataSharingSection: String {
        String(localized: "Data & sharing", comment: "App features section header for data and sharing features")
    }

    // MARK: App features — Shopping list

    static var appFeatureStoreSectionsTitle: String {
        String(localized: "Store sections", comment: "App feature title: shopping list grouped by store sections")
    }

    static var appFeatureStoreSectionsDescription: String {
        String(
            localized: "Items in your shopping list are grouped by store section, so you can shop aisle by aisle.",
            comment: "App feature description: store sections on shopping list"
        )
    }

    static var appFeaturePullDownToAddTitle: String {
        String(localized: "Pull down to add", comment: "App feature title: pull down to add items")
    }

    static var appFeaturePullDownToAddDescription: String {
        String(
            localized: "Pull down on the shopping list to search your library and quickly add items without leaving the list.",
            comment: "App feature description: pull down to add items"
        )
    }

    static var appFeatureCheckOffTitle: String {
        String(localized: "Check off", comment: "App feature title: check off shopping list items")
    }

    static var appFeatureCheckOffDescription: String {
        String(
            localized: "Tap a row to check it off, tap again to bring it back.",
            comment: "App feature description: check off shopping list items"
        )
    }

    static var appFeatureLongPressTitle: String {
        String(localized: "Long press", comment: "App feature title: long press shopping list row")
    }

    static var appFeatureLongPressDescription: String {
        String(
            localized: "Long press an item to adjust quantity. You can also quickly move the item to another store section, or edit/remove the item. If the item has a photo, you will see a preview.",
            comment: "App feature description: long press shopping list row"
        )
    }

    static var appFeaturePullUpClearCheckedTitle: String {
        String(localized: "Pull up to clear checked", comment: "App feature title: pull up to clear checked items")
    }

    static var appFeaturePullUpClearCheckedDescription: String {
        String(
            localized: "Pull up from the bottom of the list to clear all checked items in one gesture.",
            comment: "App feature description: pull up to clear checked"
        )
    }

    static var appFeaturePinchSectionsTitle: String {
        String(localized: "Pinch to collapse", comment: "App feature title: pinch to collapse store sections")
    }

    static var appFeaturePinchSectionsDescription: String {
        String(
            localized: "Pinch in on the list to collapse every store section; pinch out to expand them all.",
            comment: "App feature description: pinch to collapse store sections"
        )
    }

    static var appFeatureShakeUndoTitle: String {
        String(localized: "Shake to undo", comment: "App feature title: shake to undo a recent clear")
    }

    static var appFeatureShakeUndoDescription: String {
        String(
            localized: "After clearing checked items or the whole list, shake your device to undo. You can also use Undo in the menu.",
            comment: "App feature description: shake to undo a recent clear"
        )
    }

    static var appFeatureShareListDescription: String {
        String(
            localized: "Share your unchecked shopping list as plain text, grouped by store section, with quantities.",
            comment: "App feature description: share shopping list"
        )
    }

    static var appFeatureSortCheckedDescription: String {
        String(
            localized: "Moves checked items to the end of the shopping list instead of moving checked sections (enable in Settings).",
            comment: "App feature description: sort checked items"
        )
    }

    static var appFeatureHideSectionNamesDescription: String {
        String(
            localized: "Removes section headers to present a more condensed shopping list (enable in Settings).",
            comment: "App feature description: hide section names on shopping list"
        )
    }

    // MARK: App features — Item library

    static var appFeatureHomeSectionsTitle: String {
        String(localized: "Home sections", comment: "App feature title: home library sections")
    }

    static var appFeatureHomeSectionsDescription: String {
        String(
            localized: "Items in your home library are grouped by home sections, saving you time while preparing your shopping list.",
            comment: "App feature description: home library sections"
        )
    }

    static var appFeatureItemPhotosTitle: String {
        String(localized: "Item photos", comment: "App feature title: item photos")
    }

    static var appFeatureItemPhotosDescription: String {
        String(
            localized: "Add a photo to an item from your library or camera. Long-press an item in your shopping list to preview the photo.",
            comment: "App feature description: item photos"
        )
    }

    static var appFeatureSearchOrCreateTitle: String {
        String(localized: "Search or create", comment: "App feature title: search or create items")
    }

    static var appFeatureSearchOrCreateDescription: String {
        String(
            localized: "Search your library from Home or the Store. Create a new item when nothing matches.",
            comment: "App feature description: search or create items"
        )
    }

    static var appFeatureEditTitle: String {
        String(localized: "Edit", comment: "App feature title: edit item library")
    }

    static var appFeatureEditDescription: String {
        String(
            localized: "Edit or reorder items, select multiple items to move or delete, and manage sections from the Edit menu.",
            comment: "App feature description: edit item library"
        )
    }

    // MARK: App features — Saved lists

    static var appFeatureSaveListDescription: String {
        String(
            localized: "Save your current shopping list for quick reuse later, for example a recipe or starter list you use often.",
            comment: "App feature description: save shopping list as saved list"
        )
    }

    static var appFeatureAddSavedListTitle: String {
        String(localized: "Add saved list to shopping list", comment: "App feature title: add saved list to shopping list")
    }

    static var appFeatureAddSavedListDescription: String {
        String(
            localized: "Open a saved list, choose items, and add them to your shopping list.",
            comment: "App feature description: add saved list to shopping list"
        )
    }

    // MARK: App features — Personalization

    static var appFeatureThemeTitle: String {
        String(localized: "Theme", comment: "App feature title: theme")
    }

    static var appFeatureThemeDescription: String {
        String(
            localized: "Choose an accent color for buttons and checkboxes.",
            comment: "App feature description: theme"
        )
    }

    static var appFeatureAppearanceTextSizeTitle: String {
        String(localized: "Appearance & text size", comment: "App feature title: appearance and text size")
    }

    static var appFeatureAppearanceTextSizeDescription: String {
        String(
            localized: "Choose System, Light, or Dark mode and adjust text size in your shopping list and item library.",
            comment: "App feature description: appearance and text size"
        )
    }

    static var appFeatureAppIconBadgeDescription: String {
        String(
            localized: "Show a badge on the app icon with the count of unchecked shopping list items.",
            comment: "App feature description: app icon badge"
        )
    }

    static var appFeatureListTabBadgeDescription: String {
        String(
            localized: "Show a badge on the List tab with the count of unchecked shopping list items.",
            comment: "App feature description: List tab badge"
        )
    }

    static var appFeatureDeviceOptionsTitle: String {
        String(localized: "Device options", comment: "App feature title: device options")
    }

    static var appFeatureDeviceOptionsDescription: String {
        String(
            localized: "Lock to portrait orientation, disable haptic feedback, or optionally keep the screen awake while you shop.",
            comment: "App feature description: device options"
        )
    }

    // MARK: App features — Data & sharing

    static var appFeatureLibraryLanguageDescription: String {
        String(
            localized: "Switch the item library between English and Hebrew. App menus follow your phone language.",
            comment: "App feature description: library language"
        )
    }

    static var appFeatureBackupTitle: String {
        String(localized: "Backup export & import", comment: "App feature title: library backup")
    }

    static var appFeatureBackupDescription: String {
        String(
            localized: "Export your library, sections, recipes, and item photos as a zip file. Import to restore or move to another device.",
            comment: "App feature description: library backup export and import"
        )
    }

    static var appFeatureShareFromAppsTitle: String {
        String(localized: "Share from other apps", comment: "App feature title: share extension")
    }

    static var appFeatureShareFromAppsDescription: String {
        String(
            localized: "Share text from Safari, Messages, or other apps. Matching library items are added to your shopping list when you open Shoplister.",
            comment: "App feature description: share extension"
        )
    }

    static var appFeatureShortcutsImportTitle: String {
        String(localized: "Shortcuts import", comment: "App feature title: Shortcuts text import")
    }

    static var appFeatureShortcutsImportDescription: String {
        String(
            localized: "Use the Import Text to Shopping List shortcut to add items when each line matches a library item name.",
            comment: "App feature description: Shortcuts text import"
        )
    }

    static var libraryLanguage: String {
        String(localized: "Library language", comment: "Library language picker label")
    }

    static var libraryLanguageFooter: String {
        String(
            localized: "App menus follow your phone language. Changing the library language replaces your library and sections with the defaults and clears your shopping list.",
            comment: "Footer under library language picker"
        )
    }

    static var autoExpandQuantityPicker: String {
        String(localized: "Auto-expand quantity picker", comment: "Auto-expand quantity picker toggle")
    }

    static var autoExpandQuantityPickerFooter: String {
        String(
            localized: "When you add an item, expand the quantity controls. Turn off to expand only when you tap the quantity pill.",
            comment: "Footer under auto-expand quantity picker toggle"
        )
    }

    static var shoppingListSectionTitle: String {
        tabList
    }

    static var sortCheckedItems: String {
        String(localized: "Sort checked items", comment: "Sort checked items toggle")
    }

    static var hideSectionNames: String {
        String(localized: "Hide section names", comment: "Hide section names toggle")
    }

    static var confirmBeforeClearingList: String {
        String(localized: "Confirm before clearing list", comment: "Confirm before clearing list toggle")
    }

    static var sortCheckedItemsFooter: String {
        String(
            localized: "Moves checked items to the end of the shopping list.",
            comment: "Footer under sort checked items toggle"
        )
    }

    static var collapseCompletedSections: String {
        String(localized: "Collapse completed sections", comment: "Collapse completed sections toggle")
    }

    static var collapseCompletedSectionsFooter: String {
        String(
            localized: "Collapses completed sections by default.",
            comment: "Footer under collapse completed sections toggle"
        )
    }

    static var hideSectionNamesFooter: String {
        String(
            localized: "Removes section headers to present a more condensed shopping list.",
            comment: "Footer under hide section names toggle"
        )
    }

    static var confirmBeforeClearingListFooter: String {
        String(
            localized: "Asks to keep or clear the shopping list after all items are checked.",
            comment: "Footer under confirm before clearing list toggle"
        )
    }

    static var shoppingListSectionFooter: String {
        String(
            localized: "Sort checked items moves checked items to the end of the list. Collapse completed sections collapses finished sections by default. Hide section names removes section headers to present a more condensed list. Confirm before clearing list asks to keep or clear the list after all items are checked.",
            comment: "Footer under shopping list settings toggles"
        )
    }

    static var listTabBadge: String {
        String(localized: "List tab badge", comment: "List tab badge toggle")
    }

    static var listTabBadgeFooter: String {
        String(
            localized: "When on, the List tab shows how many shopping list items are still unchecked.",
            comment: "Footer under List tab badge toggle"
        )
    }

    static var appIconBadge: String {
        String(localized: "App icon badge", comment: "App icon badge toggle")
    }

    static var appIconBadgeFooter: String {
        String(
            localized: "When on, the app icon shows how many shopping list items are still unchecked. You may be asked to allow notifications so the badge can appear.",
            comment: "Footer under app icon badge toggle"
        )
    }

    static var appearance: String {
        String(localized: "Appearance", comment: "Appearance section header and picker label")
    }

    static var theme: String {
        String(localized: "Theme", comment: "Theme navigation title and settings row")
    }

    static var textSize: String {
        String(localized: "Text size", comment: "Text size navigation title and settings row")
    }

    static var device: String {
        String(localized: "Device settings", comment: "Device behavior settings row and navigation title")
    }

    static var lockPortrait: String {
        String(localized: "Lock portrait", comment: "Lock portrait orientation toggle")
    }

    static var hapticFeedback: String {
        String(localized: "Haptic feedback", comment: "Haptic feedback toggle")
    }

    static var disableAutoLock: String {
        String(localized: "Disable auto-lock", comment: "Disable auto-lock toggle")
    }

    static var changeLibraryLanguageAlertTitle: String {
        String(localized: "Change library language?", comment: "Alert title when changing library language")
    }

    static var changeLanguage: String {
        String(localized: "Change language", comment: "Destructive confirmation button for changing library language")
    }

    static var changeLibraryLanguageMessage: String {
        String(
            localized: "This replaces your item library and sections with the defaults for the new language and clears your shopping list. Items you added or edited will be deleted. This cannot be undone.",
            comment: "Alert message when changing library language"
        )
    }

    static var clearLibrary: String {
        String(localized: "Clear library", comment: "Destructive button to clear the item library")
    }

    static var clearLibraryFooter: String {
        String(
            localized: "This will delete all library items and sections and cannot be undone.",
            comment: "Footer under clear library button in item library settings"
        )
    }

    static var clearLibraryAlertTitle: String {
        String(localized: "Clear library", comment: "Alert title when clearing the item library")
    }

    static var clearLibraryAlertMessage: String {
        clearLibraryFooter
    }

    static var exportBackupExplainer: String {
        String(
            localized: "Exports your library, sections, recipes, and item photos in a zip file that can be imported later.",
            comment: "Export backup confirmation alert message"
        )
    }

    static var importBackupExplainer: String {
        String(
            localized: "This will delete and replace all library items, sections, and photos for this language and cannot be undone.",
            comment: "Import backup confirmation alert message"
        )
    }

    static var importComplete: String {
        String(localized: "Import complete", comment: "Import success alert title")
    }

    static var importSuccessMessage: String {
        String(
            localized: "Your library and sections were imported successfully.",
            comment: "Import success alert message"
        )
    }

    static var utf8ReadError: String {
        String(
            localized: "The file could not be read as UTF-8 text.",
            comment: "Error when import file is not valid UTF-8"
        )
    }

    // MARK: - Store (shopping list)

    static var shoppingListTitle: String {
        String(localized: "Shopping list", comment: "Shopping list navigation principal title")
    }

    static var shoppingListEmptyTitleAllDone: String {
        String(localized: "Your shopping list is empty", comment: "Empty shopping list overlay title")
    }

    static var shoppingListEmptyAddHintTapPrefix: String {
        String(
            localized: "Tap",
            comment: "Empty shopping add hint before Items tab symbol"
        )
    }

    static var shoppingListEmptyAddHintBrowseSuffix: String {
        String(
            localized: "to browse all items",
            comment: "Empty shopping add hint after Items tab symbol"
        )
    }

    static var shoppingListEmptyAddHintPullDownPrefix: String {
        String(
            localized: "Pull down or tap",
            comment: "Empty shopping add hint before plus symbol"
        )
    }

    static var shoppingListEmptyAddHintPullDownSuffix: String {
        String(
            localized: "to add items",
            comment: "Empty shopping add hint after plus symbol"
        )
    }

    static var shoppingListEmptyAddHintAccessibility: String {
        String(
            localized: "Pull down or tap plus to add items. Tap the Items tab to browse all items.",
            comment: "Accessibility label for empty shopping add hint"
        )
    }

    static var shoppingListGesturesAccessibilityHint: String {
        String(
            localized: "Pull down at the top to add items. Pull up at the bottom to clear checked items. Pinch to collapse or expand all sections. Shake to undo a recent clear.",
            comment: "VoiceOver hint for shopping list gesture shortcuts"
        )
    }

    static var storeGesturesExplainerTitle: String {
        String(localized: "Shopping list gestures", comment: "Store gestures coach overlay title")
    }

    static var storeGesturesExplainerAccessibilityLabel: String {
        String(
            localized: "Shopping list gestures. Pull down to add items. Pull up to clear checked items. Long press a row to adjust quantity. Shake to undo a recent clear.",
            comment: "Store gestures coach overlay VoiceOver label"
        )
    }

    static func checkedSectionTitle(for catalogLanguage: AppContentLanguage) -> String {
        switch catalogLanguage {
        case .hebrew:
            return "סומנו"
        case .english:
            return String(localized: "Checked", comment: "Title for checked-items section when sort checked is on")
        }
    }

    static var checkedSectionTitle: String {
        checkedSectionTitle(for: .english)
    }

    static var clearShoppingListAlertTitle: String {
        String(localized: "Clear shopping list?", comment: "Clear shopping list alert title")
    }

    static var keepList: String {
        String(localized: "Keep List", comment: "Keep shopping list button when all items checked")
    }

    static var clearList: String {
        String(localized: "Clear list", comment: "Clear shopping list destructive button")
    }

    static var clearListTitleCase: String {
        String(localized: "Clear List", comment: "Clear List button title case variant")
    }

    static var allItemsCheckedClearMessage: String {
        String(
            localized: "Every item is checked. Remove all items from your shopping list?",
            comment: "Message when all shopping items are checked"
        )
    }

    static var clearShoppingListMessage: String {
        String(
            localized: "This will remove all items from your shopping list.",
            comment: "Message for clear all shopping list confirmation"
        )
    }

    static var clearChecked: String {
        String(localized: "Clear checked", comment: "Clear checked items menu item")
    }

    static var undoClearChecked: String {
        String(localized: "Undo clear checked", comment: "Undo clear checked items menu item")
    }

    static var undoClearList: String {
        String(localized: "Undo clear list", comment: "Undo clear shopping list menu item")
    }

    static var undo: String {
        String(localized: "Undo", comment: "Undo confirmation button")
    }

    static var undoClearCheckedConfirmTitle: String {
        String(localized: "Undo clear checked?", comment: "Shake undo clear checked alert title")
    }

    static var undoClearCheckedConfirmMessage: String {
        String(
            localized: "This will restore the checked items you just cleared.",
            comment: "Shake undo clear checked alert message"
        )
    }

    static var undoClearListConfirmTitle: String {
        String(localized: "Undo clear list?", comment: "Shake undo clear list alert title")
    }

    static var undoClearListConfirmMessage: String {
        String(
            localized: "This will restore your shopping list to how it was before you cleared it.",
            comment: "Shake undo clear list alert message"
        )
    }

    static var shareList: String {
        String(localized: "Share list", comment: "Share shopping list menu item")
    }

    static var saveList: String {
        String(localized: "Save list", comment: "Save unchecked shopping list menu item and alert title")
    }

    static var listName: String {
        String(localized: "List name", comment: "Saved list name text field placeholder when saving from Store")
    }

    static var listSaved: String {
        String(localized: "List saved", comment: "Brief confirmation after saving a shopping list")
    }

    // MARK: - Home (library)

    /// EXPERIMENT (tabs): short tab-bar label for the shopping list tab.
    static var tabList: String {
        String(localized: "List", comment: "Root tab bar label for the shopping list")
    }

    /// Short tab-bar label for the catalog tab.
    static var tabLibrary: String {
        String(localized: "Items", comment: "Root tab bar label for the catalog / all items tab")
    }

    static var homeLibrary: String {
        String(localized: "All items", comment: "Home catalog navigation principal title")
    }

    static var searchLibrary: String {
        String(localized: "Search items", comment: "Home catalog navigation principal title while searching")
    }

    static var editLibrary: String {
        String(localized: "Edit library", comment: "Home library title in reorder mode")
    }

    static var noItems: String {
        String(localized: "No items", comment: "Empty home library placeholder")
    }

    static var search: String {
        String(localized: "Search", comment: "Search field prompt in edit mode")
    }

    static var searchOrCreateItem: String {
        String(localized: "Search or create item", comment: "Home and store search field prompt")
    }

    static var noMatchingItemsFound: String {
        String(localized: "No matching items found", comment: "Search with no results")
    }

    static var typeToFilterItems: String {
        String(
            localized: "Type to filter items",
            comment: "Mid-screen hint when Home or pull-to-add search field is empty (no pinned results)"
        )
    }

    static var createItem: String {
        String(localized: "Create Item", comment: "Create item action and screen title")
    }

    static var sections: String {
        String(localized: "Sections", comment: "Sections toolbar menu title")
    }

    static var homeSections: String {
        String(localized: "Home sections", comment: "Home sections editor title")
    }

    static var storeSections: String {
        String(localized: "Store sections", comment: "Store sections editor title")
    }

    static var addItem: String {
        String(localized: "Add item", comment: "Add item toolbar button")
    }

    static var welcomeExplainerTitle: String {
        String(localized: "Welcome to Shoplister!", comment: "Fresh-install welcome explainer title")
    }

    static var welcomeExplainerItemSections: String {
        String(
            localized: "Each item in Shoplister has a\n**Home section** (where you keep it)\n**Store section** (where you buy it).",
            comment: "Fresh-install welcome explainer home and store section line"
        )
    }

    static var welcomeExplainerShoppingListGrouping: String {
        String(
            localized: "Your shopping list is organized by Store sections.",
            comment: "Fresh-install welcome explainer shopping list grouping line"
        )
    }

    static var welcomeExplainerHomeLibraryGrouping: String {
        String(
            localized: "Your item library is organized by Home sections.",
            comment: "Fresh-install welcome explainer home library grouping line"
        )
    }

    static var welcomeExplainerAccessibilityLabel: String {
        String(
            localized: "Welcome to Shoplister! Each item in Shoplister has a Home section (where you keep it) Store section (where you buy it). Your item library is organized by Home sections. Your shopping list is organized by Store sections.",
            comment: "Fresh-install welcome explainer VoiceOver label"
        )
    }

    static var firstShoppingItemExplainerCongratulations: String {
        String(localized: "Congratulations!", comment: "First shopping item explainer title")
    }

    static var firstShoppingItemExplainerFirstItemAdded: String {
        String(
            localized: "You have added your first item to your shopping list.",
            comment: "First shopping item explainer line after title"
        )
    }

    static var firstShoppingItemExplainerTapQuantityPrefix: String {
        String(localized: "Tap ", comment: "First shopping item explainer prefix before quantity pill")
    }

    static var firstShoppingItemExplainerTapQuantitySuffix: String {
        String(localized: "to adjust quantity.", comment: "First shopping item explainer suffix after quantity pill")
    }

    static var firstShoppingItemExplainerRemoveHint: String {
        String(
            localized: "Or tap the row again to remove the item from your shopping list.",
            comment: "First shopping item explainer remove hint"
        )
    }

    static var firstShoppingItemExplainerAccessibilityLabel: String {
        String(
            localized: "Congratulations! You have added your first item to your shopping list. Tap the quantity pill, then use plus or minus to adjust quantity. Or tap the row again to remove the item from your shopping list.",
            comment: "First shopping item explainer VoiceOver label"
        )
    }

    // MARK: - Recipes

    static var savedLists: String {
        String(localized: "Saved lists", comment: "Saved lists navigation title and Home toolbar button")
    }

    static var newRecipe: String {
        String(localized: "New recipe", comment: "New recipe menu item and editor title")
    }

    static var recipeName: String {
        String(localized: "Recipe name", comment: "Recipe name text field placeholder")
    }

    static var ingredients: String {
        String(localized: "Ingredients", comment: "Recipe ingredients section header")
    }

    static var addIngredient: String {
        String(localized: "Add ingredient", comment: "Add ingredient button in recipe editor")
    }

    static var addToList: String {
        String(localized: "Add to list", comment: "Add selected recipe ingredients to shopping list")
    }

    static var selectAll: String {
        String(localized: "Select all", comment: "Select all recipe ingredients")
    }

    static var deselectAll: String {
        String(localized: "Deselect all", comment: "Deselect all recipe ingredients")
    }

    static var recipesEmptyFooter: String {
        String(
            localized: "Saved shopping lists will appear here for quick access",
            comment: "Empty saved lists placeholder"
        )
    }

    static func deleteRecipeConfirmationTitle(name: String) -> String {
        String(
            format: String(
                localized: "Delete “%@”?",
                comment: "Delete recipe confirmation title; %@ is recipe name"
            ),
            name
        )
    }

    static var itemNotInLibrary: String {
        String(localized: "Item not in library", comment: "Recipe ingredient missing from catalog")
    }

    static var deleteSelected: String {
        String(localized: "Delete selected", comment: "Delete selected items toolbar button")
    }

    static func deleteItemsConfirmationTitle(count: Int) -> String {
        if count == 1 {
            return String(localized: "Delete 1 item?", comment: "Delete one item confirmation title")
        }
        return String(
            format: String(localized: "Delete %lld items?", comment: "Delete multiple items confirmation title"),
            count
        )
    }

    static var sectionOrganizeFooter: String {
        String(
            localized: "Add a section to organize items. New items default to Undefined until you assign a section.",
            comment: "Empty state in section editor; Undefined is the default section name in English catalog"
        )
    }

    // MARK: - Items

    static var newItem: String {
        createItem
    }

    static var editItem: String {
        String(localized: "Edit Item", comment: "Edit item screen title and overlay button")
    }

    static var nameField: String {
        String(localized: "Name", comment: "Item name text field placeholder")
    }

    static var sectionsHeader: String {
        String(localized: "Sections", comment: "Sections form section header")
    }

    /// New Item / Edit Item form footer for the Sections group (Home + Store pickers).
    static var itemSectionsFormFooter: String {
        String(
            localized: "Home is where you keep it. Store is where you buy it.",
            comment: "Form footer explaining Home vs Store section pickers"
        )
    }

    static var homeSectionLabel: String {
        String(localized: "Home", comment: "Home section picker label")
    }

    static var storeSectionLabel: String {
        String(localized: "Store", comment: "Store section picker label")
    }

    static var photo: String {
        String(localized: "Photo", comment: "Photo form section header")
    }

    static var chooseFromLibrary: String {
        String(localized: "Choose from Library", comment: "Choose photo from library button")
    }

    static var takePhoto: String {
        String(localized: "Take Photo", comment: "Take photo with camera button")
    }

    static var removePhoto: String {
        String(localized: "Remove Photo", comment: "Remove item photo button")
    }

    static var deleteItem: String {
        String(localized: "Delete item", comment: "Delete item button")
    }

    static var deleteThisItemAlertTitle: String {
        String(localized: "Delete this item?", comment: "Delete item confirmation alert title")
    }

    static func deleteItemMessage(itemName: String) -> String {
        String(
            format: String(
                localized: "“%@” will be removed from your library and shopping list.",
                comment: "Delete item confirmation message; %@ is the item name"
            ),
            itemName
        )
    }

    static var newSection: String {
        String(localized: "New section", comment: "New section menu item and alert title")
    }

    static var sectionName: String {
        String(localized: "Section name", comment: "Section name text field placeholder")
    }

    // MARK: - Menus

    static var editItemMenu: String {
        String(localized: "Edit item", comment: "Edit item context menu action")
    }

    static var moveItem: String {
        String(localized: "Move item", comment: "Move item context menu title")
    }

    static var deleteItemMenu: String {
        String(localized: "Delete item", comment: "Delete item context menu action")
    }

    static var removeItem: String {
        String(localized: "Remove item", comment: "Remove item from shopping list context menu")
    }

    // MARK: - Share extension

    static var addItems: String {
        String(localized: "Add items", comment: "Share extension navigation title")
    }

    static var shareNoItemsFound: String {
        String(localized: "No items found", comment: "Share extension empty state title")
    }

    static var shareNoMatchesDescription: String {
        String(
            localized: "None of the shared items matched your library.",
            comment: "Share extension empty state description"
        )
    }

    static var libraryNotSyncedTitle: String {
        String(localized: "Library not synced", comment: "Share extension alert when catalog snapshot missing")
    }

    static var libraryNotSyncedMessage: String {
        String(
            localized: "Open Shoplister once so your library can be shared with this extension.",
            comment: "Share extension alert message when catalog snapshot missing"
        )
    }

    // MARK: - Overlays

    static var noImage: String {
        String(localized: "No image", comment: "Photo preview overlay when item has no image")
    }

    // MARK: - Accessibility

    static func collapseSection(_ title: String) -> String {
        String(
            format: String(localized: "Collapse %@", comment: "Accessibility label to collapse a section; %@ is section title"),
            title
        )
    }

    static func expandSection(_ title: String) -> String {
        String(
            format: String(localized: "Expand %@", comment: "Accessibility label to expand a section; %@ is section title"),
            title
        )
    }

    static func expandSectionUncheckedSuffix(_ count: Int) -> String {
        String(
            format: String(localized: ", %lld unchecked", comment: "Accessibility suffix for collapsed section with unchecked count"),
            count
        )
    }

    static func itemsInLibrary(_ count: Int) -> String {
        String(
            format: String(localized: "%lld items", comment: "Item count under Item library title (total catalog count)"),
            count
        )
    }

    static func searchItemsFound(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 item found", comment: "Home search match count subheader (singular)")
        }
        return String(
            format: String(localized: "%lld items found", comment: "Home search match count subheader"),
            count
        )
    }

    static func homeLibraryAccessibilityLabel(title: String, itemCount: Int) -> String {
        String(
            format: String(
                localized: "%@, %lld items in library",
                comment: "Accessibility label for home catalog toolbar; first %@ is title, second is count"
            ),
            title,
            itemCount
        )
    }

    static func searchItemsFoundAccessibilityLabel(_ count: Int) -> String {
        searchItemsFound(count)
    }

    static func shoppingListAccessibilityLabel(subtitle: String) -> String {
        String(
            format: String(
                localized: "Shopping list, %@",
                comment: "Accessibility label for shopping list toolbar; %@ is remaining items subtitle"
            ),
            subtitle
        )
    }

    static func itemsRemaining(unchecked: Int, total: Int, hasAnyChecked: Bool) -> String {
        if !hasAnyChecked, total > 0 {
            return itemCount(total)
        }
        if unchecked == 1 {
            return String(localized: "1 item remaining", comment: "Shopping list subtitle when one item remains unchecked")
        }
        return String(
            format: String(localized: "%lld items remaining", comment: "Shopping list subtitle for remaining unchecked items"),
            unchecked
        )
    }

    static func itemCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 item", comment: "Singular item count")
        }
        return String(
            format: String(localized: "%lld items", comment: "Plural item count"),
            count
        )
    }

    static func addedItems(_ count: Int) -> String {
        String(
            format: String(localized: "Added %lld items", comment: "Shortcuts intent success dialog"),
            count
        )
    }

    static var backToShoppingList: String {
        String(localized: "Back to shopping list", comment: "Back button accessibility label from home")
    }

    static var editHomeLibrary: String {
        String(localized: "Edit home library", comment: "Edit library toolbar button accessibility label")
    }

    static var editMenuItems: String {
        String(localized: "Items", comment: "Edit menu option to reorder catalog items")
    }

    static var homeSectionsAccessibility: String {
        String(localized: "Home sections", comment: "Home sections menu accessibility label")
    }

    static var storeSectionsAccessibility: String {
        String(localized: "Store sections", comment: "Store sections menu accessibility label")
    }

    static var doneEditing: String {
        String(localized: "Done editing", comment: "Done editing toolbar button accessibility label")
    }

    static var moveToSection: String {
        String(localized: "Move to section", comment: "Move to section toolbar button accessibility label")
    }

    static var increaseQuantity: String {
        String(localized: "Increase quantity", comment: "Increase quantity accessibility label")
    }

    static var expandQuantityStepperHint: String {
        String(
            localized: "Shows plus and minus buttons to adjust quantity.",
            comment: "Accessibility hint when collapsed quantity pill can expand"
        )
    }

    static var decreaseQuantity: String {
        String(localized: "Decrease quantity", comment: "Decrease quantity accessibility label")
    }

    static var removeFromShoppingList: String {
        String(
            localized: "Remove from shopping list",
            comment: "Remove item from shopping list accessibility label"
        )
    }

    static func quantityAccessibility(_ quantity: Int) -> String {
        String(
            format: String(localized: "Quantity %lld", comment: "Quantity accessibility label in context menu"),
            quantity
        )
    }

    static func shoppingListRowAccessibilityLabel(
        name: String,
        isChecked: Bool,
        quantity: Int
    ) -> String {
        if isChecked {
            return String(
                format: String(
                    localized: "%@, checked",
                    comment: "Shopping list row accessibility label when item is checked; %@ is item name"
                ),
                name
            )
        }
        if quantity > 1 {
            return String(
                format: String(
                    localized: "%@, unchecked, quantity %lld",
                    comment: "Shopping list row accessibility label with quantity; %@ is item name"
                ),
                name,
                quantity
            )
        }
        return String(
            format: String(
                localized: "%@, unchecked",
                comment: "Shopping list row accessibility label when item is unchecked; %@ is item name"
            ),
            name
        )
    }

    static func pullToAddCatalogRowAccessibilityLabel(
        name: String,
        isInShopping: Bool,
        quantity: Int
    ) -> String {
        if isInShopping {
            if quantity > 1 {
                return String(
                    format: String(
                        localized: "%@, on shopping list, quantity %lld",
                        comment: "Pull-to-add catalog row accessibility label when item is on list with quantity; %@ is item name"
                    ),
                    name,
                    quantity
                )
            }
            return String(
                format: String(
                    localized: "%@, on shopping list",
                    comment: "Pull-to-add catalog row accessibility label when item is on list; %@ is item name"
                ),
                name
            )
        }
        return String(
            format: String(
                localized: "%@, not on shopping list",
                comment: "Pull-to-add catalog row accessibility label when item is not on list; %@ is item name"
            ),
            name
        )
    }

    static var clearCheckedItemsAccessibility: String {
        String(localized: "Clear checked items", comment: "Pull to clear checked items accessibility label")
    }

    static var openHomeLibrary: String {
        String(localized: "Open home library", comment: "Open home library button accessibility label")
    }

    static var customColor: String {
        String(localized: "Custom color", comment: "Custom theme color picker accessibility label")
    }

    static func sectionNameAccessibility(_ title: String) -> String {
        String(
            format: String(localized: "Section name, %@", comment: "Section name field accessibility label"),
            title
        )
    }

    // MARK: - Appearance options

    static var appearanceSystem: String {
        String(localized: "System", comment: "System appearance option")
    }

    static var appearanceLight: String {
        String(localized: "Light", comment: "Light appearance option")
    }

    static var appearanceDark: String {
        String(localized: "Dark", comment: "Dark appearance option")
    }

    static var textSizeExtraSmall: String {
        String(localized: "Extra Small", comment: "Extra small text size option")
    }

    static var textSizeSmall: String {
        String(localized: "Small", comment: "Small text size option")
    }

    static var textSizeMedium: String {
        String(localized: "Medium", comment: "Medium text size option")
    }

    static var textSizeLarge: String {
        String(localized: "Large", comment: "Large text size option")
    }

    static var textSizeExtraLarge: String {
        String(localized: "Extra Large", comment: "Extra large text size option")
    }

    static var themeBlue: String {
        String(localized: "Blue", comment: "Blue theme color name")
    }

    static var themeOrange: String {
        String(localized: "Orange", comment: "Orange theme color name")
    }

    static var themeRed: String {
        String(localized: "Red", comment: "Red theme color name")
    }

    static var themeGreen: String {
        String(localized: "Green", comment: "Green theme color name")
    }

    static var themePink: String {
        String(localized: "Pink", comment: "Pink theme color name")
    }

    static var themePurple: String {
        String(localized: "Purple", comment: "Purple theme color name")
    }

    static var themeCustom: String {
        String(localized: "Custom", comment: "Custom theme color name")
    }

    static var libraryLanguageEnglish: String {
        String(localized: "English", comment: "English library language picker option")
    }

    // MARK: - App Intents

    static var importTextToShoppingListIntentTitle: String {
        String(localized: "Import Text to Shopping List", comment: "Shortcuts intent title")
    }

    static var importTextToShoppingListIntentDescription: String {
        String(
            localized: "Adds library items to the shopping list when each line exactly matches an item name.",
            comment: "Shortcuts intent description"
        )
    }

    static var importTextParameterTitle: String {
        String(localized: "Text", comment: "Shortcuts intent text parameter title")
    }

    static let importTextToShoppingListIntentTitleResource = LocalizedStringResource(
        "Import Text to Shopping List",
        comment: "Shortcuts intent title"
    )

    static let importTextToShoppingListIntentDescriptionResource = LocalizedStringResource(
        "Adds library items to the shopping list when each line exactly matches an item name.",
        comment: "Shortcuts intent description"
    )

    static let importTextParameterTitleResource = LocalizedStringResource(
        "Text",
        comment: "Shortcuts intent text parameter title"
    )

    // MARK: - Catalog backup errors

    static func backupMissingFormatHeader(expectedVersion: Int) -> String {
        String(
            format: String(
                localized: "This file is missing a valid format header (expected “# format-version: %lld”).",
                comment: "Backup import error when format header is missing"
            ),
            expectedVersion
        )
    }

    static func backupUnsupportedFormat(_ version: Int) -> String {
        String(
            format: String(
                localized: "Unsupported backup format version %lld.",
                comment: "Backup import error for unsupported format version"
            ),
            version
        )
    }

    static func backupLanguageMismatch(found: String, expected: String) -> String {
        String(
            format: String(
                localized: "This backup is for “%@” but you are importing into the “%@” library. Switch library language in Appearance, or edit the “# language:” line in the file.",
                comment: "Backup import error when file language does not match active library"
            ),
            found,
            expected
        )
    }

    static var backupMissingLanguageHeader: String {
        String(
            localized: "This file is missing “# language: english” or “# language: hebrew”.",
            comment: "Backup import error when language header is missing"
        )
    }

    static var backupInvalidLibraryHeader: String {
        String(
            localized: "Missing or invalid library item header row after “[library]” (expected tab-separated: name, home_section, shopping_section, home_order, item_id).",
            comment: "Backup import error for invalid library header row"
        )
    }

    static var backupInvalidZipArchive: String {
        String(
            localized: "This file is not a valid Shoplister library backup zip.",
            comment: "Backup import error when zip cannot be read"
        )
    }

    static var backupMissingLibraryFile: String {
        String(
            localized: "This backup zip is missing library.txt.",
            comment: "Backup import error when library.txt is absent from zip"
        )
    }

    static func backupInvalidImageFileName(_ name: String) -> String {
        String(
            format: String(
                localized: "Invalid image file name in backup: “%@”.",
                comment: "Backup import error for malformed image filename in zip"
            ),
            name
        )
    }

    static func backupInvalidItemID(line: Int) -> String {
        String(
            format: String(
                localized: "Line %lld: item_id must be a valid UUID.",
                comment: "Backup import error for invalid item_id on a library row"
            ),
            line
        )
    }

    static var backupInvalidRecipeItemsHeader: String {
        String(
            localized: "Missing or invalid recipe item header row after “[recipe_items]” (expected tab-separated: recipe_name, item_name, quantity).",
            comment: "Backup import error for invalid recipe items header row"
        )
    }

    static func backupEmptyRecipeName(line: Int) -> String {
        String(
            format: String(
                localized: "Line %lld: recipe name is empty.",
                comment: "Backup import error for empty recipe name on a recipe_items row"
            ),
            line
        )
    }

    static func backupInvalidRecipeQuantity(line: Int) -> String {
        String(
            format: String(
                localized: "Line %lld: quantity must be a whole number of at least 1.",
                comment: "Backup import error for invalid recipe quantity"
            ),
            line
        )
    }

    static func backupSkippedRecipeRows(_ count: Int) -> String {
        String(
            format: String(
                localized: "%lld recipe ingredient rows were skipped because the item was not found in the library.",
                comment: "Backup import warning when recipe rows reference unknown items"
            ),
            count
        )
    }

    static func backupWrongColumnCount(line: Int, expected: Int, got: Int) -> String {
        String(
            format: String(
                localized: "Line %lld: expected %lld tab-separated columns, found %lld.",
                comment: "Backup import error for wrong column count on a line"
            ),
            line,
            expected,
            got
        )
    }

    static var backupEmptyInventoryGroups: String {
        String(
            localized: "“[home_sections]” must list at least one section (including the default “Undefined” / “לא מוגדר”).",
            comment: "Backup import error when home sections list is empty"
        )
    }

    static var backupEmptyShoppingGroups: String {
        String(
            localized: "“[shopping_sections]” must list at least one section.",
            comment: "Backup import error when shopping sections list is empty"
        )
    }

    static func backupUnknownInventoryGroup(itemLine: Int, title: String) -> String {
        String(
            format: String(
                localized: "Line %lld: Home section “%@” is not listed under [home_sections].",
                comment: "Backup import error for unknown home section on an item line"
            ),
            itemLine,
            title
        )
    }

    static func backupUnknownShoppingGroup(itemLine: Int, title: String) -> String {
        String(
            format: String(
                localized: "Line %lld: Store section “%@” is not listed under [shopping_sections].",
                comment: "Backup import error for unknown store section on an item line"
            ),
            itemLine,
            title
        )
    }

    static func backupEmptyItemName(line: Int) -> String {
        String(
            format: String(
                localized: "Line %lld: item name is empty.",
                comment: "Backup import error when item name is empty"
            ),
            line
        )
    }
}
