import SwiftUI
import UIKit

private enum HomeCatalogEditModeTiming {
    static let chromeDelayMs: UInt64 = 280
    static let statusFadeDuration: TimeInterval = 0.2
}

/// Stable nav-bar `ToolbarItem` ids so browse↔edit morphs matching slots (not insert/remove).
private enum HomeCatalogTopToolbarItemID {
    static let principal = "homeCatalogPrincipal"
    static let leadingEditDone = "homeCatalogLeadingEditDone"
    /// Browse ⋯ and edit Move share this slot (1:1 morph).
    static let trailingPrimary = "homeCatalogTrailingPrimary"
    static let trailingDelete = "homeCatalogTrailingDelete"
    /// Push-model Home: Edit/Done share one trailing identity.
    static let pushEditDone = "homeCatalogEditDone"
}

struct InventoryView: View {
    private static let bottomFloatingBarClearance: CGFloat = 86
    /// Extra space below the no-match placeholder so it stays above the toolbar search field.
    private static let toolbarSearchFieldClearance: CGFloat = 56
    /// Pull-to-add collapses the principal nav header; reserve its height so no-match content stays centered.
    private static let toolbarSearchCollapsedTopChromeClearance: CGFloat = 100
    /// Delay before deferred edit row chrome (reorder handles) mounts after `EditMode` activates.
    private static let homeEditModeChromeDelayMs = HomeCatalogEditModeTiming.chromeDelayMs
    /// Extra space below the no-match band on Home (below section title bar).
    private static let toolbarSearchNoMatchesVerticalOffset: CGFloat = 25
    /// Absorbs taps that miss the Liquid Glass search control (visual chrome is taller than its hit target).
    /// Top aligns with content layout bottom (top of search chrome); height reaches the screen bottom.
    private static let toolbarSearchHitThroughBlockerHeight: CGFloat = 100
    /// Content layout bottom sits just above the bottom-toolbar search chrome — shift the blocker down onto it.
    /// Keep equal to height so the top edge stays put while the band extends to the screen bottom.
    private static let toolbarSearchHitThroughBlockerOffsetY: CGFloat = toolbarSearchHitThroughBlockerHeight
    @EnvironmentObject private var store: GroceryStore
    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.appTheme) private var appTheme
    @Environment(\.shoppingListSpacingScale) private var listSpacingScale
    @Environment(\.dismissSearch) private var dismissSearch
    @AppStorage(AppTextSize.storageKey) private var textSizeRaw: String = AppTextSize.defaultSize.rawValue

    @Binding var isReorderMode: Bool
    /// Home: Liquid Glass toolbar search (`searchable` + toolbar search placement).
    var usesHomeToolbarSearch: Bool = false
    /// Drives `searchable(isPresented:)` for toolbar search on Home.
    @Binding var isHomeToolbarSearchPresented: Bool
    @Binding var homeSearchText: String
    /// Only one Home quantity pill stepper is expanded at a time (owned by tab root so leave-Library can collapse immediately).
    @Binding var expandedHomeQuantityPillItemID: UUID?
    /// Identity token remounting Home pills after leave-Library collapse (avoids deferred animation).
    var homeQuantityPillChromeID: UUID = UUID()
    /// Toolbar `searchable` prompt.
    var toolbarSearchPrompt: String = LocalizedCopy.searchOrCreateItem
    /// Home: Return-key submit, exact match, new item sheet.
    var toolbarSearchUsesSubmitBehavior: Bool = true
    /// EXPERIMENT (tabs): collapse the bottom toolbar search field into a compact trailing button.
    var minimizesToolbarSearch: Bool = false
    /// EXPERIMENT (tabs): Saved lists button in the top bar (leading) instead of next to bottom search.
    var showsRecipesInTopBarLeading: Bool = false
    var bottomReservedHeight: CGFloat = InventoryView.bottomFloatingBarClearance
    var hidesNavigationBar: Bool = true
    var ignoresSafeArea: Bool = true
    var showsShoppingStatus: Bool = true
    /// Invoked when the user taps a row in reorder mode (present editor at the root).
    var onEditItem: (GroceryItem) -> Void
    /// Invoked when the user chooses Delete from a browse-mode context menu.
    var onDeleteItem: (GroceryItem) -> Void
    /// Home search Return with no exact catalog match — present add-item sheet with this name prefilled.
    var onPresentNewItemFromSearch: (String) -> Void = { _ in }
    /// Home edit mode: + in the bottom toolbar next to search.
    var onToolbarAddItem: (() -> Void)? = nil
    /// Home edit mode: **Sections** menu → Home or Store section editor sheet.
    var onToolbarSelectGroupsKind: ((Tag.Kind) -> Void)? = nil
    /// Pushed Home catalog: chevron back to Store (no ⋯ menu).
    var onBackToStore: (() -> Void)? = nil
    /// After adding a recipe to the shopping list, pop back to Store.
    var onReturnToStoreAfterRecipeApply: (() -> Void)? = nil
    /// First empty→non-empty Home add: item name + global title frame for the List-tab dive.
    var onFirstHomeAddDive: ((String, CGRect) -> Void)? = nil

    @State private var rowAnchors: [HomeCatalogRowAnchor] = []
    /// Latest global frames for Home row titles (drive first-add dive source).
    @State private var homeItemNameGlobalFrames: [UUID: CGRect] = [:]
    @State private var listScrollSnapshot = HomeCatalogListScrollSnapshot(
        viewportHeight: 0,
        contentTopInset: 0
    )
    @State private var activeSectionID: UUID?
    @State private var isProgrammaticListScroll = false
    @State private var scrollToSectionID: UUID?
    @State private var isUndefinedSectionRevealed = false
    /// Home: toolbar edit chrome (Select / Done / bottom bar).
    /// Home list `editMode` — local so parent/toolbar animation transactions never re-animate row layout.
    @State private var homeListEditMode: EditMode = .inactive
    /// Row layout/interaction chrome (reorder handles, selection tap) — deferred after shopping status hides.
    @State private var showsHomeEditRowChrome = false
    /// Shopping row status (theme tint + quantity pill) — hidden before edit handles, restored after.
    @State private var showsHomeRowShoppingStatus = true
    /// Top-bar Move → “New section” name prompt (SwiftUI Menu can’t host UIKit alert anchors cleanly).
    @State private var homeMoveNewSectionKind: Tag.Kind?
    @State private var homeMoveNewSectionName = ""
    @State private var deactivateHomeEditRowChromeTask: Task<Void, Never>?
    /// Toolbar search: deferred each Home visit so bottom-bar search mounts after the push settles.
    @State private var attachLiquidGlassToolbarSearch = false
    @State private var liquidGlassToolbarSearchAttachTask: Task<Void, Never>?
    /// Fresh identity each Home visit so SwiftUI cannot reuse a cached toolbar search controller.
    @State private var homeToolbarSearchChromeID = UUID()
    @State private var homeToolbarSearchPlaceholderPinTask: Task<Void, Never>?
    /// IDs of items currently selected in edit mode.
    @State private var selectedItemIDs: Set<UUID> = []
    /// Pinned query after adding an item in Home search — keeps matched results
    /// visible even after homeSearchText is cleared, mirroring pull-to-add behaviour.
    @State private var homeSearchPinnedQuery: String = ""
    @State private var isPresentingRecipes = false

    init(
        isReorderMode: Binding<Bool> = .constant(false),
        usesHomeToolbarSearch: Bool = false,
        isHomeToolbarSearchPresented: Binding<Bool> = .constant(false),
        homeSearchText: Binding<String> = .constant(""),
        toolbarSearchPrompt: String = LocalizedCopy.searchOrCreateItem,
        toolbarSearchUsesSubmitBehavior: Bool = true,
        minimizesToolbarSearch: Bool = false,
        showsRecipesInTopBarLeading: Bool = false,
        bottomReservedHeight: CGFloat = InventoryView.bottomFloatingBarClearance,
        hidesNavigationBar: Bool = true,
        ignoresSafeArea: Bool = true,
        showsShoppingStatus: Bool = true,
        expandedHomeQuantityPillItemID: Binding<UUID?> = .constant(nil),
        homeQuantityPillChromeID: UUID = UUID(),
        onPresentNewItemFromSearch: @escaping (String) -> Void = { _ in },
        onToolbarAddItem: (() -> Void)? = nil,
        onToolbarSelectGroupsKind: ((Tag.Kind) -> Void)? = nil,
        onBackToStore: (() -> Void)? = nil,
        onReturnToStoreAfterRecipeApply: (() -> Void)? = nil,
        onFirstHomeAddDive: ((String, CGRect) -> Void)? = nil,
        onEditItem: @escaping (GroceryItem) -> Void = { _ in },
        onDeleteItem: @escaping (GroceryItem) -> Void = { _ in }
    ) {
        _isReorderMode = isReorderMode
        self.usesHomeToolbarSearch = usesHomeToolbarSearch
        _isHomeToolbarSearchPresented = isHomeToolbarSearchPresented
        _homeSearchText = homeSearchText
        _expandedHomeQuantityPillItemID = expandedHomeQuantityPillItemID
        self.homeQuantityPillChromeID = homeQuantityPillChromeID
        self.toolbarSearchPrompt = toolbarSearchPrompt
        self.toolbarSearchUsesSubmitBehavior = toolbarSearchUsesSubmitBehavior
        self.minimizesToolbarSearch = minimizesToolbarSearch
        self.showsRecipesInTopBarLeading = showsRecipesInTopBarLeading
        self.bottomReservedHeight = bottomReservedHeight
        self.hidesNavigationBar = hidesNavigationBar
        self.ignoresSafeArea = ignoresSafeArea
        self.showsShoppingStatus = showsShoppingStatus
        self.onPresentNewItemFromSearch = onPresentNewItemFromSearch
        self.onToolbarAddItem = onToolbarAddItem
        self.onToolbarSelectGroupsKind = onToolbarSelectGroupsKind
        self.onBackToStore = onBackToStore
        self.onReturnToStoreAfterRecipeApply = onReturnToStoreAfterRecipeApply
        self.onFirstHomeAddDive = onFirstHomeAddDive
        self.onEditItem = onEditItem
        self.onDeleteItem = onDeleteItem
    }

    private var trimmedToolbarSearchText: String {
        homeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Toolbar search UI is up and the field is empty — show no rows.
    private var toolbarSearchEmptyQueryActive: Bool {
        usesHomeToolbarSearch && isHomeToolbarSearchPresented && activeHomeSearchQuery.isEmpty
    }

    /// Live query takes priority; falls back to pinned query so results stay
    /// visible after the field is cleared following an add-to-shopping tap.
    private var activeHomeSearchQuery: String {
        let trimmed = trimmedToolbarSearchText
        return trimmed.isEmpty ? homeSearchPinnedQuery : trimmed
    }

    private var catalogItemsForList: [GroceryItem] {
        guard usesHomeToolbarSearch else { return store.catalog }
        let query = activeHomeSearchQuery
        if isHomeToolbarSearchPresented, query.isEmpty { return [] }
        if query.isEmpty { return store.catalog }
        return filteredCatalogItems(matching: query)
    }

    private func filteredCatalogItems(matching query: String) -> [GroceryItem] {
        guard !CatalogSearchNormalization.normalizedForMatching(query).isEmpty else { return [] }
        return store.catalog.filter { item in
            CatalogSearchNormalization.localizedCaseInsensitiveContains(
                searchQuery: query,
                in: item.displayName(appContentLanguage: catalogLanguage)
            )
        }
    }

    /// Toolbar search has a query that matches nothing in the catalog.
    private var toolbarSearchNoMatches: Bool {
        usesHomeToolbarSearch
            && isHomeToolbarSearchPresented
            && !trimmedToolbarSearchText.isEmpty
            && catalogItemsForList.isEmpty
    }

    /// Extra top inset for the no-match band when Home’s principal toolbar is hidden (pull-to-add search).
    private var toolbarSearchNoMatchesExtraTopInset: CGFloat {
        guard toolbarSearchNoMatches, !showsHomeMainTabToolbarControls else { return 0 }
        return Self.toolbarSearchCollapsedTopChromeClearance
    }

    /// Home toolbar chrome (Edit, ⋯ anchor).
    private var showsHomeMainTabToolbarControls: Bool {
        usesHomeToolbarSearch
    }

    /// Edit toolbar: visible whenever Home toolbar chrome is shown.
    private var showsHomeEditToolbar: Bool {
        showsHomeMainTabToolbarControls
    }

    /// Principal header: browse shows title + count; active search shows "Search items" (+ match count when querying).
    private var showsHomeCatalogPrincipalToolbar: Bool {
        guard showsHomeMainTabToolbarControls, !store.catalog.isEmpty else { return false }
        return true
    }

    private var homeCatalogPrincipalIsSearchMode: Bool {
        usesHomeToolbarSearch && isHomeToolbarSearchPresented
    }

    private var homeCatalogPrincipalSearchSubtitleText: String {
        guard !activeHomeSearchQuery.isEmpty else { return "" }
        if catalogItemsForList.isEmpty {
            return LocalizedCopy.noMatchingItemsFound
        }
        return LocalizedCopy.searchItemsFound(catalogItemsForList.count)
    }

    private var homeCatalogPrincipalAccessibilityLabel: String {
        if homeCatalogPrincipalIsSearchMode {
            let subtitle = homeCatalogPrincipalSearchSubtitleText
            guard !subtitle.isEmpty else { return LocalizedCopy.searchLibrary }
            if catalogItemsForList.isEmpty {
                return "\(LocalizedCopy.searchLibrary), \(subtitle)"
            }
            return "\(LocalizedCopy.searchLibrary), \(LocalizedCopy.searchItemsFoundAccessibilityLabel(catalogItemsForList.count))"
        }
        return LocalizedCopy.homeLibraryAccessibilityLabel(
            title: LocalizedCopy.homeLibrary,
            itemCount: store.catalog.count
        )
    }

    /// Home (pushed from Store): back chevron in the navigation bar.
    private var showsHomeBackToolbar: Bool {
        usesHomeToolbarSearch && onBackToStore != nil
    }

    private var showsCatalogListRows: Bool {
        !toolbarSearchEmptyQueryActive && !toolbarSearchNoMatches
    }

    private var catalogTextDynamicTypeSize: DynamicTypeSize {
        AppTextSize.resolved(from: textSizeRaw).dynamicTypeSize
    }

    /// Top-bar edit chrome swaps with `EditMode`; native toolbar morphs via `.animation(.default, …)`.
    private var showsHomeEditToolbarChrome: Bool {
        homeListEditMode == .active
    }

    /// Bottom-bar edit chrome matches top-bar.
    private var showsHomeBottomEditToolbarChrome: Bool {
        homeListEditMode == .active
    }

    private var homeCatalogListEditMode: Binding<EditMode> {
        Binding(
            get: { homeListEditMode },
            set: { newMode in
                // Only honour externally-driven deactivation (e.g. system swipe-to-delete dismiss).
                // Activation is always initiated through enterHomeCatalogReorderMode(), so we block
                // any gesture-driven .active push from the List.
                guard newMode != .active else { return }
                deactivateHomeCatalogEditMode()
            }
        )
    }

    /// Drives `HomeToolbarSearchModifier` / return-submit (defers bottom-bar search until push settles).
    private var isHomeToolbarSearchChromeActive: Bool {
        guard usesHomeToolbarSearch else { return false }
        // EXPERIMENT (tabs): keep searchable mounted across Edit/Done so List reorder/select
        // handle animations aren't torn down. Bottom bar always hosts minimized search.
        if minimizesToolbarSearch { return true }
        return attachLiquidGlassToolbarSearch
    }

    private var unsortedInventorySectionID: UUID? {
        store.inventoryTags.first(where: { Tag.isUnsortedBucket($0) })?.id
    }

    private var allGroupedCatalog: [(Tag, [GroceryItem])] {
        var bucket: [UUID: [GroceryItem]] = [:]
        for item in store.catalog {
            bucket[item.inventoryTagID, default: []].append(item)
        }
        return store.inventoryTags
            .compactMap { tag in
                guard tag.kind == .inventory else { return nil }
                let items = bucket[tag.id] ?? []
                guard !items.isEmpty else { return nil }
                return (tag, items)
            }
    }

    private var displayedGroupedCatalog: [(Tag, [GroceryItem])] {
        var bucket: [UUID: [GroceryItem]] = [:]
        for item in catalogItemsForList {
            bucket[item.inventoryTagID, default: []].append(item)
        }
        return store.inventoryTags
            .compactMap { tag in
                guard tag.kind == .inventory else { return nil }
                let items = bucket[tag.id] ?? []
                guard !items.isEmpty else { return nil }
                return (tag, items)
            }
            .filter { isSectionVisibleInList($0.0) }
    }

    private var groupedCatalogForSectionTitles: [(Tag, [GroceryItem])] {
        if usesHomeToolbarSearch, isHomeToolbarSearchPresented {
            var bucket: [UUID: [GroceryItem]] = [:]
            for item in catalogItemsForList {
                bucket[item.inventoryTagID, default: []].append(item)
            }
            return store.inventoryTags
                .compactMap { tag in
                    guard tag.kind == .inventory else { return nil }
                    let items = bucket[tag.id] ?? []
                    guard !items.isEmpty else { return nil }
                    return (tag, items)
                }
        }
        return allGroupedCatalog
    }

    private var homeCatalogSectionTitles: [(id: UUID, title: String)] {
        groupedCatalogForSectionTitles.map { tag, _ in
            (id: tag.id, title: tag.displayTitle(appContentLanguage: catalogLanguage))
        }
    }

    private var showsHomeCatalogSectionTitleBar: Bool {
        guard !store.catalog.isEmpty else { return false }
        if usesHomeToolbarSearch, isHomeToolbarSearchPresented {
            return !homeCatalogSectionTitles.isEmpty
        }
        return !allGroupedCatalog.isEmpty
    }

    private func isSectionVisibleInList(_ tag: Tag) -> Bool {
        if usesHomeToolbarSearch,
           isHomeToolbarSearchPresented,
           !activeHomeSearchQuery.isEmpty {
            return true
        }
        guard let unsortedID = unsortedInventorySectionID, tag.id == unsortedID else { return true }
        return isUndefinedSectionRevealed
    }

    private func syncActiveSectionToVisibleTitles() {
        let visibleIDs = Set(homeCatalogSectionTitles.map(\.id))
        guard !visibleIDs.isEmpty else { return }
        if let activeSectionID, visibleIDs.contains(activeSectionID) { return }
        activeSectionID = homeCatalogSectionTitles.first?.id
    }

    private func isUnsortedSectionID(_ sectionID: UUID) -> Bool {
        sectionID == unsortedInventorySectionID
    }

    private var grouped: [(Tag, [GroceryItem])] {
        displayedGroupedCatalog
    }

    private func catalogItemMatchingSearchTermExactly(_ trimmed: String) -> GroceryItem? {
        let query = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !CatalogSearchNormalization.normalizedForMatching(query).isEmpty else { return nil }
        return store.catalog.first { item in
            CatalogSearchNormalization.localizedCaseInsensitiveEquals(
                item.displayName(appContentLanguage: catalogLanguage).trimmingCharacters(in: .whitespacesAndNewlines),
                query
            )
        }
    }

    /// Return on the search field: **empty** always runs our dismiss path (Home) so
    /// `isHomeToolbarSearchPresented` / `dismissSearch()` stay in sync with the system toolbar — otherwise the bottom bar
    /// animation can stick. **Non-empty** only runs shopping submit when `toolbarSearchUsesSubmitBehavior` is true.
    private func handleToolbarSearchSubmit() {
        guard usesHomeToolbarSearch else { return }
        let trimmed = trimmedToolbarSearchText
        if trimmed.isEmpty {
            if toolbarSearchUsesSubmitBehavior {
                dismissHomeToolbarSearchAfterSubmit()
            } else {
                dismissToolbarSearchForEditPresentation()
            }
            return
        }
        guard toolbarSearchUsesSubmitBehavior else { return }
        if let match = catalogItemMatchingSearchTermExactly(trimmed) {
            store.addToShopping(itemID: match.id, quantity: 1)
            homeSearchText = ""
            dismissHomeToolbarSearchAfterSubmit()
            return
        }
        onPresentNewItemFromSearch(trimmed)
    }

    private func dismissHomeToolbarSearchAfterSubmit() {
        isHomeToolbarSearchPresented = false
        Task { @MainActor in
            await Task.yield()
            dismissSearch()
        }
    }

    /// Clears toolbar search before presenting the item editor.
    private func dismissToolbarSearchForEditPresentation() {
        homeSearchText = ""
        isHomeToolbarSearchPresented = false
        Task { @MainActor in
            await Task.yield()
            dismissSearch()
        }
    }

    private func dismissToolbarSearchBeforePresentingItemEditorIfNeeded() {
        guard usesHomeToolbarSearch, isHomeToolbarSearchPresented else { return }
        dismissToolbarSearchForEditPresentation()
    }

    private func toggleHomeItemShopping(
        itemID: UUID,
        onAddedToShopping: (() -> Void)? = nil
    ) {
        if expandedHomeQuantityPillItemID == itemID {
            return
        }
        // Match auto-collapse: animate the previous pill closed in the same spring transaction.
        // A bare `= nil` still triggers implicit text/gutter animations and flashes on LTR.
        withAnimation(QuantityPillChromeTiming.expandCollapse) {
            expandedHomeQuantityPillItemID = nil
        }
        if store.shopping.contains(where: { $0.itemID == itemID }) {
            store.removeFromShopping(itemID: itemID)
        } else {
            let wasShoppingEmpty = store.shopping.isEmpty
            store.addToShopping(itemID: itemID, quantity: 1)
            onAddedToShopping?()
            if wasShoppingEmpty,
               let onFirstHomeAddDive,
               let frame = homeItemNameGlobalFrames[itemID],
               let item = store.item(for: itemID) {
                onFirstHomeAddDive(
                    item.displayName(appContentLanguage: catalogLanguage),
                    frame
                )
            }
            QuantityPillChromeTiming.expandAfterAdd(
                itemID: itemID,
                guardInShopping: { [store] in
                    store.shopping.contains(where: { $0.itemID == itemID })
                },
                setExpandedItemID: { expandedHomeQuantityPillItemID = $0 }
            )
        }
    }

    private func hideHomeRowShoppingStatusForEditEntry() {
        deactivateHomeEditRowChromeTask?.cancel()
        deactivateHomeEditRowChromeTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsHomeRowShoppingStatus = false
        }
    }

    private func showHomeRowShoppingStatusImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsHomeRowShoppingStatus = true
        }
    }

    private func finishHomeCatalogEditModeDeactivation() {
        deactivateHomeEditRowChromeTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsHomeEditRowChrome = false
            isReorderMode = false
            selectedItemIDs = []
        }
    }

    private func deactivateHomeCatalogEditMode(animated: Bool = true) {
        deactivateHomeEditRowChromeTask?.cancel()

        guard homeListEditMode != .inactive else {
            showHomeRowShoppingStatusImmediately()
            finishHomeCatalogEditModeDeactivation()
            return
        }

        if animated {
            showHomeRowShoppingStatusImmediately()
            // Drop list/parent chrome before the toolbar morph — doing it after ~280ms
            // reflows the bar at the end of ⋯↔Move/Delete.
            finishHomeCatalogEditModeDeactivation()
            deactivateHomeEditRowChromeTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.default) {
                    homeListEditMode = .inactive
                }
            }
        } else {
            homeListEditMode = .inactive
            showHomeRowShoppingStatusImmediately()
            finishHomeCatalogEditModeDeactivation()
        }
    }

    private func enterHomeCatalogReorderMode() {
        deactivateHomeEditRowChromeTask?.cancel()
        hideHomeRowShoppingStatusForEditEntry()
        deactivateHomeEditRowChromeTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, homeListEditMode == .inactive else { return }
            withAnimation(.default) {
                homeListEditMode = .active
            }
            // Mount list handles / parent binding immediately (unanimated). Delaying this to
            // chromeDelayMs landed on the trailing morph's settle and caused a late jump.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showsHomeEditRowChrome = true
                isReorderMode = true
            }
            deactivateHomeEditRowChromeTask = nil
        }
    }

    private func exitHomeCatalogReorderMode() {
        deactivateHomeCatalogEditMode()
    }

    private func deleteSelectedItems() {
        let toDelete = selectedItemIDs
        withAnimation(.snappy) {
            for id in toDelete {
                store.deleteCatalogItem(id)
            }
        }
        selectedItemIDs = []
    }

    private func moveSelectedItems(toInventoryTagID tagID: UUID) {
        for id in selectedItemIDs {
            guard var item = store.item(for: id) else { continue }
            item.inventoryTagID = tagID
            store.updateCatalogItem(item)
        }
        selectedItemIDs = []
    }

    private func moveSelectedItems(toShoppingTagID tagID: UUID) {
        for id in selectedItemIDs {
            guard var item = store.item(for: id) else { continue }
            item.shoppingTagID = tagID
            store.updateCatalogItem(item)
        }
        selectedItemIDs = []
    }

    private func createInventorySectionAndMoveSelected(named displayTitle: String) {
        let stored = CatalogContentLocalization.storedTagTitle(
            fromDisplay: displayTitle,
            language: catalogLanguage
        )
        guard let tagID = store.addTag(kind: .inventory, title: stored) else { return }
        moveSelectedItems(toInventoryTagID: tagID)
    }

    private func createShoppingSectionAndMoveSelected(named displayTitle: String) {
        let stored = CatalogContentLocalization.storedTagTitle(
            fromDisplay: displayTitle,
            language: catalogLanguage
        )
        guard let tagID = store.addTag(kind: .shopping, title: stored) else { return }
        moveSelectedItems(toShoppingTagID: tagID)
    }

    /// Rows for one inventory group. `.onMove` is attached only in edit mode so browse long-press opens the editor instead of reordering.
    @ViewBuilder
    private func catalogGroupItems(
        items: [GroceryItem],
        sectionID: UUID,
        sectionIndex: Int,
        totalSectionCount: Int,
        isReorderMode: Bool,
        showsRowShoppingStatus: Bool,
        usesHomePlainListChrome: Bool = false,
        onAddedToShopping: (() -> Void)? = nil
    ) -> some View {
        let hasFollowingSection = sectionIndex < totalSectionCount - 1
        let rows = ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
            HomeCatalogListItemCell(
                showsSectionDividerBelow: hasFollowingSection && itemIndex == items.count - 1,
                sectionScrollID: itemIndex == 0 ? sectionID : nil
            ) {
                Group {
                    if usesHomePlainListChrome {
                        homeInventoryCatalogRow(
                            item: item,
                            isReorderMode: isReorderMode,
                            showsRowShoppingStatus: showsRowShoppingStatus,
                            onEdit: {
                                dismissToolbarSearchBeforePresentingItemEditorIfNeeded()
                                onEditItem(item)
                            },
                            onAddedToShopping: onAddedToShopping
                        )
                    } else {
                        InventoryCatalogRow(
                            item: item,
                            isReorderMode: isReorderMode,
                            showsShoppingStatus: showsShoppingStatus,
                            expandedQuantityPillItemID: $expandedHomeQuantityPillItemID,
                            quantityPillChromeID: homeQuantityPillChromeID,
                            enablesLongPressToEdit: true,
                            onSelectToggleShopping: {},
                            onAddedToShopping: onAddedToShopping,
                            onEdit: {
                                dismissToolbarSearchBeforePresentingItemEditorIfNeeded()
                                onEditItem(item)
                            }
                        )
                    }
                }
            }
            .id(item.id)
            .reportHomeCatalogRowAnchor(sectionID: sectionID)
        }
        rows.onMove { source, destination in
            guard homeListEditMode == .active else { return }
            store.moveCatalogItems(
                withinInventoryTagID: sectionID,
                displayedItemIDs: items.map(\.id),
                fromOffsets: source,
                toOffset: destination
            )
        }
    }

    @ViewBuilder
    private var homeCatalogResultsList: some View {
        Group {
            if showsCatalogListRows {
                if store.catalog.isEmpty {
                    homeCatalogEmptyState
                } else {
                    homeCatalogListContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var homeCatalogEmptyState: some View {
        Text(LocalizedCopy.noItems)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .catalogListLayoutDirection()
    }

    @ViewBuilder
    private var homeCatalogListContent: some View {
        GeometryReader { listGeometry in
            ScrollViewReader { listProxy in
                List(selection: $selectedItemIDs) {
                    ForEach(Array(grouped.enumerated()), id: \.element.0.id) { index, pair in
                        homeInventoryGroupSection(
                            sectionIndex: index,
                            section: pair.0,
                            items: pair.1,
                            totalSectionCount: grouped.count
                        )
                    }
                }
                // Before the section title bar so chrome mirror doesn't flip the slider.
                .catalogMirrorUIKitListChrome()
                .homeCatalogSectionTitleSafeAreaBar(isPresented: showsHomeCatalogSectionTitleBar) {
                    HomeCatalogSectionTitleBar(
                        sections: homeCatalogSectionTitles,
                        activeSectionID: activeSectionID,
                        suppressBarSync: isProgrammaticListScroll,
                        onTitleTap: scrollHomeCatalogListToSection
                    )
                    .catalogListLayoutDirection()
                    .dynamicTypeSize(catalogTextDynamicTypeSize)
                    .animation(AppTextSize.layoutCommitAnimation, value: textSizeRaw)
                }
                .tint(homeListEditMode == .active ? appTheme.color : Color.primary)
                .modifier(ListDragInteractionModifier(enabled: homeListEditMode == .active))
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .dynamicTypeSize(catalogTextDynamicTypeSize)
                .shoppingListDensity()
                .animation(AppTextSize.layoutCommitAnimation, value: textSizeRaw)
                .listSectionSpacing(ShoppingListMetrics.interSectionSpacing)
                .scrollEdgeSoftTopIfAvailable(when: usesHomeToolbarSearch && showsCatalogListRows)
                .catalogListLayoutDirection()
                .environment(\.expandedQuantityPillItemID, expandedHomeQuantityPillItemID)
                .coordinateSpace(name: HomeCatalogListCoordinateSpace.name)
                .onPreferenceChange(HomeCatalogRowAnchorKey.self) { anchors in
                    rowAnchors = anchors
                    updateHomeCatalogActiveSection(anchors: anchors)
                }
                .onPreferenceChange(HomeItemNameGlobalFrameKey.self) { frames in
                    homeItemNameGlobalFrames = frames
                }
                .onScrollGeometryChange(for: HomeCatalogListScrollSnapshot.self) { geometry in
                    HomeCatalogListScrollSnapshot(
                        viewportHeight: geometry.containerSize.height,
                        contentTopInset: geometry.contentInsets.top
                    )
                } action: { _, snapshot in
                    listScrollSnapshot = snapshot
                    updateHomeCatalogActiveSection(anchors: rowAnchors)
                }
                .onAppear {
                    listScrollSnapshot = HomeCatalogListScrollSnapshot(
                        viewportHeight: listGeometry.size.height,
                        contentTopInset: listScrollSnapshot.contentTopInset
                    )
                    updateHomeCatalogActiveSection(anchors: rowAnchors)
                }
                .onChange(of: listGeometry.size.height) { _, height in
                    listScrollSnapshot = HomeCatalogListScrollSnapshot(
                        viewportHeight: height,
                        contentTopInset: listScrollSnapshot.contentTopInset
                    )
                    updateHomeCatalogActiveSection(anchors: rowAnchors)
                }
                .onChange(of: scrollToSectionID) { _, sectionID in
                    guard let sectionID else { return }
                    withAnimation(.snappy) {
                        listProxy.scrollTo(sectionID, anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func homeInventoryGroupSection(
        sectionIndex: Int,
        section: Tag,
        items: [GroceryItem],
        totalSectionCount: Int
    ) -> some View {
        Section {
            catalogGroupItems(
                items: items,
                sectionID: section.id,
                sectionIndex: sectionIndex,
                totalSectionCount: totalSectionCount,
                isReorderMode: showsHomeEditRowChrome,
                showsRowShoppingStatus: showsHomeRowShoppingStatus,
                usesHomePlainListChrome: true,
                onAddedToShopping: {
                    if !trimmedToolbarSearchText.isEmpty {
                        homeSearchPinnedQuery = trimmedToolbarSearchText
                    }
                    homeSearchText = ""
                }
            )
        }
        .listSectionMargins(.horizontal, 0)
    }

    private func scrollHomeCatalogListToSection(_ sectionID: UUID) {
        isUndefinedSectionRevealed = isUnsortedSectionID(sectionID)
        isProgrammaticListScroll = true
        activeSectionID = sectionID
        Task { @MainActor in
            if isUnsortedSectionID(sectionID) {
                await Task.yield()
            }
            scrollToSectionID = sectionID
            try? await Task.sleep(for: .milliseconds(400))
            isProgrammaticListScroll = false
            scrollToSectionID = nil
        }
    }

    private func updateHomeCatalogActiveSection(anchors: [HomeCatalogRowAnchor]) {
        activeSectionID = HomeCatalogSectionScrollSync.activeSectionID(
            anchors: anchors,
            sliderBottomY: listScrollSnapshot.contentTopInset,
            unsortedSectionID: unsortedInventorySectionID,
            isUndefinedSectionRevealed: isUndefinedSectionRevealed,
            isProgrammaticListScroll: isProgrammaticListScroll,
            fallback: activeSectionID
        )
    }

    @ViewBuilder
    private func homeInventoryCatalogRow(
        item: GroceryItem,
        isReorderMode: Bool,
        showsRowShoppingStatus: Bool,
        onEdit: @escaping () -> Void,
        onAddedToShopping: (() -> Void)? = nil
    ) -> some View {
        let catalogRow = InventoryCatalogRow(
            item: item,
            isReorderMode: isReorderMode,
            showsShoppingStatus: showsShoppingStatus,
            showsRowShoppingStatus: showsRowShoppingStatus,
            usesHomePlainListChrome: true,
            usesUIKitContextMenu: false,
            expandedQuantityPillItemID: $expandedHomeQuantityPillItemID,
            quantityPillChromeID: homeQuantityPillChromeID,
            enablesLongPressToEdit: false,
            onSelectToggleShopping: {},
            onAddedToShopping: onAddedToShopping,
            onEdit: onEdit
        )

        HomeCatalogRowContextMenuHost(
            isEnabled: !isReorderMode,
            item: item,
            onTap: {
                toggleHomeItemShopping(itemID: item.id, onAddedToShopping: onAddedToShopping)
            },
            onEdit: onEdit,
            onDelete: { onDeleteItem(item) }
        ) {
            if isReorderMode {
                catalogRow
                    .onTapGesture(perform: onEdit)
            } else {
                catalogRow
            }
        }
    }

    @ViewBuilder
    private var toolbarSearchNoMatchesPlaceholder: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top + toolbarSearchNoMatchesExtraTopInset
            let bottomInset = geometry.safeAreaInsets.bottom
                + (usesHomeToolbarSearch ? Self.toolbarSearchFieldClearance : 0)
            let bandHeight = max(0, geometry.size.height - topInset - bottomInset)

            VStack(spacing: 16) {
                if toolbarSearchUsesSubmitBehavior {
                    Button(LocalizedCopy.createItem) {
                        handleToolbarSearchSubmit()
                    }
                    .font(.body)
                    .modifier(ToolbarSearchCreateItemButtonStyle())
                }
            }
            .padding(.horizontal, 28)
            .frame(width: geometry.size.width, height: bandHeight, alignment: .center)
            .position(
                x: geometry.size.width / 2,
                y: topInset + bandHeight / 2
                    - (showsHomeMainTabToolbarControls ? 0 : 100)
                    + (usesHomeToolbarSearch ? Self.toolbarSearchNoMatchesVerticalOffset : 0)
            )
        }
        .accessibilityElement(children: .contain)
    }

    /// Empty field with no pinned query — nudge to start typing (not shown after add-and-clear pin).
    private var toolbarSearchEmptyQueryPlaceholder: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(LocalizedCopy.typeToFilterItems)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .padding(.bottom, usesHomeToolbarSearch ? Self.toolbarSearchFieldClearance : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalizedCopy.typeToFilterItems)
    }

    var body: some View {
        inventoryScreen
            .environment(\.editMode, homeCatalogListEditMode)
            .onAppear {
                // Tabs: keep list identity stable across Store ↔ Home so scroll position survives.
                // Push-model Home still remounts searchable chrome on each visit.
                if !minimizesToolbarSearch {
                    homeToolbarSearchChromeID = UUID()
                }
                scheduleLiquidGlassToolbarSearchAttachmentIfNeeded()
                if activeSectionID == nil {
                    activeSectionID = displayedGroupedCatalog.first?.0.id
                        ?? allGroupedCatalog.first?.0.id
                }
                homeListEditMode = isReorderMode ? .active : .inactive
                showsHomeEditRowChrome = isReorderMode
                showsHomeRowShoppingStatus = !isReorderMode
            }
            .onDisappear {
                deactivateHomeEditRowChromeTask?.cancel()
                deactivateHomeEditRowChromeTask = nil
                liquidGlassToolbarSearchAttachTask?.cancel()
                liquidGlassToolbarSearchAttachTask = nil
                homeToolbarSearchPlaceholderPinTask?.cancel()
                homeToolbarSearchPlaceholderPinTask = nil
                // Tabs: leave searchable + list mounted; tearing them down remounts the List
                // and resets scroll when returning from Store.
                guard usesHomeToolbarSearch, !minimizesToolbarSearch else { return }
                attachLiquidGlassToolbarSearch = false
                HomeToolbarSearchCacheCleaner.clearCachedToolbarSearchField()
                Task { @MainActor in
                    dismissSearch()
                    await Task.yield()
                    HomeToolbarSearchCacheCleaner.clearCachedToolbarSearchField()
                }
            }
            .onChange(of: attachLiquidGlassToolbarSearch) { _, attached in
                guard attached, usesHomeToolbarSearch else { return }
                scheduleHomeToolbarSearchPlaceholderPin()
            }
            .onChange(of: activeSectionID) { _, newSectionID in
                guard isUndefinedSectionRevealed,
                      let unsortedID = unsortedInventorySectionID,
                      let newSectionID,
                      newSectionID != unsortedID else { return }
                isUndefinedSectionRevealed = false
            }
            .onChange(of: homeSearchText) { _, _ in
                syncActiveSectionToVisibleTitles()
            }
            .onChange(of: isHomeToolbarSearchPresented) { _, presented in
                if !presented {
                    homeSearchPinnedQuery = ""
                }
                syncActiveSectionToVisibleTitles()
            }
            .onChange(of: isReorderMode) { _, active in
                guard !active else { return }
                guard homeListEditMode == .active, showsHomeEditRowChrome else { return }
                deactivateHomeCatalogEditMode(animated: false)
            }
            .modifier(OptionalIgnoresSafeAreaModifier(active: ignoresSafeArea))
    }

    @ViewBuilder
    private var inventoryScreen: some View {
        ZStack {
            Color.shoppingListBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Group {
                if showsCatalogListRows || showsHomeCatalogSectionTitleBar {
                    homeCatalogResultsList
                }
            }
            // Bumped only for push-model Home visits (`onAppear`). Tabs keep this stable so
            // Store ↔ Home does not remount the List and wipe scroll position.
            .id(homeToolbarSearchChromeID)
            .modifier(
                HomeToolbarSearchModifier(
                    enabled: isHomeToolbarSearchChromeActive,
                    text: $homeSearchText,
                    isHomeToolbarSearchPresented: $isHomeToolbarSearchPresented,
                    // Keep prompt stable across browse/edit in the tabs experiment so searchable
                    // chrome doesn't remount and jump the bottom bar.
                    prompt: (minimizesToolbarSearch || !showsHomeEditToolbarChrome)
                        ? toolbarSearchPrompt
                        : LocalizedCopy.search,
                    minimizes: minimizesToolbarSearch
                )
            )
            .modifier(
                HomeSearchReturnSubmitModifier(
                    enabled: isHomeToolbarSearchChromeActive,
                    onSubmit: handleToolbarSearchSubmit
                )
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: bottomReservedHeight)
                    .allowsHitTesting(false)
            }

            if toolbarSearchNoMatches {
                toolbarSearchNoMatchesPlaceholder
            } else if toolbarSearchEmptyQueryActive {
                toolbarSearchEmptyQueryPlaceholder
            }
        }
        // Home list scrolls under the bottom search bar (`bottomReservedHeight: 0`). Liquid Glass
        // chrome is taller than UISearchBar’s hit target, so edge taps would reach rows behind.
        // The content layout bottom is *above* the toolbar search — offset down onto the chrome.
        .overlay(alignment: .bottom) {
            if usesHomeToolbarSearch, isHomeToolbarSearchChromeActive {
                Color.clear
                    .frame(height: Self.toolbarSearchHitThroughBlockerHeight)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HomeToolbarSearchCacheCleaner.focusToolbarSearchField()
                    }
                    .accessibilityHidden(true)
                    .offset(y: Self.toolbarSearchHitThroughBlockerOffsetY)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { homeCatalogBottomToolbarContent }
        .sheet(isPresented: $isPresentingRecipes) {
            NavigationStack {
                RecipesListView(
                    onAppliedToShopping: {
                        isPresentingRecipes = false
                        onReturnToStoreAfterRecipeApply?()
                    }
                )
            }
            .environmentObject(store)
        }
        .toolbar(inventoryNavigationBarVisibility, for: .navigationBar)
        .toolbar {
            if usesHomeToolbarSearch, hidesNavigationBar, showsHomeCatalogPrincipalToolbar {
                ToolbarItem(id: HomeCatalogTopToolbarItemID.principal, placement: .principal) {
                    // Crossfade search ↔ browse chrome. searchable dismiss otherwise slides the
                    // principal text; keep that as an opacity fade only.
                    ZStack {
                        HomeCatalogPrincipalHeader(
                            title: LocalizedCopy.homeLibrary,
                            subtitle: LocalizedCopy.itemsInLibrary(store.catalog.count),
                            subtitleVisible: true
                        )
                        .opacity(homeCatalogPrincipalIsSearchMode ? 0 : 1)

                        HomeCatalogPrincipalHeader(
                            title: LocalizedCopy.searchLibrary,
                            subtitle: homeCatalogPrincipalSearchSubtitleText,
                            subtitleVisible: !homeCatalogPrincipalSearchSubtitleText.isEmpty
                        )
                        .opacity(homeCatalogPrincipalIsSearchMode ? 1 : 0)
                    }
                    // Stable identity so Edit/Done toolbar swaps don't remount this title view.
                    .id(HomeCatalogTopToolbarItemID.principal)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(homeCatalogPrincipalAccessibilityLabel)
                    .accessibilityAddTraits(.isHeader)
                    // Isolate from Browse↔Edit so only toolbar/list animate; title stays put.
                    .animation(nil, value: homeListEditMode)
                    .transaction { $0.animation = nil }
                    // Search↔browse crossfade (re-enabled after stripping inherited animations).
                    .animation(.easeInOut(duration: 0.22), value: homeCatalogPrincipalIsSearchMode)
                    .background(HomeCatalogPrincipalMotionSuppressor(editMode: homeListEditMode))
                }
            }
            if showsHomeBackToolbar, !showsHomeEditToolbarChrome, let onBackToStore {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBackToStore) {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .catalogToolbarCircularTapTarget()
                    .accessibilityLabel(LocalizedCopy.backToShoppingList)
                }
            }
            // Leading: Edit↔Done. Trailing: stable ⋯↔Move slot + edit-only Delete (same animation turn).
            if showsRecipesInTopBarLeading {
                if showsHomeEditToolbar {
                    ToolbarItem(id: HomeCatalogTopToolbarItemID.leadingEditDone, placement: .topBarLeading) {
                        if showsHomeEditToolbarChrome {
                            HomeCatalogDoneToolbarButton(action: exitHomeCatalogReorderMode)
                        } else {
                            HomeCatalogEditToolbarButton(action: enterHomeCatalogReorderMode)
                        }
                    }
                }
                ToolbarItem(id: HomeCatalogTopToolbarItemID.trailingPrimary, placement: .topBarTrailing) {
                    if showsHomeEditToolbarChrome {
                        homeCatalogTopBarMoveMenuControl
                    } else {
                        HomeCatalogEllipsisMenu(
                            onManageSections: onToolbarSelectGroupsKind.map { select in
                                { select(.inventory) }
                            },
                            onAddItem: onToolbarAddItem,
                            onSavedLists: { isPresentingRecipes = true }
                        )
                    }
                }
                if showsHomeEditToolbarChrome {
                    ToolbarItem(id: HomeCatalogTopToolbarItemID.trailingDelete, placement: .topBarTrailing) {
                        homeCatalogDeleteControl
                    }
                }
            } else if showsHomeEditToolbar {
                // Push-model Home: Edit/Done share one trailing identity (Move/Delete live in bottom bar).
                ToolbarItem(id: HomeCatalogTopToolbarItemID.pushEditDone, placement: .topBarTrailing) {
                    if showsHomeEditToolbarChrome {
                        HomeCatalogDoneToolbarButton(action: exitHomeCatalogReorderMode)
                    } else {
                        HomeCatalogEditToolbarButton(action: enterHomeCatalogReorderMode)
                    }
                }
            }
        }
        .alert(
            LocalizedCopy.newSection,
            isPresented: Binding(
                get: { homeMoveNewSectionKind != nil },
                set: { if !$0 { homeMoveNewSectionKind = nil } }
            )
        ) {
            TextField(LocalizedCopy.sectionName, text: $homeMoveNewSectionName)
            Button(LocalizedCopy.create) {
                let trimmed = homeMoveNewSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                let kind = homeMoveNewSectionKind
                homeMoveNewSectionKind = nil
                homeMoveNewSectionName = ""
                guard !trimmed.isEmpty, let kind else { return }
                switch kind {
                case .inventory:
                    createInventorySectionAndMoveSelected(named: trimmed)
                case .shopping:
                    createShoppingSectionAndMoveSelected(named: trimmed)
                }
            }
            Button(LocalizedCopy.cancel, role: .cancel) {
                homeMoveNewSectionKind = nil
                homeMoveNewSectionName = ""
            }
        }
    }

    /// Top bar: SwiftUI `Menu` so ⋯↔Move morphs as native toolbar content (not UIKit representable).
    private var homeCatalogTopBarMoveMenuControl: some View {
        HomeCatalogMoveSwiftUIMenu(
            inventoryTags: store.inventoryTags.filter { $0.kind == .inventory },
            shoppingTags: store.shoppingTags.filter { $0.kind == .shopping },
            catalogLanguage: catalogLanguage,
            isDisabled: selectedItemIDs.isEmpty,
            onMoveToInventoryTag: moveSelectedItems(toInventoryTagID:),
            onMoveToShoppingTag: moveSelectedItems(toShoppingTagID:),
            onCreateInventorySection: {
                homeMoveNewSectionName = ""
                homeMoveNewSectionKind = .inventory
            },
            onCreateShoppingSection: {
                homeMoveNewSectionName = ""
                homeMoveNewSectionKind = .shopping
            }
        )
    }

    /// Bottom bar: UIKit nested menu (avoids SwiftUI nested-`Menu` anchor bounce in `bottomBar`).
    private var homeCatalogMoveMenuControl: some View {
        HomeCatalogMoveMenu(
            inventoryTags: store.inventoryTags.filter { $0.kind == .inventory },
            shoppingTags: store.shoppingTags.filter { $0.kind == .shopping },
            catalogLanguage: catalogLanguage,
            isDisabled: selectedItemIDs.isEmpty,
            onMoveToInventoryTag: moveSelectedItems(toInventoryTagID:),
            onMoveToShoppingTag: moveSelectedItems(toShoppingTagID:),
            onCreateInventorySectionAndMove: createInventorySectionAndMoveSelected(named:),
            onCreateShoppingSectionAndMove: createShoppingSectionAndMoveSelected(named:)
        )
        .fixedSize()
    }

    private var homeCatalogDeleteControl: some View {
        HomeCatalogDeleteButton(
            selectionCount: selectedItemIDs.count,
            isDisabled: selectedItemIDs.isEmpty,
            onDeleteConfirmed: deleteSelectedItems
        )
    }

    @ToolbarContentBuilder
    private var homeCatalogBottomToolbarContent: some ToolbarContent {
        // EXPERIMENT (tabs): browse and edit share spacer — minimized search so Edit/Done
        // doesn't tear down the search control. Show + with edit toolbar chrome (same turn as
        // the top morph). Gating on deferred row chrome inserts + mid-morph and jumps the bar.
        if minimizesToolbarSearch, usesHomeToolbarSearch, isHomeToolbarSearchChromeActive {
            if showsHomeEditToolbarChrome, let onToolbarAddItem {
                ToolbarItem(id: "homeCatalogAdd", placement: .bottomBar) {
                    ToolbarCatalogAddButton(action: onToolbarAddItem)
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        } else if showsHomeBottomEditToolbarChrome {
            ToolbarItem(placement: .bottomBar) {
                homeCatalogMoveMenuControl
            }
            ToolbarItem(placement: .bottomBar) {
                homeCatalogDeleteControl
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)
            if let onToolbarAddItem {
                ToolbarItem(placement: .bottomBar) {
                    ToolbarCatalogAddButton(action: onToolbarAddItem)
                }
            }
        } else if usesHomeToolbarSearch, isHomeToolbarSearchChromeActive {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                HomeCatalogRecipesToolbarButton {
                    isPresentingRecipes = true
                }
            }
        }
    }

    /// Home keeps the nav bar visible while toolbar search is active (top-trailing chrome).
    private var inventoryNavigationBarVisibility: Visibility {
        (hidesNavigationBar && !usesHomeToolbarSearch) ? .hidden : .visible
    }

    private func scheduleLiquidGlassToolbarSearchAttachmentIfNeeded() {
        liquidGlassToolbarSearchAttachTask?.cancel()
        guard usesHomeToolbarSearch else {
            attachLiquidGlassToolbarSearch = true
            return
        }
        // EXPERIMENT (tabs): Home is a rooted tab, not a push — attach immediately so top/bottom
        // toolbars appear together. Push-model Home still defers until the transition settles.
        if minimizesToolbarSearch {
            attachLiquidGlassToolbarSearch = true
            return
        }
        // Defer every Store → Home visit so bottom-bar search mounts after the push settles.
        attachLiquidGlassToolbarSearch = false
        liquidGlassToolbarSearchAttachTask = Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            attachLiquidGlassToolbarSearch = true
        }
    }

    private func scheduleHomeToolbarSearchPlaceholderPin() {
        homeToolbarSearchPlaceholderPinTask?.cancel()
        let prompt = (minimizesToolbarSearch || !showsHomeEditToolbarChrome)
            ? toolbarSearchPrompt
            : LocalizedCopy.search
        homeToolbarSearchPlaceholderPinTask = Task { @MainActor in
            for _ in 0..<3 {
                await Task.yield()
                guard !Task.isCancelled else { return }
                HomeToolbarSearchCacheCleaner.pinToolbarSearchPlaceholder(prompt)
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            HomeToolbarSearchCacheCleaner.pinToolbarSearchPlaceholder(prompt)
        }
    }

}

/// Drops stale Liquid Glass toolbar search state so the next Home visit mounts fresh chrome.
enum HomeToolbarSearchCacheCleaner {
    static func clearCachedToolbarSearchField() {
        guard let window = keyWindow else { return }
        detachSearchControllers(startingAt: window.rootViewController)
        for searchBar in allDescendants(ofType: UISearchBar.self, in: window) {
            reset(searchBar: searchBar)
        }
    }

    static func pinToolbarSearchPlaceholder(_ prompt: String) {
        guard let window = keyWindow, !prompt.isEmpty else { return }
        let font = UIFont.preferredFont(forTextStyle: .body)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.placeholderText,
        ]
        let attributed = NSAttributedString(string: prompt, attributes: attributes)
        for searchBar in allDescendants(ofType: UISearchBar.self, in: window) {
            searchBar.searchTextField.font = font
            searchBar.searchTextField.attributedPlaceholder = attributed
        }
    }

    /// Focuses the bottom-toolbar search field when a tap misses its Liquid Glass hit target.
    static func focusToolbarSearchField() {
        guard let window = keyWindow else { return }
        for searchBar in allDescendants(ofType: UISearchBar.self, in: window) {
            let field = searchBar.searchTextField
            guard field.window != nil else { continue }
            field.becomeFirstResponder()
            return
        }
    }

    /// Focuses search inside the topmost presented sheet so the keyboard can rise with presentation
    /// instead of waiting for the sheet animation to finish (and without grabbing a tab-root search field).
    static func focusToolbarSearchFieldInPresentedHost() {
        guard let window = keyWindow,
              let root = window.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        guard top !== root else {
            focusToolbarSearchField()
            return
        }
        if let navigationItem = navigationItem(in: top),
           let searchController = navigationItem.searchController {
            searchController.isActive = true
            let field = searchController.searchBar.searchTextField
            if field.window != nil {
                field.becomeFirstResponder()
                return
            }
        }
        for searchBar in allDescendants(ofType: UISearchBar.self, in: top.view) {
            let field = searchBar.searchTextField
            guard field.window != nil else { continue }
            field.becomeFirstResponder()
            return
        }
    }

    private static func navigationItem(in viewController: UIViewController) -> UINavigationItem? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController.topViewController?.navigationItem
        }
        if let navigationController = viewController.navigationController {
            return navigationController.topViewController?.navigationItem
                ?? viewController.navigationItem
        }
        return viewController.navigationItem
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func detachSearchControllers(startingAt viewController: UIViewController?) {
        guard let viewController else { return }
        if let searchController = viewController.navigationItem.searchController {
            searchController.isActive = false
            reset(searchBar: searchController.searchBar)
            viewController.navigationItem.searchController = nil
        }
        for child in viewController.children {
            detachSearchControllers(startingAt: child)
        }
        detachSearchControllers(startingAt: viewController.presentedViewController)
    }

    private static func reset(searchBar: UISearchBar) {
        searchBar.text = ""
        let field = searchBar.searchTextField
        field.text = ""
        field.placeholder = nil
        field.attributedPlaceholder = nil
        field.font = UIFont.preferredFont(forTextStyle: .body)
    }

    private static func allDescendants<T: UIView>(ofType type: T.Type, in view: UIView) -> [T] {
        var matches: [T] = []
        if let match = view as? T {
            matches.append(match)
        }
        for subview in view.subviews {
            matches.append(contentsOf: allDescendants(ofType: type, in: subview))
        }
        return matches
    }
}

/// Applies `ignoresSafeArea` only when Home is embedded in the parent navigation stack.
private struct OptionalIgnoresSafeAreaModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.ignoresSafeArea(edges: .top)
        } else {
            content
        }
    }
}

/// No-results **Create Item** — glass capsule, slightly larger chrome, body text size.
private struct ToolbarSearchCreateItemButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .appThemeTint()
    }
}

