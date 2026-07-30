import SwiftUI
import UIKit

/// Store pull-to-add: catalog search and add without leaving the shopping list.
struct StorePullToAddCatalogSearchView: View {
    private static let bottomFloatingBarClearance: CGFloat = 86
    /// Space below the no-match placeholder so it stays above the toolbar search field.
    private static let toolbarSearchFieldClearance: CGFloat = 56
    /// Reserve nav/search chrome height for the no-match placeholder band.
    private static let toolbarSearchCollapsedTopChromeClearance: CGFloat = 100
    private static let regularWidthClassListMaxWidth: CGFloat = 640

    @EnvironmentObject private var store: GroceryStore
    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.shoppingListSpacingScale) private var listSpacingScale
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppTextSize.storageKey) private var textSizeRaw: String = AppTextSize.defaultSize.rawValue

    @Binding var isSearchPresented: Bool
    @Binding var searchText: String
    @Binding var pinnedSearchQuery: String
    /// Stable identity for the searchable chrome, owned by `ShoppingView` and regenerated only
    /// when a pull-to-add session begins, so adds do not churn the search field's identity.
    var searchChromeID: UUID
    var onPresentNewItem: (String) -> Void
    /// Pops pull-to-add back to Store (Cancel + return/search submit).
    var onEndSearch: () -> Void
    /// Sheet presentation: focused glass `TextField` so the keyboard rises with the sheet.
    /// Uses a sticky UIKit field that refuses to resign on row taps (unlike SwiftUI `TextField`).
    var usesFocusedSearchField: Bool = false
    /// When true, allows resign and drops focus (e.g. first-item explainer over pull-to-add).
    /// Clearing it while the sheet is still up restores the keyboard.
    var searchKeyboardSuppressed: Binding<Bool> = .constant(false)

    @State private var expandedPullToAddQuantityPillItemID: UUID?
    @State private var stickySearchFieldFocused = false
    @State private var allowsSearchFieldResign = false

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPinnedSearchQuery: String {
        pinnedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeFilterQuery: String? {
        if !trimmedSearchText.isEmpty { return trimmedSearchText }
        if !trimmedPinnedSearchQuery.isEmpty { return trimmedPinnedSearchQuery }
        return nil
    }

    private var toolbarSearchEmptyQueryActive: Bool {
        isSearchPresented && activeFilterQuery == nil
    }

    private var catalogItemsForList: [GroceryItem] {
        guard isSearchPresented, let query = activeFilterQuery else { return [] }
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

    private var toolbarSearchNoMatches: Bool {
        isSearchPresented
            && activeFilterQuery != nil
            && catalogItemsForList.isEmpty
    }

    private var showsCatalogListRows: Bool {
        !toolbarSearchEmptyQueryActive && !toolbarSearchNoMatches
    }

    /// Mirrors Home search: blank when the field is empty, match count while querying, no-match copy when empty.
    private var principalSubtitleText: String {
        guard activeFilterQuery != nil else { return "" }
        if catalogItemsForList.isEmpty {
            return LocalizedCopy.noMatchingItemsFound
        }
        return LocalizedCopy.searchItemsFound(catalogItemsForList.count)
    }

    private var principalAccessibilityLabel: String {
        let subtitle = principalSubtitleText
        if subtitle.isEmpty {
            return LocalizedCopy.addItem
        }
        if catalogItemsForList.isEmpty {
            return "\(LocalizedCopy.addItem), \(subtitle)"
        }
        return "\(LocalizedCopy.addItem), \(LocalizedCopy.searchItemsFoundAccessibilityLabel(catalogItemsForList.count))"
    }

    private var catalogTextDynamicTypeSize: DynamicTypeSize {
        AppTextSize.resolved(from: textSizeRaw).dynamicTypeSize
    }

    private var sortedCatalogItemsForList: [GroceryItem] {
        catalogItemsForList.sorted { lhs, rhs in
            let nameA = lhs.displayName(appContentLanguage: catalogLanguage)
            let nameB = rhs.displayName(appContentLanguage: catalogLanguage)
            let comparison = nameA.localizedCaseInsensitiveCompare(nameB)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        ZStack {
            Color.shoppingListBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Group {
                if showsCatalogListRows {
                    catalogResultsList
                }
            }
            .id(searchChromeID)
            .modifier(StorePullToAddNativeSearchableModifier(
                enabled: !usesFocusedSearchField,
                searchText: $searchText,
                isSearchPresented: $isSearchPresented,
                onSubmit: handleSearchSubmit
            ))

            if toolbarSearchNoMatches {
                noMatchesPlaceholder
                    .transition(.identity)
            } else if toolbarSearchEmptyQueryActive {
                emptyQueryPlaceholder
                    .transition(.identity)
            }
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? Self.regularWidthClassListMaxWidth : .infinity)
        .frame(maxWidth: .infinity)
        // Search field on the ZStack (not the results Group) so it stays visible with an empty query.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesFocusedSearchField {
                focusedSearchFieldBar
            } else {
                Color.clear
                    .frame(height: Self.bottomFloatingBarClearance)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(LocalizedCopy.addItem)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                    Text(principalSubtitleText)
                        .font(.footnote.weight(.regular))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(principalAccessibilityLabel)
                .accessibilityAddTraits(.isHeader)
            }
            if usesFocusedSearchField {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedCopy.done) {
                        dismissStorePullToAddSearch()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .onAppear {
            guard usesFocusedSearchField else { return }
            isSearchPresented = true
            applySearchKeyboardSuppression(searchKeyboardSuppressed.wrappedValue)
        }
        .onDisappear {
            guard usesFocusedSearchField else { return }
            allowsSearchFieldResign = true
            stickySearchFieldFocused = false
        }
        .onChange(of: searchKeyboardSuppressed.wrappedValue) { _, suppressed in
            guard usesFocusedSearchField else { return }
            applySearchKeyboardSuppression(suppressed)
        }
        .onChange(of: searchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pinnedSearchQuery = ""
            }
        }
    }

    private func applySearchKeyboardSuppression(_ suppressed: Bool) {
        if suppressed {
            allowsSearchFieldResign = true
            stickySearchFieldFocused = false
        } else {
            allowsSearchFieldResign = false
            Task { @MainActor in
                await Task.yield()
                stickySearchFieldFocused = true
            }
        }
    }

    private var focusedSearchFieldBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            StickyKeyboardSearchField(
                text: $searchText,
                placeholder: LocalizedCopy.searchOrCreateItem,
                isFocused: $stickySearchFieldFocused,
                allowsResign: $allowsSearchFieldResign,
                onSubmit: handleSearchSubmit
            )
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            if !trimmedSearchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedCopy.search)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    private var catalogResultsList: some View {
        List {
            ForEach(sortedCatalogItemsForList) { item in
                StorePullToAddCatalogItemRow(
                    item: item,
                    expandedQuantityPillItemID: $expandedPullToAddQuantityPillItemID,
                    onAddedToShopping: pinSearchAndClearField
                )
                // Vertical padding lives inside the row (under its tap overlay) so the
                // full cell height stays tappable, matching Store/Home row feel.
                .homeCatalogListItemRowStyle(appliesVerticalContentPadding: false)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dynamicTypeSize(catalogTextDynamicTypeSize)
        .shoppingListDensity()
        .animation(AppTextSize.layoutCommitAnimation, value: textSizeRaw)
        .listSectionSpacing(ShoppingListMetrics.interSectionSpacing)
        .scrollEdgeSoftTopIfAvailable(when: showsCatalogListRows)
        .catalogListLayoutDirection()
        .scrollDismissesKeyboard(.never)
        .environment(\.expandedQuantityPillItemID, expandedPullToAddQuantityPillItemID)
    }

    private func pinSearchAndClearField() {
        if !trimmedSearchText.isEmpty {
            pinnedSearchQuery = trimmedSearchText
        }
        searchText = ""
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

    private func handleSearchSubmit() {
        let trimmed = trimmedSearchText
        if trimmed.isEmpty {
            dismissStorePullToAddSearch()
            return
        }
        if let match = catalogItemMatchingSearchTermExactly(trimmed) {
            let itemID = match.id
            dismissStorePullToAddSearch()
            // Add on the next turn so the navigation pop can commit first. Mutating shopping in
            // the same turn as `navigationPath.removeLast()` was leaving pull-to-add on screen.
            DispatchQueue.main.async {
                store.addToShopping(itemID: itemID, quantity: 1)
            }
            return
        }
        presentNewItemAllowingKeyboardHandoff(trimmed)
    }

    private func dismissStorePullToAddSearch() {
        searchText = ""
        pinnedSearchQuery = ""
        isSearchPresented = false
        if usesFocusedSearchField {
            allowsSearchFieldResign = true
            stickySearchFieldFocused = false
        }
        // Pop now (Cancel/`onChange` may also fire) and again next turn as a safety net —
        // search `onSubmit` + binding writes can drop a same-turn `NavigationPath` update.
        onEndSearch()
        DispatchQueue.main.async {
            onEndSearch()
        }
        Task { @MainActor in
            await Task.yield()
            dismissSearch()
        }
    }

    private func presentNewItemAllowingKeyboardHandoff(_ name: String) {
        if usesFocusedSearchField {
            // Let New Item's name field take first responder.
            allowsSearchFieldResign = true
            stickySearchFieldFocused = false
        }
        onPresentNewItem(name)
    }

    @ViewBuilder
    private var noMatchesPlaceholder: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Button(LocalizedCopy.createItem) {
                handleSearchSubmit()
            }
            .font(.body)
            .modifier(StorePullToAddCreateItemButtonStyle())
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
        .padding(.top, Self.toolbarSearchCollapsedTopChromeClearance)
        .padding(.bottom, Self.toolbarSearchFieldClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// Empty field with no pinned query — nudge to start typing (not shown after add-and-clear pin).
    private var emptyQueryPlaceholder: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(LocalizedCopy.typeToFilterItems)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .offset(y: -15)
            Spacer(minLength: 0)
        }
        .padding(.top, Self.toolbarSearchCollapsedTopChromeClearance)
        .padding(.bottom, Self.toolbarSearchFieldClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalizedCopy.typeToFilterItems)
    }
}

/// Applies `.searchable` only for the pushed destination path (not the sheet focused field).
private struct StorePullToAddNativeSearchableModifier: ViewModifier {
    let enabled: Bool
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    let onSubmit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(
                    text: $searchText,
                    isPresented: $isSearchPresented,
                    placement: .toolbar,
                    prompt: LocalizedCopy.searchOrCreateItem
                )
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .onSubmit(of: .search) {
                    onSubmit()
                }
        } else {
            content
        }
    }
}

