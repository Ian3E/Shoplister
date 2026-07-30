import SwiftUI

/// Centered Store empty overlay with first-run add hints.
struct ShoppingEmptyStateView: View {
    var showsAddHint: Bool = true
    /// Checkmark only after the list has been cleared at least once (not on first-launch empty).
    var showsCheckmark: Bool = true
    /// Fades the title + hint only (checkmark uses draw, not opacity).
    var textOpacity: CGFloat = 1
    /// Set by Store when the list becomes empty after a complete/clear; consumed on appear.
    @Binding var pendingCheckmarkDraw: Bool

    /// Starts the draw 0.4s before the text fade-in completes
    /// (`ShoppingView.emptyShoppingRevealAnimation`, 0.48s) so the two mostly overlap.
    private static let checkmarkDrawDelaySeconds: TimeInterval = 0.08

    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .largeTitle) private var emptyStateIconSize: CGFloat = 48
    /// `drawOn` semantics: **active = undrawn**; deactivating plays the draw-on stroke.
    /// Mounts `true` only when a celebrate draw is pending, so revisits render fully drawn.
    @State private var isCheckmarkUndrawn: Bool
    @State private var checkmarkDrawTask: Task<Void, Never>?

    init(
        showsAddHint: Bool = true,
        showsCheckmark: Bool = true,
        textOpacity: CGFloat = 1,
        pendingCheckmarkDraw: Binding<Bool>
    ) {
        self.showsAddHint = showsAddHint
        self.showsCheckmark = showsCheckmark
        self.textOpacity = textOpacity
        self._pendingCheckmarkDraw = pendingCheckmarkDraw
        self._isCheckmarkUndrawn = State(initialValue: pendingCheckmarkDraw.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsCheckmark {
                Image(systemName: "checkmark.app.fill")
                    .font(.system(size: emptyStateIconSize, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(appTheme.color)
                    .symbolEffect(.drawOn, isActive: isCheckmarkUndrawn)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                Text(LocalizedCopy.shoppingListEmptyTitleAllDone)
                    .font(.title3.weight(.semibold))

                if showsAddHint {
                    addHintFooter
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                }
            }
            .opacity(textOpacity)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .onAppear {
            guard pendingCheckmarkDraw else { return }
            beginCheckmarkDraw()
        }
        .onChange(of: pendingCheckmarkDraw) { _, pending in
            guard pending else { return }
            // Rare path: view already mounted when a new celebrate lands. Reset to undrawn
            // without animating an erase, then draw.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                isCheckmarkUndrawn = true
            }
            beginCheckmarkDraw()
        }
        .onDisappear {
            checkmarkDrawTask?.cancel()
            checkmarkDrawTask = nil
        }
    }

    private var addHintFooter: some View {
        VStack(spacing: 16) {
            pullDownAddHintLine
            browseItemsHintLine
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var pullDownAddHintLine: some View {
        HStack(spacing: 6) {
            Text(LocalizedCopy.shoppingListEmptyAddHintPullDownPrefix)
            plusGlassHintChip
            Text(LocalizedCopy.shoppingListEmptyAddHintPullDownSuffix)
        }
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
    }

    private var browseItemsHintLine: some View {
        HStack(spacing: 6) {
            Text(LocalizedCopy.shoppingListEmptyAddHintTapPrefix)
            Image(systemName: "square.grid.2x2.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text(LocalizedCopy.shoppingListEmptyAddHintBrowseSuffix)
        }
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
    }

    /// Clear-glass circular + with theme-colored glyph (decorative — not tappable).
    private var plusGlassHintChip: some View {
        Button(action: {}) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appTheme.color)
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(true)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var accessibilityLabelText: String {
        if showsAddHint {
            return "\(LocalizedCopy.shoppingListEmptyTitleAllDone). \(LocalizedCopy.shoppingListEmptyAddHintAccessibility)"
        }
        return LocalizedCopy.shoppingListEmptyTitleAllDone
    }

    private func beginCheckmarkDraw() {
        pendingCheckmarkDraw = false
        checkmarkDrawTask?.cancel()
        checkmarkDrawTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.checkmarkDrawDelaySeconds))
            guard !Task.isCancelled else { return }
            // Deactivating `drawOn` strokes the symbol in; the effect owns its own timing.
            isCheckmarkUndrawn = false
        }
    }
}