// MARK: - Home toolbar search (Liquid Glass)

private struct HomeSearchReturnSubmitModifier: ViewModifier {
    let enabled: Bool
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onSubmit(of: .search) {
                onSubmit()
            }
        } else {
            content
        }
    }
}

/// Two-line Home principal (title + optional subtitle). Subtitle row stays reserved when blank
/// so the title stays on the top line (same as pull-to-add).
private struct HomeCatalogPrincipalHeader: View {
    let title: String
    let subtitle: String
    var subtitleVisible: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
            Text(subtitleVisible ? subtitle : " ")
                .font(.footnote.weight(.regular))
                .foregroundStyle(Color.secondary)
                .opacity(subtitleVisible ? 1 : 0)
        }
    }
}

/// Cancels UIKit position animations on the nav-bar title view when EditMode toggles,
/// without disabling toolbar button or list-handle animations.
private struct HomeCatalogPrincipalMotionSuppressor: UIViewRepresentable {
    var editMode: EditMode

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.lastEditMode != editMode else { return }
        context.coordinator.lastEditMode = editMode
        // After toolbar chrome swaps under `.snappy`, kill only the titleView's slide.
        DispatchQueue.main.async {
            Self.suppressTitleViewMotion(from: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastEditMode: EditMode?
    }

    private static func suppressTitleViewMotion(from view: UIView) {
        var walker: UIView? = view
        while let current = walker {
            if let navigationBar = current as? UINavigationBar {
                UIView.performWithoutAnimation {
                    navigationBar.topItem?.titleView?.layer.removeAllAnimations()
                    navigationBar.layoutIfNeeded()
                }
                return
            }
            walker = current.superview
        }
    }
}

/// Home toolbar search (bottom bar, browse mode).
private struct HomeToolbarSearchModifier: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    @Binding var isHomeToolbarSearchPresented: Bool
    var prompt: String
    /// EXPERIMENT (tabs): collapse the field into a compact trailing button until tapped.
    var minimizes: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(
                    text: $text,
                    isPresented: $isHomeToolbarSearchPresented,
                    placement: .toolbar,
                    prompt: prompt
                )
                .searchToolbarBehavior(minimizes ? .minimize : .automatic)
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .dynamicTypeSize(AppTextSize.defaultSize.dynamicTypeSize)
        } else {
            content
        }
    }
}

