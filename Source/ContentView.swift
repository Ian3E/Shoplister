import Combine
import SwiftUI
import UIKit

/// Root navigation: the shopping list is the stack root; All Items is pushed on top.
/// Pull-to-add is a Settings-style sheet from the shopping list (gesture or trailing "+").
struct ContentView: View {
    @EnvironmentObject private var store: GroceryStore
    @EnvironmentObject private var fullWindowOverlay: FullWindowOverlayCoordinator
    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.appTheme) private var appTheme
    @State private var isPresentingSettings = false
    @State private var isPresentingNewCatalogItem = false
    @State private var newItemPrefillName: String? = nil
    /// Inventory row reorder mode: enables drag handles and changes row taps to "edit item".
    @State private var isInventoryReorderMode: Bool = false
    /// Home quantity pill expansion — owned here so leaving All Items can collapse it immediately.
    @State private var expandedHomeQuantityPillItemID: UUID?
    /// Identity token for Home quantity pills (All Items is rebuilt on each push, so this stays stable).
    @State private var homeQuantityPillChromeID = UUID()
    /// Catalog edit/delete from the full-window quick-actions overlay — presented here (root) so sheets
    /// aren’t attached under Home’s nested `InventoryView`, which can swallow presentation.
    @State private var inventoryCatalogEditorItem: GroceryItem?
    @State private var inventoryCatalogDeleteConfirmationItem: GroceryItem?
    @State private var editGroupsSheetKind: Tag.Kind?
    /// Mirrors the Library tab search presentation so New Item can clear/collapse it after save.
    @State private var isHomeToolbarSearchPresented = false
    /// Library search field text (lifted here so New Item sheet can clear it after save).
    @State private var homeInventorySearchText = ""
    /// Store pull-to-add: catalog search hosted on its own sheet so its search field lives in a
    /// toolbar fully isolated from the shopping-dependent Store nav bar.
    @State private var isStorePullToAddSearchPresented = false
    @State private var storePullToAddSearchText = ""
    @State private var storePullToAddPinnedSearchQuery = ""
    /// Stable identity for the pull-to-add search chrome; regenerated only when a session begins,
    /// mirroring Home's `homeToolbarSearchChromeID`, so adds cannot churn the searchable field.
    @State private var storePullToAddSearchChromeID = UUID()
    /// True only when presenting **New Item** after Store pull-to-add; add saved item to shopping list.
    @State private var newItemAddToShoppingAfterSave = false
    /// True while All Items is pushed on top of the shopping list. Fresh launches open the list.
    @State private var isShowingAllItems = false
    /// Saved lists sheet opened from the shopping list + long-press menu.
    @State private var isPresentingShoppingSavedLists = false
    /// Pull-to-add presented as a modal sheet (Settings-style) from the List tab.
    @State private var isPresentingPullToAddSheet = false
    /// Drops the sticky pull-to-add search keyboard (e.g. while the first-item explainer is up).
    @State private var suppressPullToAddSearchKeyboard = false
    @AppStorage(AppTextSize.storageKey) private var textSizeRaw: String = AppTextSize.defaultSize.rawValue
    @AppStorage(AppTheme.storageKey) private var themeRaw: String = AppTheme.blue.rawValue
    @AppStorage(AppTheme.customColorStorageKey) private var customColorHex: String = AppTheme.defaultCustomColorHex
    @AppStorage(AppHomeFirstVisitExplainer.storageKey) private var hasSeenFirstShoppingItemExplainer = false
    @AppStorage(AppWelcomeExplainer.storageKey) private var hasSeenWelcomeExplainer = false
    @AppStorage(AppStoreGesturesExplainer.storageKey) private var hasSeenStoreGesturesExplainer = false
    @AppStorage(AppHomeCatalogVisit.storageKey) private var hasVisitedHomeCatalog = false
    @AppStorage(AppShoppingSortChecked.storageKey) private var sortCheckedShoppingItems: Bool = false
    @AppStorage(AppListTabBadge.storageKey) private var showListTabBadge: Bool = true
    @AppStorage(AppShoppingPlusOpensAllItems.storageKey) private var plusOpensAllItems: Bool = false
    @AppStorage(AppShoppingBadgeUnchecked.storageKey) private var showUncheckedCountAppBadge: Bool = false
    /// Text size draft while Settings is open; committed in the sheet `onDismiss` handler only.
    @State private var settingsTextSizeDraft: String = AppTextSize.defaultSize.rawValue
    /// Theme draft while Settings is open; committed in the sheet `onDismiss` handler only.
    @State private var settingsThemeDraft: String = AppTheme.blue.rawValue
    @State private var settingsThemeCustomDraft: String = AppTheme.defaultCustomColorHex
    @State private var firstShoppingItemExplainerTask: Task<Void, Never>?
    @State private var welcomeExplainerTask: Task<Void, Never>?
    @State private var storeGesturesExplainerTask: Task<Void, Never>?
    /// Drives the All Items shopping-list badge layer. Held in `@State` (not `@StateObject`) so only
    /// the badge layer observes it — frame/visibility updates don't re-render the root.
    @State private var shoppingListBadgeAnchor = ShoppingListBadgeAnchor()

    /// At least one unchecked line with a resolved catalog item (same as what share text would include).
    private var canShareShoppingList: Bool {
        ShoppingListShareText.hasUncheckedItemsToShare(store: store)
    }

    /// All Items shopping-list button badge when the dedicated setting is on (0 hides the badge).
    private var listTabUncheckedBadge: Int {
        guard showListTabBadge else { return 0 }
        return ShoppingIconBadge.uncheckedCount(store: store)
    }

    // MARK: - Navigation root

    @ViewBuilder
    private var tabChrome: some View {
        ZStack(alignment: .bottomLeading) {
            NavigationStack {
                ShoppingView(
                    canShareShoppingList: canShareShoppingList,
                    isStorePullToAddSearchPresented: $isStorePullToAddSearchPresented,
                    onBeginPullToAddSearch: beginStoreTabPullToAdd,
                    showsAddItemButton: true,
                    onShare: presentShoppingListShare,
                    onSettings: { isPresentingSettings = true },
                    onManageStoreSections: { editGroupsSheetKind = .shopping },
                    // Pull-down always opens pull-to-add (`onBeginPullToAddSearch`); only + honors the shortcut.
                    onAddItem: handleShoppingListPlusTapped,
                    onShowAllItems: { isShowingAllItems = true },
                    onSavedLists: { isPresentingShoppingSavedLists = true },
                    onCreateItem: createItemFromShoppingList
                )
                .navigationDestination(isPresented: $isShowingAllItems) {
                    homeCatalogTabScreen
                }
            }
            // Keep nav/bottom toolbar controls label-colored; themed controls opt in explicitly.
            .tint(Color.primary)
            .catalogGroupedChromeBackdrop()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Above the toolbar so Liquid Glass can't blend or clip it (see `HomeShoppingListToolbarButton`).
            ShoppingListButtonBadgeLayer(
                anchor: shoppingListBadgeAnchor,
                count: listTabUncheckedBadge
            )
            .zIndex(130)

            if let kind = fullWindowOverlay.kind {
                fullWindowOverlayContent(kind: kind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .zIndex(200)
            }
        }
        .sheet(isPresented: $isPresentingPullToAddSheet) {
            storeTabPullToAddSheet
        }
        .onChange(of: isPresentingPullToAddSheet) { _, presented in
            if !presented {
                suppressPullToAddSearchKeyboard = false
                isStorePullToAddSearchPresented = false
                storePullToAddSearchText = ""
                storePullToAddPinnedSearchQuery = ""
                if newItemAddToShoppingAfterSave {
                    isPresentingNewCatalogItem = false
                }
                scheduleFirstShoppingItemExplainerIfNeeded()
                scheduleStoreGesturesExplainerIfNeeded()
            }
        }
    }

    private var settingsSheet: some View {
        SettingsView(
            draftTextSizeRaw: $settingsTextSizeDraft,
            draftThemeRaw: $settingsThemeDraft,
            draftCustomColorHex: $settingsThemeCustomDraft,
            onClose: { isPresentingSettings = false }
        )
        .environmentObject(store)
    }

    /// All Items: pushed on the shopping list (no back chevron; bottom-leading list button + swipe-back).
    /// Edit enters reorder directly; ⋯ hosts home sections / create / saved lists; search is a
    /// minimized bottom-trailing control.
    private var homeCatalogTabScreen: some View {
        InventoryView(
            isReorderMode: $isInventoryReorderMode,
            usesHomeToolbarSearch: true,
            isHomeToolbarSearchPresented: $isHomeToolbarSearchPresented,
            homeSearchText: $homeInventorySearchText,
            minimizesToolbarSearch: true,
            showsToolbarSearchButton: true,
            showsRecipesInTopBarLeading: true,
            bottomReservedHeight: 0,
            ignoresSafeArea: false,
            showsShoppingStatus: true,
            expandedHomeQuantityPillItemID: $expandedHomeQuantityPillItemID,
            homeQuantityPillChromeID: homeQuantityPillChromeID,
            onPresentNewItemFromSearch: { name in
                newItemAddToShoppingAfterSave = false
                newItemPrefillName = name
                homeInventorySearchText = ""
                isHomeToolbarSearchPresented = false
                isPresentingNewCatalogItem = true
            },
            onToolbarAddItem: {
                newItemPrefillName = nil
                newItemAddToShoppingAfterSave = false
                isPresentingNewCatalogItem = true
            },
            onToolbarSelectGroupsKind: { editGroupsSheetKind = $0 },
            onBackToStore: nil,
            onShowShoppingList: { isShowingAllItems = false },
            shoppingListBadgeCount: listTabUncheckedBadge,
            onShoppingListButtonFrameChange: { shoppingListBadgeAnchor.buttonFrame = $0 },
            onShoppingListButtonMountedChange: { shoppingListBadgeAnchor.isButtonMounted = $0 },
            onReturnToStoreAfterRecipeApply: { isShowingAllItems = false },
            onEditItem: { item in
                inventoryCatalogEditorItem = item
            },
            onDeleteItem: { item in
                inventoryCatalogDeleteConfirmationItem = item
            }
        )
        .navigationBarBackButtonHidden(true)
        .enablesNavigationInteractivePopGesture(
            isEnabled: !isInventoryReorderMode,
            // Badge fades in as the push begins; hide as soon as a pop (button or swipe) begins,
            // and restore if an interactive swipe is cancelled (appear callbacks fire again).
            onWillAppear: { shoppingListBadgeAnchor.isPageSettled = true },
            onDidAppear: { shoppingListBadgeAnchor.isPageSettled = true },
            onWillDisappear: { shoppingListBadgeAnchor.isPageSettled = false }
        )
    }

    /// EXPERIMENT: pull-to-add as a sheet with Done (same chrome pattern as Settings).
    /// New Item is nested here so it can present over the sheet.
    /// Focused glass search field (not `.searchable`) so the keyboard rises with the sheet;
    /// sticky UIKit field refuses resign on row taps so the keyboard stays up across adds.
    private var storeTabPullToAddSheet: some View {
        NavigationStack {
            StorePullToAddCatalogSearchView(
                isSearchPresented: $isStorePullToAddSearchPresented,
                searchText: $storePullToAddSearchText,
                pinnedSearchQuery: $storePullToAddPinnedSearchQuery,
                searchChromeID: storePullToAddSearchChromeID,
                onPresentNewItem: { name in
                    newItemAddToShoppingAfterSave = true
                    newItemPrefillName = name
                    isPresentingNewCatalogItem = true
                },
                onEndSearch: endStoreTabPullToAdd,
                onShowAllItems: showAllItemsFromPullToAdd,
                usesFocusedSearchField: true,
                searchKeyboardSuppressed: $suppressPullToAddSearchKeyboard
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environmentObject(store)
        // Sheets sit above ContentView's root overlay, so the first-item explainer is hosted
        // here when pull-to-add is open (keyboard is suppressed for the duration).
        .overlay {
            if fullWindowOverlay.kind == .firstShoppingItemExplainer {
                HomeFirstVisitExplainerOverlay(onDone: completeFirstShoppingItemExplainer)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: Binding(
            get: { isPresentingNewCatalogItem && isPresentingPullToAddSheet },
            set: { isPresentingNewCatalogItem = $0 }
        )) {
            NavigationStack {
                NewItemView(
                    prefillName: newItemPrefillName,
                    addToShoppingAfterSave: true,
                    onSaved: restoreStoreAfterPullToAddNewItemIfNeeded,
                    onCancel: restoreStoreAfterPullToAddNewItemIfNeeded
                )
                .environmentObject(store)
            }
        }
    }

    private func presentShoppingListShare() {
        let text = ShoppingListShareText.buildPlainText(
            store: store,
            catalogLanguage: catalogLanguage,
            sortCheckedShoppingItems: sortCheckedShoppingItems
        )
        ShoppingListSharePresentation.presentPlainText(text)
    }

    /// Presents pull-to-add as a sheet (pull gesture or trailing "+" button).
    private func beginStoreTabPullToAdd() {
        guard !isPresentingPullToAddSheet else { return }
        storePullToAddSearchText = ""
        storePullToAddPinnedSearchQuery = ""
        storePullToAddSearchChromeID = UUID()
        isStorePullToAddSearchPresented = true
        isPresentingPullToAddSheet = true
    }

    /// Dismisses the pull-to-add sheet (Done, empty Return, or search Cancel).
    private func endStoreTabPullToAdd() {
        guard isPresentingPullToAddSheet else { return }
        isStorePullToAddSearchPresented = false
        storePullToAddSearchText = ""
        storePullToAddPinnedSearchQuery = ""
        isPresentingPullToAddSheet = false
    }

    /// Shopping list + menu **Create item**: new library item, added to the shopping list on save
    /// (same as Create Item from pull-to-add).
    private func createItemFromShoppingList() {
        newItemPrefillName = nil
        newItemAddToShoppingAfterSave = true
        isPresentingNewCatalogItem = true
    }

    /// Shopping list +: All Items when **Shortcut to All Items** is on, otherwise pull-to-add.
    private func handleShoppingListPlusTapped() {
        if plusOpensAllItems {
            isShowingAllItems = true
        } else {
            beginStoreTabPullToAdd()
        }
    }

    /// Pull-to-add **All Items**: close the sheet and push All Items underneath it.
    private func showAllItemsFromPullToAdd() {
        endStoreTabPullToAdd()
        isShowingAllItems = true
    }

    var body: some View {
        tabChrome
        .onChange(of: isShowingAllItems) { _, showing in
            if showing {
                hasVisitedHomeCatalog = true
                return
            }
            // Popped back to the shopping list (button or swipe-back).
            isHomeToolbarSearchPresented = false
            homeInventorySearchText = ""
            if isInventoryReorderMode {
                isInventoryReorderMode = false
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                expandedHomeQuantityPillItemID = nil
            }
            scheduleStoreGesturesExplainerIfNeeded()
        }
        .onAppear {
            markFirstShoppingItemExplainerSeenIfShoppingListAlreadyPopulated()
            scheduleWelcomeExplainerIfNeeded()
            scheduleStoreGesturesExplainerIfNeeded()
        }
        .onChange(of: isInventoryReorderMode) { _, active in
            if !active {
                editGroupsSheetKind = nil
            }
        }
        .onChange(of: fullWindowOverlay.inventoryQuickActionResult) { _, result in
            guard let result else { return }
            switch result {
            case .editItem(let id):
                if let item = store.item(for: id) {
                    inventoryCatalogEditorItem = item
                }
            case .deleteItem(let id):
                if let item = store.item(for: id) {
                    inventoryCatalogDeleteConfirmationItem = item
                }
            }
            Task { @MainActor in
                await Task.yield()
                fullWindowOverlay.consumeInventoryQuickActionResult()
            }
        }
        .onChange(of: store.shopping.count) { oldCount, newCount in
            guard oldCount == 0, newCount > 0 else { return }
            scheduleFirstShoppingItemExplainerIfNeeded()
            scheduleStoreGesturesExplainerIfNeeded()
        }
        .onChange(of: hasSeenFirstShoppingItemExplainer) { _, seen in
            guard !seen else { return }
            guard !store.shopping.isEmpty else { return }
            scheduleFirstShoppingItemExplainerIfNeeded()
        }
        .onChange(of: hasSeenWelcomeExplainer) { _, seen in
            guard !seen else { return }
            scheduleWelcomeExplainerIfNeeded()
        }
        .sheet(isPresented: $isPresentingSettings) {
            settingsSheet
        }
        .sheet(isPresented: $isPresentingShoppingSavedLists) {
            NavigationStack {
                RecipesListView(
                    onAppliedToShopping: { isPresentingShoppingSavedLists = false }
                )
            }
            .environmentObject(store)
        }
        .onChange(of: isPresentingSettings) { _, presented in
            if presented {
                var stored = textSizeRaw
                AppTextSize.migrateStoredRawValueIfNeeded(&stored)
                if stored != textSizeRaw {
                    textSizeRaw = stored
                }
                settingsTextSizeDraft = textSizeRaw
                settingsThemeDraft = themeRaw
                settingsThemeCustomDraft = customColorHex
            } else {
                commitSettingsTextSizeDraft()
                commitSettingsThemeDraft()
                scheduleExplainersAfterSettingsDismissed()
            }
        }
        .onChange(of: settingsThemeDraft) { _, newValue in
            guard isPresentingSettings else { return }
            themeRaw = newValue
        }
        .onChange(of: settingsThemeCustomDraft) { _, newValue in
            guard isPresentingSettings else { return }
            customColorHex = newValue
        }
        .sheet(isPresented: Binding(
            get: { isPresentingNewCatalogItem && !isPresentingPullToAddSheet },
            set: { isPresentingNewCatalogItem = $0 }
        )) {
            NavigationStack {
                NewItemView(
                    prefillName: newItemPrefillName,
                    addToShoppingAfterSave: newItemAddToShoppingAfterSave,
                    onSaved: restoreStoreAfterPullToAddNewItemIfNeeded,
                    onCancel: newItemAddToShoppingAfterSave
                        ? restoreStoreAfterPullToAddNewItemIfNeeded
                        : nil
                )
                    .environmentObject(store)
            }
        }
        .onChange(of: isPresentingNewCatalogItem) { _, presented in
            if !presented {
                newItemAddToShoppingAfterSave = false
            }
        }
        .sheet(item: $inventoryCatalogEditorItem) { item in
            NavigationStack {
                ItemEditorView(item: item)
            }
            .environmentObject(store)
        }
        .sheet(item: $editGroupsSheetKind) { kind in
            NavigationStack {
                GroupTagEditorSheet(kind: kind)
                    .navigationTitle(kind == .inventory ? LocalizedCopy.homeSections : LocalizedCopy.storeSections)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(LocalizedCopy.done) {
                                editGroupsSheetKind = nil
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(appTheme.color)
                        }
                    }
            }
            .environmentObject(store)
        }
        .alert(
            LocalizedCopy.deleteThisItemAlertTitle,
            isPresented: Binding(
                get: { inventoryCatalogDeleteConfirmationItem != nil },
                set: { if !$0 { inventoryCatalogDeleteConfirmationItem = nil } }
            )
        ) {
            Button(LocalizedCopy.cancel, role: .cancel) {
                inventoryCatalogDeleteConfirmationItem = nil
            }
            Button(LocalizedCopy.delete, role: .destructive) {
                if let item = inventoryCatalogDeleteConfirmationItem {
                    withAnimation(.snappy) {
                        store.deleteCatalogItem(item.id)
                    }
                }
                inventoryCatalogDeleteConfirmationItem = nil
            }
        } message: {
            if let item = inventoryCatalogDeleteConfirmationItem {
                Text(LocalizedCopy.deleteItemMessage(itemName: item.displayName(appContentLanguage: catalogLanguage)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareExtensionShoppingOpsMerged)) { note in
            let count = note.userInfo?[ShareExtensionAppGroupSupport.mergedOpCountUserInfoKey] as? Int ?? 0
            guard count > 0 else { return }
            isShowingAllItems = false
            isPresentingPullToAddSheet = false
            isStorePullToAddSearchPresented = false
            storePullToAddSearchText = ""
            storePullToAddPinnedSearchQuery = ""
        }
    }

    private func commitSettingsTextSizeDraft() {
        guard settingsTextSizeDraft != textSizeRaw else { return }
        withAnimation(AppTextSize.layoutCommitAnimation) {
            textSizeRaw = settingsTextSizeDraft
        }
    }

    private func commitSettingsThemeDraft() {
        guard settingsThemeDraft != themeRaw || settingsThemeCustomDraft != customColorHex else { return }
        themeRaw = settingsThemeDraft
        customColorHex = settingsThemeCustomDraft
    }

    /// Restore used after pull-to-add → Create Item → Save (and Cancel).
    private func restoreStoreAfterPullToAddNewItemIfNeeded() {
        homeInventorySearchText = ""
        storePullToAddSearchText = ""
        storePullToAddPinnedSearchQuery = ""
        isStorePullToAddSearchPresented = false
        isPresentingNewCatalogItem = false
        endStoreTabPullToAdd()
    }

    @ViewBuilder
    private func fullWindowOverlayContent(kind: FullWindowOverlayCoordinator.Kind) -> some View {
        switch kind {
        case .shoppingPhotoPreview(let itemID):
            ItemImageCompactPreviewOverlay(itemID: itemID) {
                fullWindowOverlay.dismiss()
            } onEditItem: {
                fullWindowOverlay.inventoryEditTapped(forItemID: itemID)
            }
        case .welcomeExplainer:
            WelcomeExplainerOverlay {
                hasSeenWelcomeExplainer = true
                fullWindowOverlay.dismiss(animated: false)
                scheduleFirstShoppingItemExplainerIfNeeded()
                scheduleStoreGesturesExplainerIfNeeded()
            }
        case .firstShoppingItemExplainer:
            // When pull-to-add is open the interactive copy lives on the sheet overlay;
            // this root copy covers the non–pull-to-add path.
            HomeFirstVisitExplainerOverlay(onDone: completeFirstShoppingItemExplainer)
        case .storeGesturesExplainer:
            StoreGesturesExplainerOverlay {
                hasSeenStoreGesturesExplainer = true
                fullWindowOverlay.dismiss(animated: false)
            }
        }
    }

    private func markFirstShoppingItemExplainerSeenIfShoppingListAlreadyPopulated() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppHomeFirstVisitExplainer.legacyPopulationMigrationKey) else { return }
        defaults.set(true, forKey: AppHomeFirstVisitExplainer.legacyPopulationMigrationKey)
        guard !store.shopping.isEmpty else { return }
        hasSeenFirstShoppingItemExplainer = true
    }

    private func scheduleExplainersAfterSettingsDismissed() {
        Task { @MainActor in
            await Task.yield()
            scheduleWelcomeExplainerIfNeeded()
            scheduleFirstShoppingItemExplainerIfNeeded()
            scheduleStoreGesturesExplainerIfNeeded()
        }
    }

    private func scheduleWelcomeExplainerIfNeeded() {
        guard !hasSeenWelcomeExplainer else { return }
        welcomeExplainerTask?.cancel()
        welcomeExplainerTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            guard !hasSeenWelcomeExplainer else { return }
            guard fullWindowOverlay.kind == nil else { return }
            fullWindowOverlay.presentWelcomeExplainer()
        }
    }

    private func scheduleFirstShoppingItemExplainerIfNeeded() {
        guard !hasSeenFirstShoppingItemExplainer else { return }
        dismissKeyboardForFirstItemExplainer()
        firstShoppingItemExplainerTask?.cancel()
        firstShoppingItemExplainerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            guard !hasSeenFirstShoppingItemExplainer else { return }
            guard !store.shopping.isEmpty else { return }
            guard fullWindowOverlay.kind == nil else { return }
            fullWindowOverlay.presentFirstShoppingItemExplainer()
        }
    }

    private func completeFirstShoppingItemExplainer() {
        hasSeenFirstShoppingItemExplainer = true
        fullWindowOverlay.dismiss(animated: false)
        restorePullToAddKeyboardAfterFirstItemExplainerIfNeeded()
        scheduleStoreGesturesExplainerIfNeeded()
    }

    private func restorePullToAddKeyboardAfterFirstItemExplainerIfNeeded() {
        guard isPresentingPullToAddSheet else {
            suppressPullToAddSearchKeyboard = false
            return
        }
        Task { @MainActor in
            await Task.yield()
            suppressPullToAddSearchKeyboard = false
        }
    }

    /// First visit to a non-empty shopping list. Waits for the first-item explainer
    /// when both are pending so they don't race.
    private func scheduleStoreGesturesExplainerIfNeeded() {
        guard !hasSeenStoreGesturesExplainer else { return }
        guard hasSeenFirstShoppingItemExplainer else { return }
        guard !store.shopping.isEmpty else { return }
        guard !isShowingAllItems else { return }
        guard !isPresentingSettings else { return }
        guard !isStorePullToAddSearchPresented else { return }
        if isPresentingPullToAddSheet { return }
        storeGesturesExplainerTask?.cancel()
        storeGesturesExplainerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            guard !hasSeenStoreGesturesExplainer else { return }
            guard hasSeenFirstShoppingItemExplainer else { return }
            guard !store.shopping.isEmpty else { return }
            guard !isShowingAllItems else { return }
            guard !isPresentingSettings else { return }
            guard !isStorePullToAddSearchPresented else { return }
            if isPresentingPullToAddSheet { return }
            guard fullWindowOverlay.kind == nil else { return }
            fullWindowOverlay.presentStoreGesturesExplainer()
        }
    }

    /// Resigns first responder before the first-item explainer overlay.
    /// Pull-to-add's sticky search field refuses resign unless suppression is set first.
    private func dismissKeyboardForFirstItemExplainer() {
        if isPresentingPullToAddSheet {
            suppressPullToAddSearchKeyboard = true
        }
        Task { @MainActor in
            await Task.yield()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

}

/// Where and when to draw the All Items shopping-list badge (observed only by the badge layer).
private final class ShoppingListBadgeAnchor: ObservableObject {
    /// Button frame in window coordinates.
    @Published var buttonFrame: CGRect = .zero
    /// All Items is appearing/visible and no pop is in progress.
    @Published var isPageSettled = false
    /// Button is in the toolbar (false in edit mode, before mount, after pop).
    @Published var isButtonMounted = false
}

/// Unchecked-count badge pinned to the All Items shopping-list button's top-trailing corner.
/// Drawn above the navigation stack: inside the toolbar, Liquid Glass blends it (translucent) and
/// clips it while the bar morphs in.
private struct ShoppingListButtonBadgeLayer: View {
    @ObservedObject var anchor: ShoppingListBadgeAnchor
    let count: Int
    @Environment(\.appTheme) private var appTheme

    private static let badgeHeight: CGFloat = 16
    /// How far the badge center sits outside the button frame's top-trailing corner.
    private static let cornerOutset = CGPoint(x: 1, y: 1)

    /// The toolbar animates the button in by scaling its frame (Edit → Done: ~7pt → ~39pt → 36pt over
    /// ~0.8s, with sparse updates; on push it first reports an off-screen placeholder at (-18, -18),
    /// then 43pt frames). The finished button is exactly the tap-target size and on-screen, so pin
    /// the badge only to such a frame — no timers needed.
    private var hasSettledButtonFrame: Bool {
        let frame = anchor.buttonFrame
        let size = CatalogToolbarTapChrome.iconTapDiameter
        let tolerance: CGFloat = 0.5
        return abs(frame.width - size) <= tolerance
            && abs(frame.height - size) <= tolerance
            && frame.minX >= 0
            && frame.minY >= 0
    }

    private var isVisible: Bool {
        count > 0
            && anchor.isButtonMounted
            && anchor.isPageSettled
            && hasSettledButtonFrame
    }

    private var badgeText: String {
        count > 99 ? "99+" : "\(count)"
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let frame = anchor.buttonFrame
            // Window coordinates are physical; pick the trailing corner for the interface direction.
            let isRTL = AppSystemLocale.interfaceLayoutDirection == .rightToLeft
            let cornerX = isRTL ? frame.minX + Self.cornerOutset.x : frame.maxX - Self.cornerOutset.x
            let cornerY = frame.minY + Self.cornerOutset.y
            Text(badgeText)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .padding(.horizontal, 4)
                .frame(minWidth: Self.badgeHeight, minHeight: Self.badgeHeight)
                .background(Capsule().fill(appTheme.color))
                .fixedSize()
                .position(x: cornerX - origin.x, y: cornerY - origin.y)
                // Never animate placement: frame updates can arrive inside other transactions
                // (e.g. Edit → Done remounting the button), which made the badge slide in.
                .transaction { $0.animation = nil }
                .opacity(isVisible ? 1 : 0)
                // Fade in alongside the push (toolbar items morph in place, they don't slide);
                // disappear instantly when a pop begins.
                .animation(isVisible ? .easeOut(duration: 0.25) : nil, value: isVisible)
        }
        // Positions are computed in physical (window) coordinates — don't let RTL mirror them.
        .environment(\.layoutDirection, .leftToRight)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Swipe back with a custom toolbar back control

/// Allows the navigation edge-pop to begin while a list is dragging or decelerating.
private final class NavigationInteractivePopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?
    var isPopEnabled: Bool = true

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isPopEnabled else { return false }
        guard let navigationController else { return false }
        return navigationController.viewControllers.count > 1
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === navigationController?.interactivePopGestureRecognizer else {
            return false
        }
        return otherGestureRecognizer.view is UIScrollView
            || Self.viewIsInsideScrollView(otherGestureRecognizer.view)
    }

    private static func viewIsInsideScrollView(_ view: UIView?) -> Bool {
        var current = view
        while let node = current {
            if node is UIScrollView { return true }
            current = node.superview
        }
        return false
    }
}

