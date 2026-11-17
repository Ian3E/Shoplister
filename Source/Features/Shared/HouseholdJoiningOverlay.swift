import SwiftUI

/// Centered card shown after tapping Join on a household invite (same look as the first-time
/// explainers). The button reads "Joining" with a spinner while the household's lists download,
/// then becomes Done.
struct HouseholdJoiningOverlay: View {
    /// False while the download is still running.
    let isFinished: Bool
    let onDone: () -> Void

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?

    private let cardHorizontalInset: CGFloat = 16
    private let cardMaxWidth: CGFloat = 340
    private let cardTextVerticalInset: CGFloat = 15
    private let cardCornerRadius: CGFloat = 34
    private static let fadeAnimation = Animation.easeInOut(duration: 0.25)
    private static let fadeOutDuration: Duration = .milliseconds(250)

    private var tips: [(systemImage: String, detail: String)] {
        [
            ("checklist", LocalizedCopy.householdJoiningTipLists),
            ("square.grid.2x2.fill", LocalizedCopy.householdJoiningTipLibrary),
            ("arrow.triangle.2.circlepath", LocalizedCopy.householdJoiningTipSync),
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
            VStack(alignment: .center, spacing: 16) {
                Text(LocalizedCopy.householdShareTitle)
                    .font(.system(size: 18, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        tipRow(systemImage: tip.systemImage, detail: tip.detail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color(uiColor: .label))
            .padding(.horizontal, cardHorizontalInset)
            .padding(.vertical, cardTextVerticalInset)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)

            Button(action: dismissAnimated) {
                HStack(spacing: 8) {
                    Text(isFinished ? LocalizedCopy.done : LocalizedCopy.joining)
                        .font(.body.weight(.semibold))
                    if !isFinished {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .appThemeTint()
            .disabled(!isFinished)
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

    private func tipRow(systemImage: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            Text(detail)
                .font(.body)
                .foregroundStyle(Color(uiColor: .label))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