private enum InventoryToolbarGlyph {
    static let font = Font.system(size: 15, weight: .semibold)
}

/// Home catalog **Edit** / **Done** toolbar title.
private struct HomeCatalogEditToolbarLabel: View {
    var title: String = LocalizedCopy.edit

    var body: some View {
        Text(title)
            .font(.body.weight(.semibold))
    }
}

/// Home catalog **Edit** (browse mode) — enters reorder/select directly.
/// Use a titled toolbar `Button` (not a custom plain label) so Liquid Glass keeps capsule
/// chrome; extra capsule padding was collapsing this control into the nav-bar overflow `…`.
private struct HomeCatalogEditToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(LocalizedCopy.edit, action: action)
            .font(.body.weight(.semibold))
            .accessibilityLabel(LocalizedCopy.editHomeLibrary)
    }
}

/// Home catalog **Done** (edit mode) — system checkmark + glass prominent (no fixed frames;
/// forced sizing fights Liquid Glass morph and causes a late jump).
private struct HomeCatalogDoneToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(LocalizedCopy.doneEditing, systemImage: "checkmark", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .appThemeTint()
            .appThemeIdentity()
            .accessibilityLabel(LocalizedCopy.doneEditing)
    }
}

/// Toolbar add control: icon only (no glass circle or filled disk).
private struct ToolbarCatalogAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(LocalizedCopy.addItem, systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(InventoryToolbarGlyph.font)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel(LocalizedCopy.addItem)
    }
}

