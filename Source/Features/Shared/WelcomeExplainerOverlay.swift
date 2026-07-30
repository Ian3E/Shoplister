import SwiftUI

struct WelcomeExplainerOverlay: View {
    let onDone: () -> Void

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var measuredContentHeight: CGFloat = 0

    private let cardHorizontalInset: CGFloat = 16
    private let cardMaxWidth: CGFloat = 340
    private let cardTextVerticalInset: CGFloat = 15
    private let cardCornerRadius: CGFloat = 34
    private static let fadeAnimation = Animation.easeInOut(duration: 0.25)
    private static let fadeOutDuration: Duration = .milliseconds(250)
    private static let scrollMaxHeight: CGFloat = 420

    private var welcomeTips: [(systemImage: String, detail: String, usesMarkdown: Bool)] {
        [
            (
                "mappin.and.ellipse",
                LocalizedCopy.welcomeExplainerItemSections,
                true
            ),
            (
                "square.grid.2x2.fill",
                LocalizedCopy.welcomeExplainerHomeLibraryGrouping,
                false
            ),
            (
                "checklist",
                LocalizedCopy.welcomeExplainerShoppingListGrouping,
                false
            ),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.55 : 0)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            cardContent
                .opacity(isVisible ? 1 : 0)
                .padding(.horizontal, 28)
        }
        .onAppear {
            withAnimation(Self.fadeAnimation) {
                isVisible = true
            }
        }
        .onDisappear {
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .center, spacing: 16) {
                    Text(LocalizedCopy.welcomeExplainerTitle)
                        .font(.system(size: 18, weight: .bold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(welcomeTips.enumerated()), id: \.offset) { _, tip in
                            welcomeTipRow(
                                systemImage: tip.systemImage,
                                detail: tip.detail,
                                usesMarkdown: tip.usesMarkdown
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Color(uiColor: .label))
                .padding(.horizontal, cardHorizontalInset)
                .padding(.top, cardTextVerticalInset)
                .padding(.bottom, cardTextVerticalInset)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: WelcomeContentHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: measuredContentHeight == 0
                ? Self.scrollMaxHeight
                : min(measuredContentHeight, Self.scrollMaxHeight))
            .onPreferenceChange(WelcomeContentHeightKey.self) { measuredContentHeight = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(LocalizedCopy.welcomeExplainerAccessibilityLabel)
            .accessibilityAddTraits(.isModal)

            Button(action: dismissAnimated) {
                Text(LocalizedCopy.done)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .appThemeTint()
            .padding(.horizontal, cardHorizontalInset)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: cardMaxWidth)
        .background {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
    }

    private func welcomeTipRow(systemImage: String, detail: String, usesMarkdown: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            Group {
                if usesMarkdown {
                    welcomeExplainerBodyText(detail)
                } else {
                    Text(detail)
                }
            }
            .font(.body)
            .foregroundStyle(Color(uiColor: .label))
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func welcomeExplainerBodyText(_ localized: String) -> Text {
        guard var attributed = try? AttributedString(
            markdown: localized,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return Text(localized)
        }

        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                attributed[run.range].font = .body.weight(.semibold)
            } else {
                attributed[run.range].font = .body
            }
        }

        return Text(attributed)
    }

    private func dismissAnimated() {
        dismissTask?.cancel()
        withAnimation(Self.fadeAnimation) {
            isVisible = false
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: Self.fadeOutDuration)
            guard !Task.isCancelled else { return }
            onDone()
        }
    }
}

private struct WelcomeContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
