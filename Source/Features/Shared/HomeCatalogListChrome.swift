import SwiftUI

// MARK: - List coordinate space

enum HomeCatalogListCoordinateSpace {
    static let name = "homeCatalogList"
}

// MARK: - Dividers

enum HomeCatalogListDividerChrome {
    static var sectionLineColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.12)
                : UIColor(white: 0.84, alpha: 1)
        })
    }
}

struct HomeCatalogListDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

// MARK: - Section title bar

struct HomeCatalogSectionTitleBar: View {
    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.shoppingListSpacingScale) private var spacingScale

    let sections: [(id: UUID, title: String)]
    let activeSectionID: UUID?
    let suppressBarSync: Bool
    let onTitleTap: (UUID) -> Void

    private let titleBarHorizontalInset: CGFloat = 24
    private var titleSpacing: CGFloat { 26 * spacingScale }
    private var titleVerticalPadding: CGFloat { 10 * spacingScale }

    /// Pin the active title to the reading-start edge.
    ///
    /// iOS 27+: `.leading` under forced catalog `layoutDirection` already means reading-start
    /// (right for Hebrew, left for English), even when the phone is English + library is Hebrew.
    ///
    /// iOS 26: scroll anchors behave more like physical edges, so Hebrew/RTL needs `.trailing`
    /// to pin to the right (reading-start) while LTR stays `.leading`.
    private var activeTitlePinAnchor: UnitPoint {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            return .leading
        }
        return catalogLayoutDirection == .rightToLeft ? .trailing : .leading
    }

    private var catalogLayoutDirection: LayoutDirection {
        CatalogLayoutMirroring.catalogLayoutDirection(for: catalogLanguage)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: titleSpacing) {
                    ForEach(sections, id: \.id) { section in
                        Button {
                            withAnimation(.snappy) {
                                proxy.scrollTo(section.id, anchor: activeTitlePinAnchor)
                            }
                            onTitleTap(section.id)
                        } label: {
                            Text(section.title)
                                .font(CatalogGroupHeaderChrome.titleFont)
                                .foregroundStyle(titleColor(for: section.id))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.plain)
                        .id(section.id)
                        .accessibilityLabel(section.title)
                    }
                }
                .padding(.vertical, titleVerticalPadding)
                .environment(\.layoutDirection, catalogLayoutDirection)
            }
            .environment(\.layoutDirection, catalogLayoutDirection)
            .contentMargins(.horizontal, titleBarHorizontalInset, for: .scrollContent)
            .clipped()
            .onChange(of: activeSectionID) { _, sectionID in
                guard !suppressBarSync, let sectionID else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(sectionID, anchor: activeTitlePinAnchor)
                }
            }
            .onAppear {
                guard let sectionID = activeSectionID else { return }
                proxy.scrollTo(sectionID, anchor: activeTitlePinAnchor)
            }
        }
        .environment(\.layoutDirection, catalogLayoutDirection)
    }

    private func titleColor(for sectionID: UUID) -> Color {
        sectionID == activeSectionID
            ? Color(uiColor: .label)
            : HomeCatalogSectionTitleChrome.inactiveTitleColor
    }
}

enum HomeCatalogSectionTitleChrome {
    static var inactiveTitleColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .tertiaryLabel
                : UIColor(white: 0.78, alpha: 1)
        })
    }
}

extension View {
    /// Pins the section title slider above the list and lets rows scroll beneath it with Liquid Glass.
    @ViewBuilder
    func homeCatalogSectionTitleSafeAreaBar<Bar: View>(
        isPresented: Bool,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        if isPresented {
            self
                .safeAreaBar(edge: .top, spacing: 0) {
                    bar()
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular, in: .rect)
                }
        } else {
            self
        }
    }
}

// MARK: - Row scroll anchors

struct HomeCatalogRowAnchor: Equatable {
    let sectionID: UUID
    let minY: CGFloat
    let maxY: CGFloat
}

struct HomeCatalogRowAnchorKey: PreferenceKey {
    static var defaultValue: [HomeCatalogRowAnchor] = []

    static func reduce(value: inout [HomeCatalogRowAnchor], nextValue: () -> [HomeCatalogRowAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func reportHomeCatalogRowAnchor(sectionID: UUID) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(HomeCatalogListCoordinateSpace.name))
                Color.clear.preference(
                    key: HomeCatalogRowAnchorKey.self,
                    value: [
                        HomeCatalogRowAnchor(
                            sectionID: sectionID,
                            minY: frame.minY,
                            maxY: frame.maxY
                        )
                    ]
                )
            }
        }
    }
}

// MARK: - List item cell

struct HomeCatalogListItemCell<Row: View>: View {
    @Environment(\.shoppingListSpacingScale) private var spacingScale

    let showsSectionDividerBelow: Bool
    let sectionScrollID: UUID?
    @ViewBuilder let row: () -> Row

    private var rowHorizontalInset: CGFloat {
        ShoppingListMetrics.homeCatalogItemRowHorizontalInset(scale: spacingScale)
    }

    var body: some View {
        VStack(spacing: 0) {
            rowContent
                .padding(ShoppingListMetrics.homeCatalogItemRowVerticalContentPadding(scale: spacingScale))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .zIndex(1)

            if showsSectionDividerBelow {
                HomeCatalogListDivider(color: HomeCatalogListDividerChrome.sectionLineColor)
                    .padding(.horizontal, -rowHorizontalInset)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .listRowInsets(ShoppingListMetrics.homeCatalogItemRowHorizontalListInsets(scale: spacingScale))
        .listRowSeparator(.hidden)
        // Clear per-row fill: `InventoryView` provides a full-bleed backdrop so glass pill halos can composite across row boundaries.
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var rowContent: some View {
        if let sectionScrollID {
            row().id(sectionScrollID)
        } else {
            row()
        }
    }
}

// MARK: - Quantity pill (glass)

struct HomeCatalogQuantityPillGlassStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
            .appThemeTint()
    }
}

/// Decorative quantity pill matching live row glass without button press feedback.
struct HomeCatalogQuantityPillStaticGlassStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule(style: .continuous))
            }
            .appThemeTint()
    }
}

// MARK: - Section scroll sync

struct HomeCatalogListScrollSnapshot: Equatable {
    var viewportHeight: CGFloat
    var contentTopInset: CGFloat
}

enum HomeCatalogSectionScrollSync {
    /// Active section = the section of whichever row is crossing the slider bottom edge.
    static func activeSectionID(
        anchors: [HomeCatalogRowAnchor],
        sliderBottomY: CGFloat,
        unsortedSectionID: UUID?,
        isUndefinedSectionRevealed: Bool,
        isProgrammaticListScroll: Bool,
        fallback: UUID?
    ) -> UUID? {
        guard !isProgrammaticListScroll else { return fallback }

        let crossingRow = anchors.first { anchor in
            guard anchor.minY <= sliderBottomY, anchor.maxY > sliderBottomY else { return false }
            guard let unsortedID = unsortedSectionID else { return true }
            return isUndefinedSectionRevealed || anchor.sectionID != unsortedID
        }

        return crossingRow?.sectionID ?? fallback
    }
}