/// Home catalog browse-mode ⋯ menu (top trailing): home sections, create item, saved lists.
private struct HomeCatalogEllipsisMenu: View {
    let onManageSections: (() -> Void)?
    let onAddItem: (() -> Void)?
    let onSavedLists: () -> Void

    var body: some View {
        Menu {
            if let onManageSections {
                Section {
                    Button(action: onManageSections) {
                        Label(LocalizedCopy.homeSections, systemImage: "house.fill")
                    }
                }
            }

            Section {
                if let onAddItem {
                    Button(action: onAddItem) {
                        Label(LocalizedCopy.createItem, systemImage: "plus")
                    }
                }
                Button(action: onSavedLists) {
                    Label(LocalizedCopy.savedLists, systemImage: "book.pages")
                }
            }
        } label: {
            Label(LocalizedCopy.menu, systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(InventoryToolbarGlyph.font)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .catalogToolbarCircularTapTarget()
        .accessibilityLabel(LocalizedCopy.menu)
    }
}

/// Top-bar edit **Move** menu — SwiftUI so it morphs with the trailing glass group (UIKit
/// `UIViewRepresentable` settles after the morph and jumps the whole bar, including leading).
private struct HomeCatalogMoveSwiftUIMenu: View {
    let inventoryTags: [Tag]
    let shoppingTags: [Tag]
    let catalogLanguage: AppContentLanguage
    let isDisabled: Bool
    let onMoveToInventoryTag: (UUID) -> Void
    let onMoveToShoppingTag: (UUID) -> Void
    let onCreateInventorySection: () -> Void
    let onCreateShoppingSection: () -> Void

    var body: some View {
        Menu {
            Menu {
                ForEach(inventoryTags) { tag in
                    Button(tag.displayTitle(appContentLanguage: catalogLanguage)) {
                        onMoveToInventoryTag(tag.id)
                    }
                }
                Button(action: onCreateInventorySection) {
                    Label(LocalizedCopy.newSection, systemImage: "folder.badge.plus")
                }
            } label: {
                Label(LocalizedCopy.homeSectionLabel, systemImage: "house")
            }
            Menu {
                ForEach(shoppingTags) { tag in
                    Button(tag.displayTitle(appContentLanguage: catalogLanguage)) {
                        onMoveToShoppingTag(tag.id)
                    }
                }
                Button(action: onCreateShoppingSection) {
                    Label(LocalizedCopy.newSection, systemImage: "folder.badge.plus")
                }
            } label: {
                Label(LocalizedCopy.storeSectionLabel, systemImage: "cart")
            }
        } label: {
            Label(LocalizedCopy.moveToSection, systemImage: "folder")
                .labelStyle(.iconOnly)
                .font(InventoryToolbarGlyph.font)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .catalogToolbarCircularTapTarget()
        .disabled(isDisabled)
        .accessibilityLabel(LocalizedCopy.moveToSection)
    }
}

/// Home catalog browse-mode Recipes shortcut (bottom bar, trailing icon).
private struct HomeCatalogRecipesToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(LocalizedCopy.savedLists, systemImage: "book.pages")
                .labelStyle(.iconOnly)
                .font(InventoryToolbarGlyph.font)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .catalogToolbarCircularTapTarget()
        .accessibilityLabel(LocalizedCopy.savedLists)
    }
}

/// Compact host so SwiftUI does not stretch the toolbar representable across the bar.
private final class HomeCatalogMoveToolbarButtonHost: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(
            width: HomeCatalogMoveToolbarButton.toolbarTapSide,
            height: HomeCatalogMoveToolbarButton.toolbarTapSide
        )
    }
}

