import SwiftUI

private enum ShoppingListShakeUndoKind {
    case clearList
    case clearChecked
}

struct ShoppingView: View {
    private static let allCheckedClearDialogAnimation: Animation = .spring(
        response: 0.42,
        dampingFraction: 0.78
    )
    private static let emptyShoppingRevealAnimation = Animation.easeOut(duration: 0.48)
    /// List bottom inset when the open-home control lives in the bottom toolbar (system lays out bar inset).
    private static let bottomFloatingBarClearance: CGFloat = 0
    /// Readable list width on iPad and other regular horizontal size classes.
    private static let regularWidthClassListMaxWidth: CGFloat = 640

    private static let shoppingGroupHeaderTitleFont: Font = .title3.weight(.heavy)
    private static var shoppingGroupHeaderTitleColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .secondaryLabel
                : UIColor(white: 0.28, alpha: 1)
        })
    }

    private static var shoppingGroupHeaderTitleDimmedColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .quaternaryLabel
                : UIColor(white: 0.72, alpha: 1)
        })
    }

    private static func shoppingGroupHeaderTitleForeground(allItemsChecked: Bool) -> Color {
        allItemsChecked ? shoppingGroupHeaderTitleDimmedColor : shoppingGroupHeaderTitleColor
    }

    private var catalogTextDynamicTypeSize: DynamicTypeSize {
        AppTextSize.resolved(from: textSizeRaw).dynamicTypeSize
    }
    /// Synthetic shopping-tag id for the bottom “Checked” / “סומנו” section when **Sort checked items** is on.
    private static let checkedShoppingSectionTagID = UUID(uuidString: "E84B9F00-9D1C-4A2F-A3B5-C7E8F9A0B1C2")!

    @EnvironmentObject private var store: GroceryStore
    @EnvironmentObject private var fullWindowOverlay: FullWindowOverlayCoordinator
    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.appTheme) private var appTheme
    @Environment(\.shoppingListSpacingScale) private var listSpacingScale
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppShoppingSortChecked.storageKey) private var sortCheckedShoppingItems: Bool = false
    @AppStorage(AppShoppingCollapseCompletedSections.storageKey) private var collapseCompletedSections: Bool = false
    @AppStorage(AppShoppingHideStoreGroupNames.storageKey) private var hideStoreGroupNames: Bool = false
    @AppStorage(AppShoppingConfirmClearWhenAllChecked.storageKey) private var confirmClearWhenAllChecked: Bool = true
    @AppStorage(AppShoppingEmptyAddHint.storageKey) private var emptyAddHintCompletedListCount: Int = 0
    @AppStorage(AppTextSize.storageKey) private var textSizeRaw: String = AppTextSize.defaultSize.rawValue

    @State private var wasAllVisibleItemsChecked = false
    @State private var isPresentingAllCheckedClearConfirm = false
    @State private var isPresentingClearAllConfirm = false
    @State private var isPresentingSaveAsRecipeAlert = false
    @State private var showsStoreGlassToast = false
    @State private var storeGlassToastMessage = ""
    @State private var storeGlassToastSymbol = "book.pages"
    @State private var storeGlassToastSession: UInt = 0
    @State private var shakeUndoToConfirm: ShoppingListShakeUndoKind?

    /// Collapsed by explicit user action (tap header, pinch gesture).
    @State private var userCollapsedShoppingGroupIDs: Set<UUID> = []
    /// Explicitly expanded by the user, even if it would be auto-collapsed.
    @State private var userExpandedShoppingGroupIDs: Set<UUID> = []
    /// Collapsed automatically because every row in that group is checked.
    @State private var autoCollapsedShoppingGroupIDs: Set<UUID> = []
    /// Last visible row counts per shopping section; used to expand collapsed sections that gain items.
    @State private var lastShoppingGroupRowCounts: [UUID: Int] = [:]
    /// Pull passed the invoke threshold this gesture; search runs on finger up.
    @State private var pullToAddReachedThreshold = false
    @State private var pullToAddThresholdHapticFired = false
    /// Scroll view content offset (`List`).
    @State private var pullToAddScrollHostReportsAtTop = false
    @State private var pullToAddDragAmount: CGFloat = 0
    /// Snapshot after a little movement so scroll geometry has applied (first `onChanged` can race layout).
    /// Still only snapshotted once per drag so rubber-band overscroll does not flip “at top” mid-pull.
    @State private var pullToAddLatchSet = false
    @State private var pullToAddBeganWithListAtTop = false
    /// Pull passed clear threshold; `clearChecked()` runs on finger up.
    @State private var pullToClearReachedThreshold = false
    @State private var pullToClearThresholdHapticFired = false
    @State private var pullToClearScrollHostReportsAtBottom = false
    @State private var pullToClearDragAmount: CGFloat = 0
    @State private var pullToClearLatchSet = false
    @State private var pullToClearBeganWithListAtBottom = false
    @State private var emptyShoppingRevealOpacity: CGFloat = 1
    /// Bumped so a pending fade-in `Task` is dropped when the list gains items again mid-animation.
    @State private var emptyShoppingFadeSession: UInt = 0
    /// Snapshot so the add hint stays visible on the trip that increments the counter to the hide threshold.
    @State private var showsEmptyAddHint = true
    /// One-shot: set when the list empties after complete/clear so the checkmark draws once.
    @State private var pendingEmptyCheckmarkDraw = false
    /// Mirrors the last `entriesWithItems.isEmpty` we applied (`nil` until first `syncEmptyShoppingFadeFromResolvedRows`).
    @State private var lastResolvedShoppingListWasEmpty: Bool?

    private static let pullRevealHorizontalDominanceRatio: CGFloat = 2.0
    /// Pull distance for full fade/scale (2×); haptic, threshold styling, and invoke-on-lift align with `t == 1`.
    private static let pullRevealFullSizeDrag: CGFloat = 150
    /// Wait for layout + preference before locking edge eligibility when pull started.
    private static let pullRevealLatchMovementThreshold: CGFloat = 20
    /// Let `UIScrollView` finish its rubber-band spring before pull-to-clear content mutations.
    private static let pullToClearRubberBandSettleMs: Int = 300
    /// Fade/scale progress runs from latch through full size (chrome appears at latch with `t == 0`).
    private static var pullRevealDragSpan: CGFloat {
        pullRevealFullSizeDrag - pullRevealLatchMovementThreshold
    }

    private static func pullRevealProgress(dragAmount: CGFloat) -> CGFloat {
        let effective = max(0, dragAmount - pullRevealLatchMovementThreshold)
        return min(1, effective / pullRevealDragSpan)
    }

    private var pullToAddListAppearsAtTop: Bool {
        pullToAddScrollHostReportsAtTop
    }

    private var pullToClearListAppearsAtBottom: Bool {
        pullToClearScrollHostReportsAtBottom
    }

    private var pullToClearIsAvailable: Bool {
        hasCheckedShoppingLines
    }

    private var entriesWithItems: [(ShoppingEntry, GroceryItem)] {
        store.shopping.compactMap { entry in
            guard let item = store.item(for: entry.itemID) else { return nil }
            return (entry, item)
        }
    }

    private var hasVisibleShoppingLines: Bool {
        !entriesWithItems.isEmpty
    }

    private var hasCheckedShoppingLines: Bool {
        entriesWithItems.contains { $0.0.isChecked }
    }

    private var hasUncheckedShoppingLines: Bool {
        entriesWithItems.contains { !$0.0.isChecked }
    }

    private var grouped: [(Tag, [(ShoppingEntry, GroceryItem)])] {
        let bucket = Dictionary(grouping: entriesWithItems, by: { $0.1.shoppingTagID })

        struct ShoppingGroupSortKey {
            let tag: Tag
            let rows: [(ShoppingEntry, GroceryItem)]
            let order: Int
            let unchecked: Int
        }

        // **Sort checked items** on: order unchecked / checked buckets like Inventory (within each bucket).
        let inventoryRank = Dictionary(
            uniqueKeysWithValues: store.inventoryTags.enumerated().map { ($0.element.id, $0.offset) }
        )
        func inventoryLikeRowSort(_ a: (ShoppingEntry, GroceryItem), _ b: (ShoppingEntry, GroceryItem)) -> Bool {
            let ra = inventoryRank[a.1.inventoryTagID] ?? Int.max
            let rb = inventoryRank[b.1.inventoryTagID] ?? Int.max
            if ra != rb { return ra < rb }
            if a.1.sortOrder != b.1.sortOrder { return a.1.sortOrder < b.1.sortOrder }
            let nameA = a.1.displayName(appContentLanguage: catalogLanguage)
            let nameB = b.1.displayName(appContentLanguage: catalogLanguage)
            let cmp = nameA.localizedCaseInsensitiveCompare(nameB)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return a.0.addedAt > b.0.addedAt
        }

        if !sortCheckedShoppingItems {
            let keys: [ShoppingGroupSortKey] = store.shoppingTags.enumerated().compactMap { order, tag in
                guard tag.kind == .shopping else { return nil }
                let rows = (bucket[tag.id] ?? []).sorted(by: inventoryLikeRowSort)
                guard !rows.isEmpty else { return nil }
                let unchecked = rows.reduce(into: 0) { acc, row in
                    if !row.0.isChecked { acc += 1 }
                }
                return ShoppingGroupSortKey(tag: tag, rows: rows, order: order, unchecked: unchecked)
            }

            return keys
                .sorted { a, b in
                    // Groups with no unchecked rows go to the bottom, otherwise preserve tag order.
                    let aIsDone = (a.unchecked == 0)
                    let bIsDone = (b.unchecked == 0)
                    if aIsDone != bIsDone { return bIsDone } // not-done first
                    return a.order < b.order
                }
                .map { ($0.tag, $0.rows) }
        }

        var sections: [(Tag, [(ShoppingEntry, GroceryItem)])] = []
        let uncheckedKeys: [ShoppingGroupSortKey] = store.shoppingTags.enumerated().compactMap { order, tag in
            guard tag.kind == .shopping else { return nil }
            let rows = (bucket[tag.id] ?? []).filter { !$0.0.isChecked }.sorted(by: inventoryLikeRowSort)
            guard !rows.isEmpty else { return nil }
            return ShoppingGroupSortKey(tag: tag, rows: rows, order: order, unchecked: rows.count)
        }
        sections.append(contentsOf: uncheckedKeys.sorted { $0.order < $1.order }.map { ($0.tag, $0.rows) })

        let checkedRows = entriesWithItems.filter { $0.0.isChecked }.sorted(by: inventoryLikeRowSort)
        if !checkedRows.isEmpty {
            let pseudoTag = Tag(
                id: Self.checkedShoppingSectionTagID,
                kind: .shopping,
                title: "",
                sortOrder: 0
            )
            sections.append((pseudoTag, checkedRows))
        }
        return sections
    }

    private var usesManualMirror: Bool {
        CatalogLayoutMirroring.catalogListUsesManualMirror(for: catalogLanguage)
    }

    private var checkedShoppingSectionTitle: String {
        LocalizedCopy.checkedSectionTitle(for: catalogLanguage)
    }

    private func isCollapsedShoppingGroup(_ tagID: UUID) -> Bool {
        guard !hideStoreGroupNames else { return false }
        if userExpandedShoppingGroupIDs.contains(tagID) { return false }
        if userCollapsedShoppingGroupIDs.contains(tagID) { return true }
        return autoCollapsedShoppingGroupIDs.contains(tagID)
    }

    private var shoppingGroupRowCounts: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: grouped.map { ($0.0.id, $0.1.count) })
    }

    private func expandCollapsedShoppingGroupsThatGainedItems() {
        let current = shoppingGroupRowCounts
        let previous = lastShoppingGroupRowCounts
        lastShoppingGroupRowCounts = current

        guard !previous.isEmpty else { return }

        let gainedTagIDs = current.compactMap { tagID, count -> UUID? in
            count > (previous[tagID] ?? 0) ? tagID : nil
        }
        guard !gainedTagIDs.isEmpty else { return }

        withAnimation(.snappy) {
            for tagID in gainedTagIDs {
                if sortCheckedShoppingItems, tagID == Self.checkedShoppingSectionTagID {
                    continue
                }
                userCollapsedShoppingGroupIDs.remove(tagID)
                if autoCollapsedShoppingGroupIDs.contains(tagID) {
                    userExpandedShoppingGroupIDs.insert(tagID)
                }
            }
        }
    }

    /// True when there is at least one visible shopping line and every line is checked.
    private var allVisibleShoppingItemsChecked: Bool {
        !entriesWithItems.isEmpty && entriesWithItems.allSatisfy { $0.0.isChecked }
    }

    private var storeUncheckedItemCount: Int {
        entriesWithItems.filter { !$0.0.isChecked }.count
    }

    private var storeRemainingItemsSubtitle: String {
        LocalizedCopy.itemsRemaining(
            unchecked: storeUncheckedItemCount,
            total: entriesWithItems.count,
            hasAnyChecked: entriesWithItems.contains { $0.0.isChecked }
        )
    }

    /// Keep the bar visible when empty so Settings stays reachable.
    private var shoppingNavigationBarVisibility: Visibility {
        .visible
    }

    private var storeNavigationPrincipalSubtitle: String {
        if entriesWithItems.isEmpty {
            return LocalizedCopy.noItems
        }
        return storeRemainingItemsSubtitle
    }

    @Binding var isStorePullToAddSearchPresented: Bool

    /// Requests the pull-to-add search session; the parent pushes it as its own isolated destination
    /// so the shopping-dependent Store toolbar can never tear down the search field on adds.
    var onBeginPullToAddSearch: () -> Void
    var onAddItem: (() -> Void)?
    var showsAddItemButton: Bool
    let canShareShoppingList: Bool
    let onShare: () -> Void
    let onSettings: () -> Void
    let onManageStoreSections: () -> Void

    init(
        canShareShoppingList: Bool,
        isStorePullToAddSearchPresented: Binding<Bool>,
        onBeginPullToAddSearch: @escaping () -> Void,
        showsAddItemButton: Bool = true,
        onShare: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onManageStoreSections: @escaping () -> Void,
        onAddItem: (() -> Void)? = nil
    ) {
        self.canShareShoppingList = canShareShoppingList
        _isStorePullToAddSearchPresented = isStorePullToAddSearchPresented
        self.onBeginPullToAddSearch = onBeginPullToAddSearch
        self.showsAddItemButton = showsAddItemButton
        self.onShare = onShare
        self.onSettings = onSettings
        self.onManageStoreSections = onManageStoreSections
        self.onAddItem = onAddItem
    }

    private var showsPullToAddChrome: Bool {
        entriesWithItems.isEmpty || pullToAddListAppearsAtTop
            || (pullToAddLatchSet && pullToAddBeganWithListAtTop)
    }

    private var showsPullToClearChrome: Bool {
        pullToClearIsAvailable && (
            pullToClearListAppearsAtBottom
                || (pullToClearLatchSet && pullToClearBeganWithListAtBottom)
        )
    }

    @ViewBuilder
    private func shoppingListSections(listMinHeight: CGFloat) -> some View {
        if entriesWithItems.isEmpty {
            Section {
                Color.clear
                    .frame(minHeight: listMinHeight)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)
        } else if !hideStoreGroupNames {
            ForEach(Array(grouped.enumerated()), id: \.element.0.id) { index, sectionRows in
                shoppingGroupSection(
                    sectionIndex: index,
                    section: sectionRows.0,
                    rows: sectionRows.1
                )
            }
        } else {
            Section {
                shoppingListRowsWithoutGroupHeaders
            }
            .listSectionMargins(.horizontal, 0)
            .listSectionSeparator(.hidden)
        }
    }

    private var shoppingListFlatRowsWithoutHeaders: [ShoppingListFlatRow] {
        var rows: [ShoppingListFlatRow] = []
        rows.reserveCapacity(entriesWithItems.count)
        for (sectionIndex, sectionRows) in grouped.enumerated() {
            for (rowIndex, row) in sectionRows.1.enumerated() {
                rows.append(
                    ShoppingListFlatRow(
                        entry: row.0,
                        item: row.1,
                        showsInterGroupDividerAbove: sectionIndex > 0 && rowIndex == 0
                    )
                )
            }
        }
        return rows
    }

    @ViewBuilder
    private var shoppingListRowsWithoutGroupHeaders: some View {
        ForEach(shoppingListFlatRowsWithoutHeaders) { flatRow in
            shoppingListRow(
                entry: flatRow.entry,
                item: flatRow.item,
                showsInterGroupDividerAbove: flatRow.showsInterGroupDividerAbove
            )
        }
    }

    @ViewBuilder
    private func shoppingStoreList(listMinHeight: CGFloat) -> some View {
        List {
            shoppingListSections(listMinHeight: listMinHeight)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dynamicTypeSize(catalogTextDynamicTypeSize)
        .shoppingListDensity()
        .animation(AppTextSize.layoutCommitAnimation, value: textSizeRaw)
        .listSectionSpacing(ShoppingListMetrics.interSectionSpacing)
        .scrollDisabled(entriesWithItems.isEmpty)
        .scrollEdgeSoftTopIfAvailable(when: !entriesWithItems.isEmpty)
        .modifier(PullToAddScrollHostAtTopModifier(state: $pullToAddScrollHostReportsAtTop))
        .modifier(PullToClearScrollHostAtBottomModifier(state: $pullToClearScrollHostReportsAtBottom))
        .simultaneousGesture(pullRevealDragGesture)
        .overlay(alignment: .top) { pullToAddChromeOverlay }
        .overlay(alignment: .bottom) { pullToClearChromeOverlay }
        // Hide list + pull chrome under the rising sheet so rubber-band cancel isn't visible.
        .opacity(isStorePullToAddSearchPresented ? 0 : 1)
        .animation(nil, value: isStorePullToAddSearchPresented)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: Self.bottomFloatingBarClearance)
                .allowsHitTesting(false)
        }
        .accessibilityHint(LocalizedCopy.shoppingListGesturesAccessibilityHint)
        .catalogListLayoutDirection()
    }

    private func handleDeviceShakeUndo() {
        guard !isStorePullToAddSearchPresented else { return }
        if store.canUndoClearShoppingList {
            AppHaptics.impact(.medium)
            shakeUndoToConfirm = .clearList
        } else if store.canUndoClearChecked {
            AppHaptics.impact(.medium)
            shakeUndoToConfirm = .clearChecked
        }
    }

    private func beginStorePullToAddSearch() {
        onBeginPullToAddSearch()
    }

    private var pullToAddChromeScale: CGFloat {
        accessibilityReduceMotion ? 1 : (1 + Self.pullRevealProgress(dragAmount: pullToAddDragAmount))
    }

    private var pullToClearChromeScale: CGFloat {
        accessibilityReduceMotion ? 1 : (1 + Self.pullRevealProgress(dragAmount: pullToClearDragAmount))
    }

    @ViewBuilder
    private var pullToAddChromeOverlay: some View {
        if !isStorePullToAddSearchPresented, showsPullToAddChrome {
            let progress = Self.pullRevealProgress(dragAmount: pullToAddDragAmount)
            Image(systemName: "plus.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(pullToAddReachedThreshold ? appTheme.color : Color.secondary)
                .opacity(progress)
                .scaleEffect(pullToAddChromeScale)
                .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12), value: pullToAddReachedThreshold)
                .padding(.top, 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var pullToClearChromeOverlay: some View {
        if showsPullToClearChrome {
            let progress = Self.pullRevealProgress(dragAmount: pullToClearDragAmount)
            Image(systemName: "xmark.app.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(pullToClearReachedThreshold ? Color.primary : Color.secondary)
                .opacity(progress)
                .scaleEffect(pullToClearChromeScale)
                .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12), value: pullToClearReachedThreshold)
                .padding(.bottom, 30)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var pullRevealDragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .local)
            .onChanged(handlePullRevealDragChanged)
            .onEnded { _ in handlePullRevealDragEnded() }
    }

    private func handlePullRevealDragChanged(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height

        if !pullToAddLatchSet, !pullToClearLatchSet {
            let moved = max(abs(dy), abs(dx))
            guard moved >= Self.pullRevealLatchMovementThreshold else { return }
            if dy > 0, !isStorePullToAddSearchPresented {
                pullToAddBeganWithListAtTop =
                    entriesWithItems.isEmpty || pullToAddListAppearsAtTop
                if pullToAddBeganWithListAtTop {
                    pullToAddLatchSet = true
                }
            } else if dy < 0, pullToClearIsAvailable, pullToClearListAppearsAtBottom {
                pullToClearBeganWithListAtBottom = true
                pullToClearLatchSet = true
            }
        }

        if pullToAddLatchSet {
            guard pullToAddBeganWithListAtTop,
                  entriesWithItems.isEmpty || pullToAddListAppearsAtTop else {
                pullToAddDragAmount = 0
                pullToAddReachedThreshold = false
                return
            }

            pullToAddDragAmount = max(0, dy)
            let verticallyDominant =
                abs(dy) > abs(dx) * Self.pullRevealHorizontalDominanceRatio
            let revealProgress = Self.pullRevealProgress(dragAmount: pullToAddDragAmount)
            pullToAddReachedThreshold = verticallyDominant && revealProgress >= 1
            if pullToAddReachedThreshold, !pullToAddThresholdHapticFired {
                pullToAddThresholdHapticFired = true
                AppHaptics.impact(.medium)
            } else if !pullToAddReachedThreshold {
                pullToAddThresholdHapticFired = false
            }
            return
        }

        if pullToClearLatchSet {
            guard pullToClearBeganWithListAtBottom,
                  pullToClearIsAvailable,
                  pullToClearListAppearsAtBottom else {
                pullToClearDragAmount = 0
                pullToClearReachedThreshold = false
                return
            }

            pullToClearDragAmount = max(0, -dy)
            let verticallyDominant =
                abs(dy) > abs(dx) * Self.pullRevealHorizontalDominanceRatio
            let revealProgress = Self.pullRevealProgress(dragAmount: pullToClearDragAmount)
            pullToClearReachedThreshold = verticallyDominant && revealProgress >= 1
            if pullToClearReachedThreshold, !pullToClearThresholdHapticFired {
                pullToClearThresholdHapticFired = true
                AppHaptics.impact(.medium)
            } else if !pullToClearReachedThreshold {
                pullToClearThresholdHapticFired = false
            }
        }
    }

    private func handlePullRevealDragEnded() {
        if pullToAddReachedThreshold {
            beginStorePullToAddSearch()
        }
        pullToAddReachedThreshold = false
        pullToAddThresholdHapticFired = false
        pullToAddDragAmount = 0
        pullToAddLatchSet = false
        pullToAddBeganWithListAtTop = false

        if pullToClearReachedThreshold {
            Task { @MainActor in
                // Let the scroll view's rubber-band spring complete before shrinking the content.
                try? await Task.sleep(for: .milliseconds(Self.pullToClearRubberBandSettleMs))
                clearCheckedAndShowToast()
            }
        }
        pullToClearReachedThreshold = false
        pullToClearThresholdHapticFired = false
        if accessibilityReduceMotion {
            pullToClearDragAmount = 0
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                pullToClearDragAmount = 0
            }
        }
        pullToClearLatchSet = false
        pullToClearBeganWithListAtBottom = false
    }

    var body: some View {
        ZStack {
            Color.shoppingListBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)

            GeometryReader { proxy in
                shoppingStoreList(listMinHeight: proxy.size.height)
                    .modifier(StorePullToAddKeyboardSafeAreaModifier(
                        respectsKeyboard: false
                    ))
            }

            if entriesWithItems.isEmpty {
                shoppingEmptyStateOverlay
                    .opacity(isStorePullToAddSearchPresented ? 0 : 1)
                    .animation(nil, value: isStorePullToAddSearchPresented)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }

            if showsStoreGlassToast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer(minLength: 0)
                        StoreGlassToastConfirmation(
                            message: storeGlassToastMessage,
                            systemImage: storeGlassToastSymbol
                        )
                        Spacer(minLength: 0)
                    }
                    .offset(y: -10)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(1)
            }
        }
            .frame(maxWidth: horizontalSizeClass == .regular ? Self.regularWidthClassListMaxWidth : .infinity)
            .frame(maxWidth: .infinity)
            .simultaneousGesture(pinchToggleAllShoppingGroupsGesture)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDeviceShake(perform: handleDeviceShakeUndo)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(shoppingNavigationBarVisibility, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(LocalizedCopy.shoppingListTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .label))
                        Text(storeNavigationPrincipalSubtitle)
                            .font(.footnote.weight(.regular))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        LocalizedCopy.shoppingListAccessibilityLabel(subtitle: storeNavigationPrincipalSubtitle)
                    )
                    // Suppress SwiftUI principal animation when pull-to-add Cancel (X) dismisses
                    // system search and the Store title reappears under the fade-in.
                    .transaction { $0.animation = nil }
                }
                ToolbarItem(placement: .topBarLeading) {
                    StoreSettingsToolbarButton(action: onSettings)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    StoreTabEllipsisMenu(
                        canShareShoppingList: canShareShoppingList,
                        hasCheckedLines: hasCheckedShoppingLines,
                        hasVisibleLines: hasVisibleShoppingLines,
                        hasUncheckedLines: hasUncheckedShoppingLines,
                        isPresentingClearAllConfirm: $isPresentingClearAllConfirm,
                        onManageStoreSections: onManageStoreSections,
                        onShare: onShare,
                        onSaveAsRecipe: {
                            isPresentingSaveAsRecipeAlert = true
                        },
                        onClearChecked: clearCheckedAndShowToast
                    )
                }
            }
            .toolbar {
                if showsAddItemButton, let onAddItem {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        StoreAddItemToolbarButton(action: onAddItem)
                            .id(appTheme.id)
                    }
                }
            }
            .alert(
                LocalizedCopy.clearShoppingListAlertTitle,
                isPresented: $isPresentingAllCheckedClearConfirm
            ) {
                Button(LocalizedCopy.keepList, role: .cancel) {
                    isPresentingAllCheckedClearConfirm = false
                }
                Button(LocalizedCopy.clearListTitleCase, role: .destructive) {
                    var dismissAlert = Transaction()
                    dismissAlert.disablesAnimations = true
                    withTransaction(dismissAlert) {
                        isPresentingAllCheckedClearConfirm = false
                    }
                    withAnimation(.snappy) {
                        store.clearShoppingList()
                    }
                }
            } message: {
                Text(LocalizedCopy.allItemsCheckedClearMessage)
            }
            .alert(
                LocalizedCopy.clearShoppingListAlertTitle,
                isPresented: $isPresentingClearAllConfirm
            ) {
                Button(LocalizedCopy.cancel, role: .cancel) {
                    isPresentingClearAllConfirm = false
                }
                Button(LocalizedCopy.clearList, role: .destructive) {
                    isPresentingClearAllConfirm = false
                    store.clearShoppingList()
                }
            } message: {
                Text(LocalizedCopy.clearShoppingListMessage)
            }
            .background {
                SaveShoppingListAsRecipeAlert(
                    isPresented: $isPresentingSaveAsRecipeAlert,
                    onConfirm: confirmSavedListFromStore(name:)
                )
            }
            .alert(
                LocalizedCopy.undoClearListConfirmTitle,
                isPresented: Binding(
                    get: { shakeUndoToConfirm == .clearList },
                    set: { if !$0 { shakeUndoToConfirm = nil } }
                )
            ) {
                Button(LocalizedCopy.cancel, role: .cancel) {
                    shakeUndoToConfirm = nil
                }
                Button(LocalizedCopy.undo) {
                    shakeUndoToConfirm = nil
                    withAnimation(.snappy) {
                        store.undoClearShoppingList()
                    }
                }
            } message: {
                Text(LocalizedCopy.undoClearListConfirmMessage)
            }
            .alert(
                LocalizedCopy.undoClearCheckedConfirmTitle,
                isPresented: Binding(
                    get: { shakeUndoToConfirm == .clearChecked },
                    set: { if !$0 { shakeUndoToConfirm = nil } }
                )
            ) {
                Button(LocalizedCopy.cancel, role: .cancel) {
                    shakeUndoToConfirm = nil
                }
                Button(LocalizedCopy.undo) {
                    shakeUndoToConfirm = nil
                    withAnimation(.snappy) {
                        store.undoClearChecked()
                    }
                }
            } message: {
                Text(LocalizedCopy.undoClearCheckedConfirmMessage)
            }
            .onAppear {
                wasAllVisibleItemsChecked = allVisibleShoppingItemsChecked
                lastShoppingGroupRowCounts = shoppingGroupRowCounts
                recomputeAutoCollapsedGroups()
                syncEmptyShoppingFadeFromResolvedRows()
            }
            .onChange(of: store.shopping) { _, _ in
                expandCollapsedShoppingGroupsThatGainedItems()
                evaluateAllCheckedClearPrompt()
                recomputeAutoCollapsedGroups()
                if lastResolvedShoppingListWasEmpty == true, allVisibleShoppingItemsChecked {
                    expandAllShoppingGroupsAfterAllCheckedRestore()
                }
                syncEmptyShoppingFadeFromResolvedRows()
            }
            .onChange(of: emptyAddHintCompletedListCount) { _, count in
                // Debug reset (and any external clear) while already empty should restore the hint.
                guard entriesWithItems.isEmpty else { return }
                showsEmptyAddHint = AppShoppingEmptyAddHint.shouldShow(completedListCount: count)
            }
            .onChange(of: store.catalog) { _, _ in
                expandCollapsedShoppingGroupsThatGainedItems()
                recomputeAutoCollapsedGroups()
                syncEmptyShoppingFadeFromResolvedRows()
            }
            .onChange(of: catalogLanguage) { _, _ in
                lastShoppingGroupRowCounts = [:]
                syncEmptyShoppingFadeFromResolvedRows()
            }
            .onChange(of: sortCheckedShoppingItems) { _, _ in
                lastShoppingGroupRowCounts = [:]
                recomputeAutoCollapsedGroups()
            }
            .onChange(of: collapseCompletedSections) { _, _ in
                lastShoppingGroupRowCounts = [:]
                recomputeAutoCollapsedGroups()
            }
            .onChange(of: hideStoreGroupNames) { _, _ in
                lastShoppingGroupRowCounts = [:]
                recomputeAutoCollapsedGroups()
            }
            .onChange(of: isStorePullToAddSearchPresented) { _, isPresented in
                if isPresented {
                    emptyShoppingFadeSession &+= 1
                }
            }
    }

    private func clearCheckedAndShowToast() {
        withAnimation(.snappy) {
            store.clearChecked()
        }
        showStoreGlassToast(
            message: LocalizedCopy.clearChecked,
            systemImage: "xmark.app"
        )
    }

    private func showStoreGlassToast(message: String, systemImage: String) {
        storeGlassToastMessage = message
        storeGlassToastSymbol = systemImage
        storeGlassToastSession &+= 1
        let session = storeGlassToastSession
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showsStoreGlassToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard session == storeGlassToastSession else { return }
            withAnimation(.spring(response: 0.82, dampingFraction: 0.88)) {
                showsStoreGlassToast = false
            }
        }
    }

    private func confirmSavedListFromStore(name: String) {
        let saved = store.createRecipeFromUncheckedShoppingList(name: name) != nil
        guard saved else { return }
        showStoreGlassToast(message: LocalizedCopy.listSaved, systemImage: "book.pages")
    }

    private func evaluateAllCheckedClearPrompt() {
        let now = allVisibleShoppingItemsChecked
        let restoredFromEmpty = lastResolvedShoppingListWasEmpty == true && !entriesWithItems.isEmpty
        if now, !wasAllVisibleItemsChecked, !restoredFromEmpty {
            if confirmClearWhenAllChecked {
                withAnimation(Self.allCheckedClearDialogAnimation) {
                    isPresentingAllCheckedClearConfirm = true
                }
            } else {
                withAnimation(.snappy) {
                    store.clearShoppingList()
                }
            }
        }
        wasAllVisibleItemsChecked = now
    }

    private func beginEmptyShoppingReveal() {
        guard entriesWithItems.isEmpty else { return }

        pendingEmptyCheckmarkDraw = true

        if accessibilityReduceMotion {
            emptyShoppingRevealOpacity = 1
            lastResolvedShoppingListWasEmpty = true
            return
        }

        emptyShoppingFadeSession &+= 1
        let session = emptyShoppingFadeSession
        var hideOverlay = Transaction()
        hideOverlay.disablesAnimations = true
        withTransaction(hideOverlay) {
            emptyShoppingRevealOpacity = 0
        }
        Task { @MainActor in
            await Task.yield()
            guard session == emptyShoppingFadeSession else { return }
            var reveal = Transaction()
            reveal.animation = Self.emptyShoppingRevealAnimation
            withTransaction(reveal) {
                emptyShoppingRevealOpacity = 1
            }
        }
        lastResolvedShoppingListWasEmpty = true
    }

    private func syncEmptyShoppingFadeFromResolvedRows() {
        let nowEmpty = entriesWithItems.isEmpty
        guard let wasEmpty = lastResolvedShoppingListWasEmpty else {
            lastResolvedShoppingListWasEmpty = nowEmpty
            if nowEmpty {
                showsEmptyAddHint = AppShoppingEmptyAddHint.shouldShow(
                    completedListCount: emptyAddHintCompletedListCount
                )
                emptyShoppingRevealOpacity = 1
                pendingEmptyCheckmarkDraw = false
            }
            return
        }

        if nowEmpty, !wasEmpty {
            showsEmptyAddHint = AppShoppingEmptyAddHint.shouldShow(
                completedListCount: emptyAddHintCompletedListCount
            )
            if emptyAddHintCompletedListCount < AppShoppingEmptyAddHint.hideAfterCompletedLists {
                emptyAddHintCompletedListCount += 1
            }
            beginEmptyShoppingReveal()
        } else if !nowEmpty, wasEmpty {
            emptyShoppingFadeSession &+= 1
            emptyShoppingRevealOpacity = 1
            pendingEmptyCheckmarkDraw = false
        }

        lastResolvedShoppingListWasEmpty = nowEmpty
    }

    @ViewBuilder
    private var shoppingEmptyStateOverlay: some View {
        ShoppingEmptyStateView(
            showsAddHint: showsEmptyAddHint,
            showsCheckmark: emptyAddHintCompletedListCount > 0 || pendingEmptyCheckmarkDraw,
            textOpacity: emptyShoppingRevealOpacity,
            pendingCheckmarkDraw: $pendingEmptyCheckmarkDraw
        )
    }

    @ViewBuilder
    private func shoppingGroupSection(
        sectionIndex: Int,
        section: Tag,
        rows: [(ShoppingEntry, GroceryItem)]
    ) -> some View {
        let showsVisibleGroupDivider = sectionIndex > 0
        Section {
            shoppingGroupHeaderRow(
                tagID: section.id,
                title: shoppingGroupSectionTitle(for: section),
                uncheckedCount: rows.filter { !$0.0.isChecked }.count,
                showsVisibleGroupDivider: showsVisibleGroupDivider
            )
            if !isCollapsedShoppingGroup(section.id) {
                shoppingGroupItemRows(rows)
            }
        }
        .listSectionMargins(.horizontal, 0)
    }

    @ViewBuilder
    private func shoppingGroupItemRows(_ rows: [(ShoppingEntry, GroceryItem)]) -> some View {
        ForEach(rows, id: \.0.id) { entry, item in
            shoppingListRow(entry: entry, item: item)
        }
    }

    private func shoppingGroupSectionTitle(for section: Tag) -> String {
        if section.id == Self.checkedShoppingSectionTagID {
            return checkedShoppingSectionTitle
        }
        return section.displayTitle(appContentLanguage: catalogLanguage)
    }

    /// Pulls row-level modifiers out of `List` so the Swift compiler can type-check `body` quickly.
    @ViewBuilder
    private func shoppingListRow(
        entry: ShoppingEntry,
        item: GroceryItem,
        showsInterGroupDividerAbove: Bool = false
    ) -> some View {
        let dividerGapBelow = showsInterGroupDividerAbove
            ? ShoppingListMetrics.interGroupDividerGapBelow(scale: listSpacingScale)
            : 0

        ShoppingListRowContextMenuHost(
            entry: entry,
            item: item,
            showsPhotoPreview: item.hasDisplayablePhoto && ItemImageStore.loadImage(forItemID: item.id) != nil,
            onTap: {
                withAnimation(.snappy) {
                    store.toggleChecked(entryID: entry.id)
                    recomputeAutoCollapsedGroups(animated: false)
                }
            },
            onEdit: {
                fullWindowOverlay.inventoryEditTapped(forItemID: item.id)
            }
        ) {
            ShoppingRowView(
                entry: entry,
                item: item
            )
            .shoppingListItemRowStyle(
                hebrew: usesManualMirror,
                extraTopInset: dividerGapBelow
            )
            .interGroupDividerHairline(
                spacingScale: listSpacingScale,
                gapBelow: dividerGapBelow
            )
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                LocalizedCopy.shoppingListRowAccessibilityLabel(
                    name: item.displayName(appContentLanguage: catalogLanguage),
                    isChecked: entry.isChecked,
                    quantity: entry.quantity
                )
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: LocalizedCopy.increaseQuantity) {
                guard !entry.isChecked else { return }
                store.incrementUncheckedShoppingQuantity(itemID: item.id, delta: 1)
            }
            .accessibilityAction(named: LocalizedCopy.decreaseQuantity) {
                guard !entry.isChecked, entry.quantity > 1 else { return }
                store.adjustUncheckedShoppingQuantity(itemID: item.id, delta: -1)
            }
        }
    }

    @ViewBuilder
    private func shoppingGroupHeaderRow(
        tagID: UUID,
        title: String,
        uncheckedCount: Int,
        showsVisibleGroupDivider: Bool
    ) -> some View {
        let collapsed = isCollapsedShoppingGroup(tagID)
        let expanded = !collapsed
        VStack(spacing: 0) {
            CatalogGroupHeaderSeparatorPrefix(showsVisibleDivider: showsVisibleGroupDivider)
            shoppingGroupHeaderTitleLabel(
                title: title,
                expanded: expanded,
                collapsed: collapsed,
                uncheckedCount: uncheckedCount,
                allItemsChecked: uncheckedCount == 0
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .shoppingListGroupHeaderRowStyle()
        .groupHeaderRowToggleOverlay {
            toggleShoppingGroupCollapsed(tagID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            (expanded ? LocalizedCopy.collapseSection(title) : LocalizedCopy.expandSection(title))
                + (collapsed && uncheckedCount > 0 ? LocalizedCopy.expandSectionUncheckedSuffix(uncheckedCount) : "")
        )
    }

    @ViewBuilder
    private func shoppingGroupHeaderTitleLabel(
        title: String,
        expanded: Bool,
        collapsed: Bool,
        uncheckedCount: Int,
        allItemsChecked: Bool
    ) -> some View {
        let titleColor = Self.shoppingGroupHeaderTitleForeground(allItemsChecked: allItemsChecked)
        if usesManualMirror {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: ShoppingListChrome.countChevronSpacing) {
                    disclosureChevronIcon(expanded: expanded, edgeChevron: .leading)
                        .frame(width: ShoppingListChrome.chevronColumnWidth)
                    collapsedGroupCountLabel(uncheckedCount, collapsed: collapsed)
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Text(title)
                    .font(Self.shoppingGroupHeaderTitleFont)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(Self.shoppingGroupHeaderTitleFont)
                    .foregroundStyle(titleColor)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: ShoppingListChrome.countChevronSpacing) {
                    collapsedGroupCountLabel(uncheckedCount, collapsed: collapsed)
                    disclosureChevronIcon(expanded: expanded, edgeChevron: .trailing)
                        .frame(width: ShoppingListChrome.chevronColumnWidth)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func collapsedGroupCountLabel(_ count: Int, collapsed: Bool) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(ShoppingListChrome.trailingQuantityFont.monospacedDigit())
                .foregroundStyle(appTheme.color)
                .opacity(collapsed ? 1 : 0)
                .accessibilityHidden(!collapsed)
                .animation(.snappy, value: collapsed)
        }
    }

    private func toggleShoppingGroupCollapsed(_ tagID: UUID) {
        let currentlyCollapsed = isCollapsedShoppingGroup(tagID)
        withAnimation(.snappy) {
            if currentlyCollapsed {
                // Expand. Only override auto-collapse when the group is currently auto-collapsed (i.e. already all-checked).
                userCollapsedShoppingGroupIDs.remove(tagID)
                if autoCollapsedShoppingGroupIDs.contains(tagID) {
                    userExpandedShoppingGroupIDs.insert(tagID)
                }
            } else {
                // Collapse (explicitly).
                userExpandedShoppingGroupIDs.remove(tagID)
                userCollapsedShoppingGroupIDs.insert(tagID)
            }
        }
    }

    /// After undo restores a previously cleared all-checked list, expand every section so rows are visible.
    private func expandAllShoppingGroupsAfterAllCheckedRestore() {
        guard allVisibleShoppingItemsChecked else { return }

        withAnimation(.snappy) {
            if sortCheckedShoppingItems {
                let checkedSectionID = Self.checkedShoppingSectionTagID
                userCollapsedShoppingGroupIDs.remove(checkedSectionID)
                userExpandedShoppingGroupIDs.insert(checkedSectionID)
                autoCollapsedShoppingGroupIDs.remove(checkedSectionID)
            } else if !hideStoreGroupNames {
                let allGroupIDs = Set(grouped.map(\.0.id))
                userCollapsedShoppingGroupIDs.subtract(allGroupIDs)
                userExpandedShoppingGroupIDs.formUnion(allGroupIDs)
                autoCollapsedShoppingGroupIDs.subtract(allGroupIDs)
            } else {
                userCollapsedShoppingGroupIDs = []
                userExpandedShoppingGroupIDs = []
                autoCollapsedShoppingGroupIDs = []
            }
        }
    }

    private func recomputeAutoCollapsedGroups(animated: Bool = true) {
        func applyCollapseState(_ changes: () -> Void) {
            if animated {
                withAnimation(.snappy, changes)
            } else {
                changes()
            }
        }

        guard !hideStoreGroupNames else {
            if !autoCollapsedShoppingGroupIDs.isEmpty
                || !userCollapsedShoppingGroupIDs.isEmpty
                || !userExpandedShoppingGroupIDs.isEmpty
            {
                applyCollapseState {
                    autoCollapsedShoppingGroupIDs = []
                    userCollapsedShoppingGroupIDs = []
                    userExpandedShoppingGroupIDs = []
                }
            }
            return
        }

        guard !sortCheckedShoppingItems else {
            let checkedSectionID = Self.checkedShoppingSectionTagID
            let hasCheckedRows = entriesWithItems.contains(where: { $0.0.isChecked })

            if !hasCheckedRows {
                if userCollapsedShoppingGroupIDs.contains(checkedSectionID)
                    || userExpandedShoppingGroupIDs.contains(checkedSectionID)
                    || !autoCollapsedShoppingGroupIDs.isEmpty
                {
                    applyCollapseState {
                        userCollapsedShoppingGroupIDs.remove(checkedSectionID)
                        userExpandedShoppingGroupIDs.remove(checkedSectionID)
                        autoCollapsedShoppingGroupIDs = []
                    }
                }
                return
            }

            if collapseCompletedSections {
                let nextAuto: Set<UUID> = [checkedSectionID]
                let nextUserExpanded = userExpandedShoppingGroupIDs.intersection(nextAuto)
                if autoCollapsedShoppingGroupIDs != nextAuto
                    || userExpandedShoppingGroupIDs != nextUserExpanded
                {
                    applyCollapseState {
                        autoCollapsedShoppingGroupIDs = nextAuto
                        userExpandedShoppingGroupIDs = nextUserExpanded
                    }
                }
            } else if !autoCollapsedShoppingGroupIDs.isEmpty || !userExpandedShoppingGroupIDs.isEmpty {
                applyCollapseState {
                    autoCollapsedShoppingGroupIDs = []
                    userExpandedShoppingGroupIDs = []
                }
            }
            return
        }

        userCollapsedShoppingGroupIDs.remove(Self.checkedShoppingSectionTagID)
        userExpandedShoppingGroupIDs.remove(Self.checkedShoppingSectionTagID)

        guard collapseCompletedSections else {
            if !autoCollapsedShoppingGroupIDs.isEmpty || !userExpandedShoppingGroupIDs.isEmpty {
                applyCollapseState {
                    autoCollapsedShoppingGroupIDs = []
                    userExpandedShoppingGroupIDs = []
                }
            }
            return
        }

        // Collapse any group where every row is checked. If that later becomes un-checked, auto-expand it
        // (unless user explicitly collapsed it).
        let allCheckedGroupIDs: Set<UUID> = Set(
            grouped
                .filter { _, rows in rows.allSatisfy { $0.0.isChecked } }
                .map { $0.0.id }
        )
        // Drop explicit user expansions for groups that are no longer auto-collapsed.
        // If the user expanded a group that remains all-checked, keep it expanded.
        let nextUserExpanded = userExpandedShoppingGroupIDs.intersection(allCheckedGroupIDs)

        if autoCollapsedShoppingGroupIDs != allCheckedGroupIDs || userExpandedShoppingGroupIDs != nextUserExpanded {
            applyCollapseState {
                autoCollapsedShoppingGroupIDs = allCheckedGroupIDs
                userExpandedShoppingGroupIDs = nextUserExpanded
            }
        }
    }

    /// Pinch **in** collapses all shopping sections; pinch **out** expands all.
    private var pinchToggleAllShoppingGroupsGesture: some Gesture {
        MagnificationGesture()
            .onEnded { scale in
                guard !hideStoreGroupNames, !grouped.isEmpty else { return }
                withAnimation(.snappy) {
                    if scale < 0.98 {
                        userCollapsedShoppingGroupIDs = Set(grouped.map { $0.0.id })
                        userExpandedShoppingGroupIDs = []
                    } else if scale > 1.02 {
                        userCollapsedShoppingGroupIDs = []
                        userExpandedShoppingGroupIDs = []
                    }
                }
            }
    }

    private func disclosureChevronIcon(expanded: Bool, edgeChevron: HorizontalEdge) -> some View {
        Image(systemName: "chevron.down")
            .font(Self.shoppingGroupHeaderTitleFont)
            .foregroundStyle(Self.shoppingGroupHeaderTitleColor)
            .rotationEffect(
                .degrees(
                    expanded
                        ? 0
                        : (edgeChevron == .leading ? 90 : -90)
                )
            )
            .animation(accessibilityReduceMotion ? nil : .snappy, value: expanded)
    }

}

private struct ShoppingListFlatRow: Identifiable {
    let entry: ShoppingEntry
    let item: GroceryItem
    let showsInterGroupDividerAbove: Bool

    var id: UUID { entry.id }
}

private extension View {
    /// `gapBelow` extra top inset on the row; keeps the hairline on the group boundary above that gap.
    func interGroupDividerHairline(spacingScale: CGFloat, gapBelow: CGFloat) -> some View {
        overlay(alignment: .top) {
            if gapBelow > 0 {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .offset(y: -0.5)
            }
        }
    }
}

/// Brief centered glass confirmation toast (list saved, checked cleared, etc.).
private struct StoreGlassToastConfirmation: View {
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(uiColor: .label))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(message)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(20)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

/// Store bottom bar: opens pull-to-add so items can be added to the shopping list.
private struct StoreAddItemToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .catalogToolbarCircularTapTarget()
        .clipShape(Circle())
        .appThemeTint()
        .appThemeIdentity()
        .accessibilityLabel(LocalizedCopy.addItem)
    }
}

