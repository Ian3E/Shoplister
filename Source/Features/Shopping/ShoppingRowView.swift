import SwiftUI
import UIKit

struct ShoppingRowView: View {
    private static let rowContentSpacing: CGFloat = 12
    private static let quantityEdgeInset: CGFloat = ShoppingRowQuantityMetrics.quantityEdgeInset
    private static let uncheckedSymbolName = "app"
    private static let checkedFillSymbolName = "app.fill"
    private static let checkedStrokeSymbolName = "checkmark"

    @Environment(\.appContentLanguage) private var catalogLanguage
    @Environment(\.appTheme) private var appTheme
    @Environment(\.layoutDirection) private var layoutDirection

    let entry: ShoppingEntry
    let item: GroceryItem

    private var checkmarkFont: Font {
        let pointSize = UIFont.preferredFont(forTextStyle: .body).pointSize * 1.25
        return .system(size: pointSize)
    }

    /// Sized to sit inside the filled square like `checkmark.app.fill`'s knocked-out check.
    private var checkStrokeFont: Font {
        let pointSize = UIFont.preferredFont(forTextStyle: .body).pointSize * 1.25 * 0.5
        return .system(size: pointSize, weight: .bold)
    }

    private var showsQuantity: Bool {
        entry.quantity > 1 && !entry.isChecked
    }

    private var usesManualMirror: Bool {
        CatalogLayoutMirroring.usesManualCatalogMirror(
            catalogLanguage: catalogLanguage,
            layoutDirection: layoutDirection
        )
    }

    private var revealsQuantityFromLeading: Bool {
        CatalogLayoutMirroring.quantityPillOnPhysicalLeadingEdge(for: catalogLanguage)
    }

    private var quantityEdgePadding: Edge.Set {
        revealsQuantityFromLeading ? .leading : .trailing
    }

    private var quantityStaticShift: CGFloat {
        ShoppingRowQuantityMetrics.layoutHorizontalOffset(
            ShoppingRowQuantityMetrics.listQuantityStaticShift(
                revealsFromLeading: revealsQuantityFromLeading,
                layoutDirection: layoutDirection
            ),
            layoutDirection: layoutDirection
        )
    }

    var body: some View {
        Group {
            if usesManualMirror {
                hebrewRow
            } else {
                englishRow
            }
        }
        .listRowFullBleedHitArea()
        .contentShape(Rectangle())
    }

    /// Mirror of `englishRow`: quantity on the far left, checkmark on the far right.
    private var hebrewRow: some View {
        HStack(alignment: .center, spacing: Self.rowContentSpacing) {
            leadingQuantitySlot

            Spacer(minLength: 0)

            Text(item.displayName(appContentLanguage: catalogLanguage))
                .font(.body)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .strikethrough(entry.isChecked, color: .secondary)
                .foregroundStyle(entry.isChecked ? .secondary : .primary)

            checkmarkImage
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var englishRow: some View {
        HStack(alignment: .center, spacing: Self.rowContentSpacing) {
            checkmarkImage

            Text(item.displayName(appContentLanguage: catalogLanguage))
                .font(.body)
                .lineLimit(1)
                .strikethrough(entry.isChecked, color: .secondary)
                .foregroundStyle(entry.isChecked ? .secondary : .primary)

            Spacer(minLength: 0)

            trailingQuantitySlot
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var leadingQuantitySlot: some View {
        if showsQuantity {
            quantityLabel(entry.quantity)
                .padding(quantityEdgePadding, Self.quantityEdgeInset)
        }
    }

    @ViewBuilder
    private var trailingQuantitySlot: some View {
        if showsQuantity {
            quantityLabel(entry.quantity)
                .padding(quantityEdgePadding, Self.quantityEdgeInset)
        }
    }

    /// Recomposes `checkmark.app.fill` so only the check strokes: `drawOn` on the whole
    /// filled symbol renders its square fill layer as a fade that hides the check draw.
    /// Here the square fills via a quick opacity swap and the check draws on top of it.
    /// `drawOn` semantics: active = undrawn, so unchecked holds the check hidden and
    /// checking deactivates the effect to play the draw.
    private var checkmarkImage: some View {
        ZStack {
            Image(systemName: Self.uncheckedSymbolName)
                .font(checkmarkFont)
                .foregroundStyle(appTheme.color)
            Image(systemName: Self.checkedFillSymbolName)
                .font(checkmarkFont)
                .foregroundStyle(appTheme.color)
                .opacity(entry.isChecked ? 1 : 0)
                // Checking snaps the fill in instantly (like native edit-mode selection);
                // unchecking keeps the row's `withAnimation(.snappy)` fade-out.
                .transaction { transaction in
                    if entry.isChecked {
                        transaction.animation = nil
                    }
                }
            Image(systemName: Self.checkedStrokeSymbolName)
                .font(checkStrokeFont)
                .foregroundStyle(.background)
                .symbolEffect(.drawOn, isActive: !entry.isChecked)
                // The tap handler toggles inside `withAnimation(.snappy)`; keep that
                // transaction off the draw so the effect owns its timing.
                .transaction { $0.animation = nil }
        }
    }

    private func quantityLabel(_ quantity: Int) -> some View {
        Text("\(quantity)")
            .font(ShoppingListChrome.trailingQuantityFont.monospacedDigit())
            .foregroundStyle(appTheme.color)
            .frame(minWidth: ShoppingRowQuantityMetrics.slotMinWidth)
            .offset(x: quantityStaticShift)
    }
}