/// Toolbar folder button that attaches its menu only after it has a stable window frame.
private final class HomeCatalogMoveToolbarButton: UIButton {
    static let toolbarIconPointSize: CGFloat = 15
    static let toolbarTapSide: CGFloat = 30

    var menuProvider: (() -> UIMenu)?

    func applyToolbarSizing() {
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.toolbarTapSide, height: Self.toolbarTapSide)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshMenuIfReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshMenuIfReady()
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        refreshMenuIfReady()
    }

    override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
        CGPoint(x: bounds.midX, y: bounds.maxY)
    }

    func refreshMenuIfReady() {
        guard window != nil, bounds.width > 0 else { return }
        guard let menuProvider else { return }
        menu = menuProvider()
    }
}

/// Edit mode **Move** menu (bottom bar) — UIKit nested `UIMenu` keeps Store/Home sub-menus
/// without the SwiftUI nested-`Menu` anchor bounce in `bottomBar` toolbars.
private struct HomeCatalogMoveMenu: UIViewRepresentable {
    let inventoryTags: [Tag]
    let shoppingTags: [Tag]
    let catalogLanguage: AppContentLanguage
    let isDisabled: Bool
    let onMoveToInventoryTag: (UUID) -> Void
    let onMoveToShoppingTag: (UUID) -> Void
    let onCreateInventorySectionAndMove: (String) -> Void
    let onCreateShoppingSectionAndMove: (String) -> Void