/// Tracks whether the shopping `List` scroll position is at the top.
private struct PullToAddScrollHostAtTopModifier: ViewModifier {
    @Binding var state: Bool

    private static let scrollEdgeSlack: CGFloat = 6

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self) { geometry in
            let adjustedTop = geometry.contentOffset.y + geometry.contentInsets.top
            return adjustedTop <= Self.scrollEdgeSlack
        } action: { _, atTop in
            state = atTop
        }
    }
}

/// Tracks whether the shopping `List` scroll position is at the bottom.
private struct PullToClearScrollHostAtBottomModifier: ViewModifier {
    @Binding var state: Bool

    private static let scrollEdgeSlack: CGFloat = 6

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self) { geometry in
            let distanceFromBottom = geometry.contentSize.height
                - geometry.contentOffset.y
                - geometry.containerSize.height
                + geometry.contentInsets.bottom
            return distanceFromBottom <= Self.scrollEdgeSlack
        } action: { _, atBottom in
            state = atBottom
        }
    }
}

/// Owns alert presentation so keystrokes do not re-render `ShoppingView` (which dismisses the field).
/// Uses UIKit so Create is `preferredAction` (white text on prominent fill), matching move-to-new-section.
private struct SaveShoppingListAsRecipeAlert: View {
    @Binding var isPresented: Bool
    let onConfirm: (String) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background(
                SaveShoppingListUIKitAlertBridge(
                    isPresented: $isPresented,
                    onConfirm: onConfirm
                )
            )
    }
}

