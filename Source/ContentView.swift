import Combine
import SwiftUI
import UIKit

/// Root TabView with centered List + Library tabs.
/// Pull-to-add is a Settings-style sheet from the List tab (gesture or trailing "+").
private enum TabSelection: Hashable {
    case store
    case home
    /// Intercept-only: tap opens pull-to-add, then bounces back to `.store`.
    case storeAdd
    /// Intercept-only: tap activates Home searchable, then bounces back to `.home`.
    case homeSearch

    /// Whether the Store side-add control should be visible for this selection.
    var showsStoreSideAddControl: Bool {
        switch self {
        case .store, .storeAdd: return true
        case .home, .homeSearch: return false
        }
    }
}

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
    /// Home quantity pill expansion — owned here so leaving Library can collapse it immediately
    /// (TabView may defer InventoryView updates until the tab is visible again).
    @State private var expandedHomeQuantityPillItemID: UUID?
    /// Bumped when returning to Library after an expanded pill so rows remount collapsed
    /// (TabView defers Home updates while off-screen; remount must happen on become-active).
    @State private var homeQuantityPillChromeID = UUID()
    /// Set when leaving Library with an expanded pill; consumed on the next Library activation.
    @State private var homeQuantityPillNeedsChromeReset = false
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
    /// Selected root tab (List / Library). Fresh launches open List.
    @State private var selectedTab: TabSelection = .store
    /// Required so `role: .search` gets Liquid Glass *button* (pinned) placement.
    /// Text is unused — side taps bounce into Store add / Home search instead.
    @State private var tabBarSearchText = ""
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
    @AppStorage(AppShoppingBadgeUnchecked.storageKey) private var showUncheckedCountAppBadge: Bool = false
    /// Text size draft while Settings is open; committed in the sheet `onDismiss` handler only.
    @State private var settingsTextSizeDraft: String = AppTextSize.defaultSize.rawValue
    /// Theme draft while Settings is open; committed in the sheet `onDismiss` handler only.
    @State private var settingsThemeDraft: String = AppTheme.blue.rawValue
    @State private var settingsThemeCustomDraft: String = AppTheme.defaultCustomColorHex
    @State private var firstShoppingItemExplainerTask: Task<Void, Never>?
    @State private var welcomeExplainerTask: Task<Void, Never>?
    @State private var storeGesturesExplainerTask: Task<Void, Never>?
    @StateObject private var firstAddToListDive = FirstAddToListDiveController()
    /// Live List-tab icon center (window coords); refreshed by `ListTabDiveTargetReader`.
    @State private var listTabDiveTargetPoint: CGPoint = .zero
    /// Snapshot taken when a dive starts so travel doesn’t drift with layout.
    @State private var activeDiveTargetPoint: CGPoint = .zero
    /// Hide the List tab badge until the first-add +1 bubble finishes.
    @State private var suppressListTabBadgeForFirstAddDive = false
    /// Blocks Home/List interaction from dive start until the first-item explainer appears.
    @State private var blocksInteractionUntilFirstItemExplainer = false

    /// At least one unchecked line with a resolved catalog item (same as what share text would include).
    private var canShareShoppingList: Bool {
        ShoppingListShareText.hasUncheckedItemsToShare(store: store)
    }

    /// List tab badge when the dedicated setting is on (0 hides the badge).
    private var listTabUncheckedBadge: Int {
        guard showListTabBadge else { return 0 }
        guard !suppressListTabBadgeForFirstAddDive else { return 0 }
        return ShoppingIconBadge.uncheckedCount(store: store)
    }

    /// Theme used for tab chrome; follows the Settings draft so picks apply under the sheet immediately.
    private var tabBarTheme: AppThemeSelection {
        if isPresentingSettings {
            return AppThemeSelection(
                presetRaw: settingsThemeDraft,
                customColorHex: settingsThemeCustomDraft
            )
        }
        return appTheme
    }

    // MARK: - TabView root

    @ViewBuilder
    private var tabChrome: some View {
        ZStack(alignment: .bottomLeading) {
            TabView(selection: $selectedTab) {
                Tab(LocalizedCopy.tabList, systemImage: "checklist", value: TabSelection.store) {
                    NavigationStack {
                        ShoppingView(
                            canShareShoppingList: canShareShoppingList,
                            isStorePullToAddSearchPresented: $isStorePullToAddSearchPresented,
                            onBeginPullToAddSearch: beginStoreTabPullToAdd,
                            showsAddItemButton: false,
                            onShare: presentShoppingListShare,
                            onSettings: { isPresentingSettings = true },
                            onManageStoreSections: { editGroupsSheetKind = .shopping },
                            onAddItem: beginStoreTabPullToAdd
                        )
                    }
                    // Keep nav/bottom toolbar controls label-colored; tab bar tint is UIKit-only.
                    .tint(Color.primary)
                }
                .badge(listTabUncheckedBadge)

                Tab(LocalizedCopy.tabLibrary, systemImage: "square.grid.2x2.fill", value: TabSelection.home) {
                    NavigationStack {
                        homeCatalogTabScreen
                    }
                    .tint(Color.primary)
                }

                // `role: .search` + searchable on *this* tab + `.tabViewSearchActivation`
                // → separated clear-glass button (HIG). searchable must not live on the
                // TabView root — that parks a top search field on List and Library.
                if selectedTab.showsStoreSideAddControl {
                    Tab(value: TabSelection.storeAdd, role: .search) {
                        NavigationStack {
                            Color.clear
                                .accessibilityHidden(true)
                                .searchable(text: $tabBarSearchText)
                        }
                    } label: {
                        Label {
                            Text(LocalizedCopy.addItem)
                        } icon: {
                            Image(uiImage: StoreSideAddSymbol.image(color: tabBarTheme.color))
                        }
                    }
                } else {
                    Tab(
                        LocalizedCopy.search,
                        systemImage: "magnifyingglass",
                        value: TabSelection.homeSearch,
                        role: .search
                    ) {
                        NavigationStack {
                            Color.clear
                                .accessibilityHidden(true)
                                .searchable(text: $tabBarSearchText)
                        }
                    }
                }
            }
            // Theme the selected tab glyph immediately. Each tab’s `NavigationStack` keeps
            // `.tint(Color.primary)` so toolbars don’t pick up the accent — without this,
            // UIKit re-tint on tab change lags a frame and flashes system blue.
            .tint(tabBarTheme.color)
            .tabViewSearchActivation(.searchTabSelection)
            .modifier(
                TabBarThemeModifier(
                    theme: tabBarTheme,
                    badgeCount: listTabUncheckedBadge,
                    selectedTab: selectedTab,
                    paintsStoreAddSymbol: selectedTab.showsStoreSideAddControl
                )
            )
            .background {
                ListTabDiveTargetReader(point: $listTabDiveTargetPoint)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .catalogGroupedChromeBackdrop()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if blocksInteractionUntilFirstItemExplainer {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(140)
                    .accessibilityHidden(true)
            }

            if let dive = firstAddToListDive.payload {
                FirstAddToListDiveOverlay(
                    itemName: dive.itemName,
                    sourceFrame: dive.sourceFrame,
                    targetPoint: activeDiveTargetPoint,
                    onPlusOneFinished: {
                        suppressListTabBadgeForFirstAddDive = false
                    },
                    onFinished: completeFirstAddToListDive
                )
                .allowsHitTesting(false)
                .zIndex(150)
            }

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

    /// Home tab: rooted catalog (no back chevron). Edit enters reorder directly; ⋯ hosts
    /// home sections / create / saved lists; search is a minimized bottom-trailing control.
    private var homeCatalogTabScreen: some View {
        InventoryView(
            isReorderMode: $isInventoryReorderMode,
            usesHomeToolbarSearch: true,
            isHomeToolbarSearchPresented: $isHomeToolbarSearchPresented,
            homeSearchText: $homeInventorySearchText,
            minimizesToolbarSearch: true,
            showsToolbarSearchButton: false,
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
            onReturnToStoreAfterRecipeApply: { selectedTab = .store },
            onFirstHomeAddDive: beginFirstAddToListDiveIfNeeded,
            onEditItem: { item in
                inventoryCatalogEditorItem = item
            },
            onDeleteItem: { item in
                inventoryCatalogDeleteConfirmationItem = item
            }
        )
        .navigationBarBackButtonHidden(true)
        .enablesNavigationInteractivePopGesture(isEnabled: !isInventoryReorderMode)
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

    var body: some View {
        tabChrome
        .onChange(of: selectedTab) { previous, current in
            // Intercept side-tab taps: bounce back and trigger the associated action.
            if current == .storeAdd {
                tabBarSearchText = ""
                bounceTabSelection(to: .store)
                beginStoreTabPullToAdd()
                return
            }
            if current == .homeSearch {
                tabBarSearchText = ""
                bounceTabSelection(to: .home)
                // Present after the bounce so Home’s searchable mounts on the Library
                // tab (not during the brief search-role selection).
                DispatchQueue.main.async {
                    isHomeToolbarSearchPresented = true
                }
                return
            }
            if current == .home {
                hasVisitedHomeCatalog = true
            }
            if current == .store {
                isHomeToolbarSearchPresented = false
                scheduleStoreGesturesExplainerIfNeeded()
            }
            if previous == .home {
                if isInventoryReorderMode {
                    isInventoryReorderMode = false
                }
                // Clear shared expansion now; remount rows when Library becomes active again
                // (off-screen Home won't apply local `@State` resets until then).
                if expandedHomeQuantityPillItemID != nil {
                    homeQuantityPillNeedsChromeReset = true
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    expandedHomeQuantityPillItemID = nil
                }
            }
            if current == .home, homeQuantityPillNeedsChromeReset {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    homeQuantityPillChromeID = UUID()
                    homeQuantityPillNeedsChromeReset = false
                }
            }
        }
        .onAppear {
            if selectedTab == .home {
                hasVisitedHomeCatalog = true
            }
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
            selectedTab = .store
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

    /// Immediately returns the tab selection without animation so intercept-only tabs never stay selected.
    private func bounceTabSelection(to target: TabSelection) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = target
        }
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
        guard !firstAddToListDive.isActive else { return }
        dismissKeyboardForFirstItemExplainer()
        firstShoppingItemExplainerTask?.cancel()
        firstShoppingItemExplainerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            guard !hasSeenFirstShoppingItemExplainer else { return }
            guard !firstAddToListDive.isActive else { return }
            guard !store.shopping.isEmpty else { return }
            guard fullWindowOverlay.kind == nil else { return }
            fullWindowOverlay.presentFirstShoppingItemExplainer()
        }
    }

    private func beginFirstAddToListDiveIfNeeded(itemName: String, sourceFrame: CGRect) {
        guard !hasSeenFirstShoppingItemExplainer else { return }
        guard !firstAddToListDive.isActive else { return }
        firstShoppingItemExplainerTask?.cancel()
        // Straight vertical dive: keep the item’s x, use List-tab bar height for y.
        let listTabY =
            (listTabDiveTargetPoint == .zero
                ? (ListTabIconFrameLocator.listTabIconCenterInWindow() ?? listTabDiveFallbackPoint)
                : listTabDiveTargetPoint).y
        activeDiveTargetPoint = CGPoint(x: sourceFrame.midX, y: listTabY)
        suppressListTabBadgeForFirstAddDive = true
        blocksInteractionUntilFirstItemExplainer = true
        firstAddToListDive.begin(itemName: itemName, sourceFrame: sourceFrame)
        // Invalid source frame: fall through to the normal explainer delay.
        if !firstAddToListDive.isActive {
            suppressListTabBadgeForFirstAddDive = false
            blocksInteractionUntilFirstItemExplainer = false
            scheduleFirstShoppingItemExplainerIfNeeded()
        }
    }

    private func completeFirstAddToListDive() {
        firstAddToListDive.complete()
        // After the dive +1, wait briefly before the explainer.
        guard !hasSeenFirstShoppingItemExplainer else {
            blocksInteractionUntilFirstItemExplainer = false
            return
        }
        dismissKeyboardForFirstItemExplainer()
        firstShoppingItemExplainerTask?.cancel()
        firstShoppingItemExplainerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard !hasSeenFirstShoppingItemExplainer else {
                blocksInteractionUntilFirstItemExplainer = false
                return
            }
            guard !store.shopping.isEmpty else {
                blocksInteractionUntilFirstItemExplainer = false
                return
            }
            guard fullWindowOverlay.kind == nil else {
                blocksInteractionUntilFirstItemExplainer = false
                return
            }
            fullWindowOverlay.presentFirstShoppingItemExplainer()
            blocksInteractionUntilFirstItemExplainer = false
        }
    }

    /// Fallback when the live tab probe hasn’t published yet (2-tab centered bar).
    private var listTabDiveFallbackPoint: CGPoint {
        let bounds = keyWindowSceneBounds
        return CGPoint(x: bounds.midX - bounds.width * 0.12, y: bounds.height - 40)
    }

    private var keyWindowSceneBounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene =
            scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        return scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    private func completeFirstShoppingItemExplainer() {
        hasSeenFirstShoppingItemExplainer = true
        blocksInteractionUntilFirstItemExplainer = false
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

    /// First visit to a non-empty List (Store tab). Waits for the first-item explainer
    /// when both are pending so they don't race.
    private func scheduleStoreGesturesExplainerIfNeeded() {
        guard !hasSeenStoreGesturesExplainer else { return }
        guard hasSeenFirstShoppingItemExplainer else { return }
        guard !store.shopping.isEmpty else { return }
        guard selectedTab == .store else { return }
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
            guard selectedTab == .store else { return }
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

    func makeUIViewController(context: Context) -> UIViewController {
        NavigationInteractivePopEnablerViewController(isPopEnabled: isEnabled)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let controller = uiViewController as? NavigationInteractivePopEnablerViewController else { return }
        controller.isPopEnabled = isEnabled
        controller.applyInteractivePopGestureState()
    }

    private final class NavigationInteractivePopEnablerViewController: UIViewController {
        private let popGestureDelegate = NavigationInteractivePopGestureDelegate()
        private var coordinatedScrollViews = NSHashTable<UIScrollView>.weakObjects()
        var isPopEnabled: Bool

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
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyInteractivePopGestureState()
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
    func enablesNavigationInteractivePopGesture(isEnabled: Bool = true) -> some View {
        background(NavigationInteractivePopEnabler(isEnabled: isEnabled))
    }
}

/// SF Symbol `plus` rendered with `.alwaysOriginal` tint for the Store side-add control.
private enum StoreSideAddSymbol {
    static func image(color: Color) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let base = UIImage(systemName: "plus", withConfiguration: config) ?? UIImage()
        return base.withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
    }
}

/// Themes selected tab symbols and List tab badge via tint only.
/// Do not replace `standardAppearance` / `scrollEdgeAppearance` — that can collapse
/// Liquid Glass’s separated search-button layout back into the main capsule.
private struct TabBarThemeModifier: ViewModifier {
    var theme: AppThemeSelection
    var badgeCount: Int
    var selectedTab: TabSelection
    /// When true, restamp the trailing side-tab glyph as a themed + (image only).
    var paintsStoreAddSymbol: Bool = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Immediate + deferred: SwiftUI attaches `.badge` after first layout, and
                // that pass uses the default red unless we stamp `badgeColor` again.
                Self.apply(theme.color, paintsStoreAddSymbol: paintsStoreAddSymbol)
                Self.reapplyAfterLayout(theme.color, paintsStoreAddSymbol: paintsStoreAddSymbol)
            }
            .onChange(of: theme) { _, newTheme in
                Self.apply(newTheme.color, paintsStoreAddSymbol: paintsStoreAddSymbol)
                Self.reapplyAfterLayout(newTheme.color, paintsStoreAddSymbol: paintsStoreAddSymbol)
            }
            .onChange(of: badgeCount) { _, _ in
                Self.reapplyAfterLayout(theme.color, paintsStoreAddSymbol: paintsStoreAddSymbol)
            }
            .onChange(of: selectedTab) { _, _ in
                // Immediate + deferred: tab swaps remount the side control and can reset
                // UIKit tint for a frame without the synchronous pass.
                Self.apply(theme.color, paintsStoreAddSymbol: paintsStoreAddSymbol)
                Self.reapplyAfterLayout(theme.color, paintsStoreAddSymbol: paintsStoreAddSymbol)
            }
            .onChange(of: paintsStoreAddSymbol) { _, paints in
                Self.apply(theme.color, paintsStoreAddSymbol: paints)
                Self.reapplyAfterLayout(theme.color, paintsStoreAddSymbol: paints)
            }
    }

    private static func reapplyAfterLayout(_ color: Color, paintsStoreAddSymbol: Bool) {
        Task { @MainActor in
            await Task.yield()
            apply(color, paintsStoreAddSymbol: paintsStoreAddSymbol)
            await Task.yield()
            apply(color, paintsStoreAddSymbol: paintsStoreAddSymbol)
        }
    }

    private static func apply(_ color: Color, paintsStoreAddSymbol: Bool) {
        let uiColor = UIColor(color)
        UITabBar.appearance().tintColor = uiColor
        // Future tab items (including the first `.badge` attach) inherit theme, not system red.
        UITabBarItem.appearance().badgeColor = uiColor

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                paintLiveTabBars(in: window, color: uiColor, paintsStoreAddSymbol: paintsStoreAddSymbol)
            }
        }
    }

    private static func paintLiveTabBars(in view: UIView, color: UIColor, paintsStoreAddSymbol: Bool) {
        if let tabBar = view as? UITabBar {
            tabBar.tintColor = color
            tabBar.items?.forEach { $0.badgeColor = color }
            // Swap only the glyph — do not replace the tab item (that collapses search separation).
            if paintsStoreAddSymbol, let side = tabBar.items?.last {
                let plus = StoreSideAddSymbol.image(color: Color(uiColor: color))
                side.image = plus
                side.selectedImage = plus
                side.title = LocalizedCopy.addItem
            }
        }
        for subview in view.subviews {
            paintLiveTabBars(in: subview, color: color, paintsStoreAddSymbol: paintsStoreAddSymbol)
        }
    }
}