    private static let symbolConfiguration = UIImage.SymbolConfiguration(
        pointSize: HomeCatalogMoveToolbarButton.toolbarIconPointSize,
        weight: .semibold
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> HomeCatalogMoveToolbarButtonHost {
        let host = HomeCatalogMoveToolbarButtonHost(frame: .zero)
        host.backgroundColor = .clear
        host.setContentHuggingPriority(.required, for: .horizontal)
        host.setContentHuggingPriority(.required, for: .vertical)

        let button = HomeCatalogMoveToolbarButton(type: .system)
        button.applyToolbarSizing()
        button.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            button.topAnchor.constraint(equalTo: host.topAnchor),
            button.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            button.widthAnchor.constraint(equalToConstant: HomeCatalogMoveToolbarButton.toolbarTapSide),
            button.heightAnchor.constraint(equalToConstant: HomeCatalogMoveToolbarButton.toolbarTapSide),
        ])

        context.coordinator.button = button
        applyConfiguration(to: button, coordinator: context.coordinator)
        return host
    }

    func updateUIView(_ uiView: HomeCatalogMoveToolbarButtonHost, context: Context) {
        guard let button = context.coordinator.button else { return }
        context.coordinator.parent = self
        applyConfiguration(to: button, coordinator: context.coordinator)
    }

    private func applyConfiguration(to button: HomeCatalogMoveToolbarButton, coordinator: Coordinator) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "folder", withConfiguration: Self.symbolConfiguration)
        config.contentInsets = .zero
        button.configuration = config
        button.showsMenuAsPrimaryAction = true
        button.isEnabled = !isDisabled
        button.accessibilityLabel = LocalizedCopy.moveToSection
        button.menuProvider = { [weak coordinator] in
            coordinator?.buildMenu() ?? UIMenu(children: [])
        }
        button.refreshMenuIfReady()
    }

    @MainActor
    final class Coordinator {
        var parent: HomeCatalogMoveMenu
        weak var button: HomeCatalogMoveToolbarButton?

        private static let homeSubmenuID = UIMenu.Identifier("catalog.move.home")
        private static let storeSubmenuID = UIMenu.Identifier("catalog.move.store")

        init(parent: HomeCatalogMoveMenu) {
            self.parent = parent
        }

        func buildMenu() -> UIMenu {
            UIMenu(children: [
                UIDeferredMenuElement { [weak self] completion in
                    completion(self?.topLevelSubmenus() ?? [])
                },
            ])
        }

        private func topLevelSubmenus() -> [UIMenuElement] {
            let homeMenu = UIMenu(
                title: LocalizedCopy.homeSectionLabel,
                image: UIImage(systemName: "house"),
                identifier: Self.homeSubmenuID,
                children: homeActions()
            )
            let storeMenu = UIMenu(
                title: LocalizedCopy.storeSectionLabel,
                image: UIImage(systemName: "cart"),
                identifier: Self.storeSubmenuID,
                children: storeActions()
            )
            return [homeMenu, storeMenu]
        }

        private func storeActions() -> [UIMenuElement] {
            CatalogMoveNewSectionPrompt.sectionMoveElements(
                tags: parent.shoppingTags,
                language: parent.catalogLanguage,
                onSelectTag: { [weak self] tagID in
                    self?.parent.onMoveToShoppingTag(tagID)
                },
                onNewSection: { [weak self] in
                    guard let self, let view = self.button else { return }
                    CatalogMoveNewSectionPrompt.presentAfterMenuDismiss(from: view) { [weak self] displayTitle in
                        self?.parent.onCreateShoppingSectionAndMove(displayTitle)
                    }
                }
            )
        }

        private func homeActions() -> [UIMenuElement] {
            CatalogMoveNewSectionPrompt.sectionMoveElements(
                tags: parent.inventoryTags,
                language: parent.catalogLanguage,
                onSelectTag: { [weak self] tagID in
                    self?.parent.onMoveToInventoryTag(tagID)
                },
                onNewSection: { [weak self] in
                    guard let self, let view = self.button else { return }
                    CatalogMoveNewSectionPrompt.presentAfterMenuDismiss(from: view) { [weak self] displayTitle in
                        self?.parent.onCreateInventorySectionAndMove(displayTitle)
                    }
                }
            )
        }
    }
}