private struct SaveShoppingListUIKitAlertBridge: UIViewRepresentable {
    @Binding var isPresented: Bool
    let onConfirm: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.onConfirm = onConfirm
        if isPresented {
            context.coordinator.presentIfNeeded(from: uiView)
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }

    @MainActor
    final class Coordinator {
        var isPresented: Binding<Bool>
        var onConfirm: ((String) -> Void)?
        private weak var presentedAlert: UIAlertController?
        private var isPresenting = false

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func presentIfNeeded(from view: UIView) {
            guard presentedAlert == nil, !isPresenting else { return }
            isPresenting = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.isPresented.wrappedValue else {
                    self.isPresenting = false
                    return
                }
                guard self.presentedAlert == nil else {
                    self.isPresenting = false
                    return
                }
                guard let presenter = view.nearestViewControllerForAlert() else {
                    self.isPresenting = false
                    self.isPresented.wrappedValue = false
                    return
                }

                let alert = UIAlertController(
                    title: LocalizedCopy.saveList,
                    message: nil,
                    preferredStyle: .alert
                )
                alert.addTextField { field in
                    field.placeholder = LocalizedCopy.listName
                    field.autocapitalizationType = .words
                    field.autocorrectionType = .default
                }

                let createAction = UIAlertAction(title: LocalizedCopy.create, style: .default) { [weak self] _ in
                    let raw = alert.textFields?.first?.text ?? ""
                    guard let self else { return }
                    // Clear presentation state before onConfirm. Confirm shows a toast and
                    // re-renders ShoppingView; if isPresented is still true and presentedAlert
                    // was already nil, updateUIView would present the alert again.
                    self.presentedAlert = nil
                    self.isPresenting = false
                    self.isPresented.wrappedValue = false
                    DispatchQueue.main.async {
                        self.onConfirm?(raw)
                    }
                }
                alert.addAction(createAction)
                alert.addAction(UIAlertAction(title: LocalizedCopy.cancel, style: .cancel) { [weak self] _ in
                    self?.presentedAlert = nil
                    self?.isPresenting = false
                    self?.isPresented.wrappedValue = false
                })
                alert.preferredAction = createAction

                self.presentedAlert = alert
                presenter.present(alert, animated: true) {
                    self.isPresenting = false
                }
            }
        }

        func dismissIfNeeded() {
            guard let alert = presentedAlert else { return }
            presentedAlert = nil
            isPresenting = false
            alert.dismiss(animated: true)
        }
    }
}

private extension UIView {
    func nearestViewControllerForAlert() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController.presentedViewController ?? viewController
            }
            responder = current.next
        }
        return nil
    }
}

/// Pull-to-add search respects keyboard insets; shopping list and empty art do not.
private struct StorePullToAddKeyboardSafeAreaModifier: ViewModifier {
    let respectsKeyboard: Bool

    func body(content: Content) -> some View {
        if respectsKeyboard {
            content
        } else {
            content.ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}