/// UIKit search field that refuses to resign on list row taps so the keyboard stays up while adding.
private struct StickyKeyboardSearchField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var isFocused: Bool
    @Binding var allowsResign: Bool
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> StickyKeyboardUITextField {
        let field = StickyKeyboardUITextField(frame: .zero)
        field.delegate = context.coordinator
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.font = .preferredFont(forTextStyle: .body)
        field.returnKeyType = .search
        field.clearButtonMode = .never
        field.autocapitalizationType = .sentences
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: StickyKeyboardUITextField, context: Context) {
        context.coordinator.parent = self
        uiView.allowsResign = allowsResign
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }
        if uiView.text != text {
            uiView.text = text
        }
        if isFocused {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    _ = uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder, allowsResign {
            _ = uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // Single-line field: take the proposed width but never more than the intrinsic text height,
    // otherwise the glass capsule inflates to fill the sheet.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: StickyKeyboardUITextField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: uiView.intrinsicContentSize.height
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: StickyKeyboardSearchField

        init(parent: StickyKeyboardSearchField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            let newText = textField.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
            if parent.allowsResign { return true }
            // Swipe-down dismiss: allow resign while the sheet is being dismissed.
            var responder: UIResponder? = textField
            while let current = responder {
                if let viewController = current as? UIViewController, viewController.isBeingDismissed {
                    return true
                }
                responder = current.next
            }
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.allowsResign, parent.isFocused {
                parent.isFocused = false
            }
        }
    }
}