/// Edit mode **Delete** button (bottom bar) — confirms then removes selected items from the catalog.
private struct HomeCatalogDeleteButton: View {
    let selectionCount: Int
    let isDisabled: Bool
    let onDeleteConfirmed: () -> Void

    @State private var showConfirmation = false

    var body: some View {
        Button {
            showConfirmation = true
        } label: {
            Label(LocalizedCopy.deleteSelected, systemImage: "trash")
                .labelStyle(.iconOnly)
                .font(InventoryToolbarGlyph.font)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .catalogToolbarCircularTapTarget()
        .disabled(isDisabled)
        .accessibilityLabel(LocalizedCopy.deleteSelected)
        .confirmationDialog(
            LocalizedCopy.deleteItemsConfirmationTitle(count: selectionCount),
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button(LocalizedCopy.delete, role: .destructive) { onDeleteConfirmed() }
            Button(LocalizedCopy.cancel, role: .cancel) {}
        }
    }
}

// MARK: - Catalog row (split from `InventoryView` to keep Swift type-checking fast)

private struct InventoryCatalogRow: View {
    @EnvironmentObject private var store: GroceryStore
    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.shoppingListSpacingScale) private var spacingScale

    private var usesManualMirror: Bool {
        CatalogLayoutMirroring.usesManualCatalogMirror(
            catalogLanguage: catalogLanguage,
            layoutDirection: layoutDirection
        )
    }