/// UIKit disables edge swipe-back when the system back button is hidden; this re-enables it and
/// coordinates scroll pans so swipe-back works during active list scroll, not only when idle.
private struct NavigationInteractivePopEnabler: UIViewControllerRepresentable {
    var isEnabled: Bool = true
    /// Page is about to appear (push starting, or an interactive pop being cancelled).
    var onWillAppear: (() -> Void)? = nil
    /// Page finished appearing (push landed, or an interactive pop was cancelled).
    var onDidAppear: (() -> Void)? = nil
    /// Page is about to leave (pop started by button or swipe).
    var onWillDisappear: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = NavigationInteractivePopEnablerViewController(isPopEnabled: isEnabled)
        controller.onWillAppear = onWillAppear
        controller.onDidAppear = onDidAppear
        controller.onWillDisappear = onWillDisappear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let controller = uiViewController as? NavigationInteractivePopEnablerViewController else { return }
        controller.isPopEnabled = isEnabled
        controller.onWillAppear = onWillAppear
        controller.onDidAppear = onDidAppear
        controller.onWillDisappear = onWillDisappear
        controller.applyInteractivePopGestureState()
    }

    private final class NavigationInteractivePopEnablerViewController: UIViewController {
        private let popGestureDelegate = NavigationInteractivePopGestureDelegate()
        private var coordinatedScrollViews = NSHashTable<UIScrollView>.weakObjects()
        var isPopEnabled: Bool
        var onWillAppear: (() -> Void)?
        var onDidAppear: (() -> Void)?
        var onWillDisappear: (() -> Void)?

        init(isPopEnabled: Bool) {
            self.isPopEnabled = isPopEnabled
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyInteractivePopGestureState()
            onDidAppear?()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onWillDisappear?()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyInteractivePopGestureState()
            onWillAppear?()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if isPopEnabled {
                coordinateScrollViewsForInteractivePop()
            }
        }

        func applyInteractivePopGestureState() {
            guard let navigationController else { return }
            guard let pop = navigationController.interactivePopGestureRecognizer else { return }

            popGestureDelegate.isPopEnabled = isPopEnabled
            popGestureDelegate.navigationController = navigationController

            guard isPopEnabled, navigationController.viewControllers.count > 1 else {
                pop.isEnabled = false
                return
            }

            pop.isEnabled = true
            pop.delegate = popGestureDelegate

            coordinateScrollViewsForInteractivePop()
            DispatchQueue.main.async { [weak self] in
                self?.coordinateScrollViewsForInteractivePop()
            }
        }

        private func coordinateScrollViewsForInteractivePop() {
            guard isPopEnabled else { return }
            guard let navigationController else { return }
            guard navigationController.viewControllers.count > 1 else { return }
            guard let pop = navigationController.interactivePopGestureRecognizer else { return }

            Self.enumerateScrollViews(in: navigationController.view) { scrollView in
                let pan = scrollView.panGestureRecognizer
                guard pan !== pop else { return }
                guard !coordinatedScrollViews.contains(scrollView) else { return }
                pan.require(toFail: pop)
                coordinatedScrollViews.add(scrollView)
            }
        }

        private static func enumerateScrollViews(in view: UIView, body: (UIScrollView) -> Void) {
            if let scrollView = view as? UIScrollView {
                body(scrollView)
            }
            for subview in view.subviews {
                enumerateScrollViews(in: subview, body: body)
            }
        }
    }
}

private extension View {
    func enablesNavigationInteractivePopGesture(
        isEnabled: Bool = true,
        onWillAppear: (() -> Void)? = nil,
        onDidAppear: (() -> Void)? = nil,
        onWillDisappear: (() -> Void)? = nil
    ) -> some View {
        background(
            NavigationInteractivePopEnabler(
                isEnabled: isEnabled,
                onWillAppear: onWillAppear,
                onDidAppear: onDidAppear,
                onWillDisappear: onWillDisappear
            )
        )
    }
}