private final class StickyKeyboardUITextField: UITextField {
    var allowsResign = false

    override func resignFirstResponder() -> Bool {
        guard allowsResign || isHostBeingDismissed else { return false }
        return super.resignFirstResponder()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        // Swipe-dismiss / sheet teardown: system resign is refused while still attached,
        // so force resign here once the field is leaving the hierarchy.
        if newWindow == nil {
            forceResignForTeardown()
        }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            forceResignForTeardown()
        }
    }

    private func forceResignForTeardown() {
        allowsResign = true
        guard isFirstResponder else { return }
        _ = super.resignFirstResponder()
    }

    /// True while the sheet (or any ancestor VC) is interactively or programmatically dismissing.
    private var isHostBeingDismissed: Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController, viewController.isBeingDismissed {
                return true
            }
            responder = current.next
        }
        return false
    }
}

/// No-results **Create Item** — matches Home toolbar search (glass capsule, large control).
private struct StorePullToAddCreateItemButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .appThemeTint()
    }
}

private struct StorePullToAddCatalogItemRow: View {
    @EnvironmentObject private var store: GroceryStore
    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.shoppingListSpacingScale) private var spacingScale

    let item: GroceryItem
    @Binding var expandedQuantityPillItemID: UUID?
    let onAddedToShopping: () -> Void

    @State private var isQuantityPillExpanded = false

    private var usesManualMirror: Bool {
        CatalogLayoutMirroring.usesManualCatalogMirror(
            catalogLanguage: catalogLanguage,
            layoutDirection: layoutDirection
        )
    }

    private var isInShopping: Bool {
        store.shopping.contains(where: { $0.itemID == item.id })
    }

    private var qty: Int {
        store.shoppingListQuantity(for: item.id)
    }

    var body: some View {
        rowLabel
            .listRowFullBleedHitArea(
                alignment: CatalogLayoutMirroring.rowContentAlignment(
                    catalogLanguage: catalogLanguage,
                    layoutDirection: layoutDirection
                )
            )
            // Padding sits inside the tap overlay so the overlay spans the full cell height.
            .padding(ShoppingListMetrics.homeCatalogItemRowVerticalContentPadding(scale: spacingScale))
            .overlay {
                CatalogListRowTapTouchOverlay(
                    item: item,
                    usesGlassChrome: true,
                    onTap: handleTap
                )
                .listRowFullBleedHitArea()
            }
            .onChange(of: expandedQuantityPillItemID) { _, expandedID in
                syncQuantityPillExpansion(with: expandedID)
            }
            .onChange(of: isInShopping) { _, inShopping in
                guard !inShopping else { return }
                quantityPillExpandedBinding.wrappedValue = false
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                LocalizedCopy.pullToAddCatalogRowAccessibilityLabel(
                    name: item.displayName(appContentLanguage: catalogLanguage),
                    isInShopping: isInShopping,
                    quantity: qty
                )
            )
            .accessibilityAddTraits(.isButton)
    }

    private func syncQuantityPillExpansion(with expandedID: UUID?) {
        let shouldExpand = expandedID == item.id
        guard isQuantityPillExpanded != shouldExpand else { return }
        isQuantityPillExpanded = shouldExpand
    }

    private var quantityPillExpandedBinding: Binding<Bool> {
        Binding(
            get: { isQuantityPillExpanded },
            set: { newValue in
                isQuantityPillExpanded = newValue
                if newValue {
                    expandedQuantityPillItemID = item.id
                } else if expandedQuantityPillItemID == item.id {
                    expandedQuantityPillItemID = nil
                }
            }
        )
    }

    private func handleTap() {
        if expandedQuantityPillItemID == item.id {
            return
        }
        withAnimation(QuantityPillChromeTiming.expandCollapse) {
            expandedQuantityPillItemID = nil
        }
        if isInShopping {
            store.removeFromShopping(itemID: item.id)
        } else {
            store.addToShopping(itemID: item.id, quantity: 1)
            onAddedToShopping()
            QuantityPillChromeTiming.expandAfterAdd(
                itemID: item.id,
                guardInShopping: { [store] in
                    store.shopping.contains(where: { $0.itemID == item.id })
                },
                setExpandedItemID: { expandedQuantityPillItemID = $0 }
            )
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
        isInShopping && isQuantityPillExpanded ? Font.body.weight(.bold) : .body
    }

    private var hebrewRow: some View {
        HStack(spacing: 0) {
            quantityPillColumn
            Text(item.displayName(appContentLanguage: catalogLanguage))
                .font(rowItemNameFont)
                .animation(QuantityPillChromeTiming.expandCollapse, value: isQuantityPillExpanded)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isInShopping ? appTheme.color : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var englishRow: some View {
        HStack(spacing: 0) {
            Text(item.displayName(appContentLanguage: catalogLanguage))
                .font(rowItemNameFont)
                .animation(QuantityPillChromeTiming.expandCollapse, value: isQuantityPillExpanded)
                .multilineTextAlignment(.leading)
                .foregroundStyle(isInShopping ? appTheme.color : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            quantityPillColumn
        }
    }

    private var quantityPillColumn: some View {
        Group {
            if isInShopping {
                quantityPill(qty: qty, itemID: item.id)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(height: 0, alignment: .center)
            }
        }
        .frame(
            minWidth: CatalogListRowDensity.quantityPillSlotMinWidth
                + CatalogListRowDensity.quantityPillHorizontalNudge,
            alignment: usesManualMirror ? .leading : .trailing
        )
    }

    private func quantityPill(qty: Int, itemID: UUID) -> some View {
        ExpandableQuantityPill(
            quantity: qty,
            style: .glass,
            usesLivePadding: false,
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