    let item: GroceryItem
    let isReorderMode: Bool
    let showsShoppingStatus: Bool
    var showsRowShoppingStatus: Bool = true
    var usesHomePlainListChrome: Bool = false
    var usesUIKitContextMenu: Bool = false
    var expandedQuantityPillItemID: Binding<UUID?>? = nil
    /// Remount token: bumped when Library becomes active after an expanded pill so row `@State` resets.
    var quantityPillChromeID: UUID = UUID()
    var enablesLongPressToEdit: Bool = false
    let onSelectToggleShopping: () -> Void
    /// Called after the row adds this item to the shopping list (not when removing or in reorder mode).
    let onAddedToShopping: (() -> Void)?
    let onEdit: () -> Void

    /// Visual expansion — starts collapsed so row-add can animate open after the pill mounts.
    /// Shared list ID coordinates which row is expanded; `quantityPillChromeID` remounts to clear stale expansion.
    @State private var isQuantityPillExpanded = false

    private var isInShopping: Bool {
        store.shopping.contains(where: { $0.itemID == item.id })
    }

    private var showsInShopping: Bool {
        showsShoppingStatus && showsRowShoppingStatus && isInShopping
    }

    private var qty: Int {
        store.shoppingListQuantity(for: item.id)
    }

    var body: some View {
        let row = rowLabel
            .listRowFullBleedHitArea(
                alignment: CatalogLayoutMirroring.rowContentAlignment(
                    catalogLanguage: catalogLanguage,
                    layoutDirection: layoutDirection
                )
            )
            .catalogListRowSeparatorFullWidth(!usesHomePlainListChrome)
            .contentShape(Rectangle())
            .onChange(of: expandedQuantityPillItemID?.wrappedValue) { _, expandedID in
                syncQuantityPillExpansion(with: expandedID)
            }
            .onChange(of: isInShopping) { _, inShopping in
                guard !inShopping else { return }
                quantityPillExpandedBinding.wrappedValue = false
            }

        // Key by item + chrome token so `@State` expansion resets on Library become-active remount.
        // Chrome ID alone isn't unique across sibling rows.
        Group {
            if isReorderMode {
                row
            } else if usesUIKitContextMenu {
                row
            } else {
                row
                    .onTapGesture { handleTap() }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        guard enablesLongPressToEdit else { return }
                        AppHaptics.impact(.medium)
                        onEdit()
                    }
                    .accessibilityAction(named: LocalizedCopy.edit) {
                        guard enablesLongPressToEdit else { return }
                        onEdit()
                    }
            }
        }
        // Un-mirror row content when the List mirrors UIKit edit chrome (English device + Hebrew library).
        .catalogMirrorUIKitListChrome()
        .id("\(item.id.uuidString)-\(quantityPillChromeID.uuidString)")
    }

    private func syncQuantityPillExpansion(with expandedID: UUID?) {
        let shouldExpand = expandedID == item.id
        guard isQuantityPillExpanded != shouldExpand else { return }
        isQuantityPillExpanded = shouldExpand
    }

    private func syncExpandedQuantityPillListID(isExpanded: Bool) {
        guard let expandedQuantityPillItemID else { return }
        if isExpanded {
            expandedQuantityPillItemID.wrappedValue = item.id
        } else if expandedQuantityPillItemID.wrappedValue == item.id {
            expandedQuantityPillItemID.wrappedValue = nil
        }
    }

    private var quantityPillExpandedBinding: Binding<Bool> {
        Binding(
            get: { isQuantityPillExpanded },
            set: { newValue in
                isQuantityPillExpanded = newValue
                syncExpandedQuantityPillListID(isExpanded: newValue)
            }
        )
    }

    private func collapseExpandedQuantityPillIfNeeded() {
        guard let expandedQuantityPillItemID,
              expandedQuantityPillItemID.wrappedValue != nil else { return }
        withAnimation(QuantityPillChromeTiming.expandCollapse) {
            expandedQuantityPillItemID.wrappedValue = nil
        }
    }

    private func scheduleExpandQuantityPillAfterAdd() {
        guard let expandedQuantityPillItemID else { return }
        let itemID = item.id
        QuantityPillChromeTiming.expandAfterAdd(
            itemID: itemID,
            guardInShopping: { [store] in
                store.shopping.contains(where: { $0.itemID == itemID })
            },
            setExpandedItemID: { expandedQuantityPillItemID.wrappedValue = $0 }
        )
    }

    private func handleTap() {
        collapseExpandedQuantityPillIfNeeded()
        if isReorderMode {
            onEdit()
        } else {
            if isInShopping {
                store.removeFromShopping(itemID: item.id)
            } else {
                store.addToShopping(itemID: item.id, quantity: 1)
                onAddedToShopping?()
                scheduleExpandQuantityPillAfterAdd()
            }
            onSelectToggleShopping()
        }
    }

    @ViewBuilder
    private var rowLabel: some View {
        if usesManualMirror {
            hebrewRow
        } else {
            englishRow
        }
    }

    private var rowItemNameFont: Font {
        showsInShopping && isQuantityPillExpanded ? Font.body.weight(.bold) : .body
    }

    /// Pill is in the HStack (avoids LTR title-padding flicker) but reports `height: 0` so expand
    /// chrome can overflow without changing list row height — same as the old overlay behavior.
    private var hebrewRow: some View {
        HStack(spacing: 0) {
            if showsShoppingStatus {
                quantityPillColumn
            }
            Text(item.displayName(appContentLanguage: catalogLanguage))
                .font(rowItemNameFont)
                .animation(QuantityPillChromeTiming.expandCollapse, value: isQuantityPillExpanded)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(showsInShopping ? appTheme.color : .primary)
                .animation(.easeIn(duration: HomeCatalogEditModeTiming.statusFadeDuration), value: showsRowShoppingStatus)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    itemNameDiveSourceProbe
                }
        }
    }

    private var englishRow: some View {
        HStack(spacing: 0) {
            Text(item.displayName(appContentLanguage: catalogLanguage))
                .font(rowItemNameFont)
                .animation(QuantityPillChromeTiming.expandCollapse, value: isQuantityPillExpanded)
                .multilineTextAlignment(.leading)
                .foregroundStyle(showsInShopping ? appTheme.color : .primary)
                .animation(.easeIn(duration: HomeCatalogEditModeTiming.statusFadeDuration), value: showsRowShoppingStatus)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    itemNameDiveSourceProbe
                }
            if showsShoppingStatus {
                quantityPillColumn
            }
        }
    }

    /// Intrinsic name bounds for the first-add dive (does not affect truncation layout).
    /// Uses bold to match the diving label so midX lines up after the row turns bold.
    private var itemNameDiveSourceProbe: some View {
        Text(item.displayName(appContentLanguage: catalogLanguage))
            .font(.body.weight(.bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .hidden()
            .reportHomeItemNameGlobalFrame(itemID: item.id)
            .accessibilityHidden(true)
    }

    private var quantityPillColumn: some View {
        Group {
            if showsInShopping {
                quantityPill(qty: qty, itemID: item.id)
                    .fixedSize(horizontal: true, vertical: true)
                    // Keep width in the HStack; contribute no height so rows stay text-sized.
                    .frame(height: 0, alignment: .center)
                    .opacity(showsRowShoppingStatus ? 1 : 0)
                    .animation(.easeIn(duration: HomeCatalogEditModeTiming.statusFadeDuration), value: showsRowShoppingStatus)
            }
        }
        .frame(
            minWidth: CatalogListRowDensity.quantityPillSlotMinWidth
                + CatalogListRowDensity.quantityPillHorizontalNudge,
            alignment: usesManualMirror ? .leading : .trailing
        )
        .accessibilityHidden(!showsInShopping)
    }

    @ViewBuilder
    private func quantityPill(qty: Int, itemID: UUID) -> some View {
        ExpandableQuantityPill(
            quantity: qty,
            style: usesHomePlainListChrome ? .glass : .material,
            usesLivePadding: !usesHomePlainListChrome,
            edgeAlignment: usesManualMirror ? .leading : .trailing,
            isExpanded: quantityPillExpandedBinding,
            onIncrement: {
                store.incrementUncheckedShoppingQuantity(itemID: itemID, delta: 1)
            },
            onDecrement: {
                store.adjustUncheckedShoppingQuantity(itemID: itemID, delta: -1)
            },
            onRemove: {
                store.removeFromShopping(itemID: itemID)
            }
        )
    }
}

/// Adjusts the underlying UICollectionView/UITableView drag interaction so
/// long-press-to-drag is only active in edit mode, letting browse-mode rows
/// handle their own long-press-to-edit gesture.
private struct ListDragInteractionModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.background(ListDragInteractionAdjuster(enabled: enabled))
    }
}

private struct ListDragInteractionAdjuster: UIViewRepresentable {
    let enabled: Bool
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            // Walk up through ancestors; at each level search descendants for
            // the UICollectionView that the .background view sits alongside.
            var ancestor: UIView? = uiView.superview
            for _ in 0..<8 {
                guard let container = ancestor else { break }
                if let cv = Self.firstDescendant(ofType: UICollectionView.self, in: container) {
                    let offset = cv.contentOffset
                    cv.dragInteractionEnabled = enabled
                    guard offset.y > 0 else { return }
                    DispatchQueue.main.async {
                        UIView.performWithoutAnimation {
                            cv.contentOffset = offset
                        }
                    }
                    return
                }
                ancestor = container.superview
            }
        }
    }

    private static func firstDescendant<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let found = firstDescendant(ofType: type, in: sub) { return found }
        }
        return nil
    }
}
