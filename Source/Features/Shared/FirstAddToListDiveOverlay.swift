import SwiftUI
import UIKit

/// One-shot controller for the All Items → shopping-list button “dive” celebration before the first-item explainer.
@MainActor
final class FirstAddToListDiveController: ObservableObject {
    struct Payload: Equatable {
        let itemName: String
        let sourceFrame: CGRect
    }

    @Published private(set) var payload: Payload?

    var isActive: Bool { payload != nil }

    func begin(itemName: String, sourceFrame: CGRect) {
        guard payload == nil else { return }
        guard sourceFrame.width > 1, sourceFrame.height > 1 else { return }
        payload = Payload(itemName: itemName, sourceFrame: sourceFrame)
    }

    func complete() {
        payload = nil
    }
}

/// Preference: Home catalog row title frames in global coordinates (for the first-add dive).
struct HomeItemNameGlobalFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Reports the **intrinsic** name bounds (call before expanding `.frame(maxWidth:)`).
    func reportHomeItemNameGlobalFrame(itemID: UUID) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: HomeItemNameGlobalFrameKey.self,
                    value: [itemID: geometry.frame(in: .global)]
                )
            }
        }
    }
}

/// Item name dives into the All Items shopping-list button, then a short +1 bubble rises and fades.
struct FirstAddToListDiveOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.appTheme) private var appTheme

    let itemName: String
    let sourceFrame: CGRect
    let targetPoint: CGPoint
    /// Fired when the +1 bubble finishes (reveal the shopping-list button badge).
    var onPlusOneFinished: () -> Void = {}
    let onFinished: () -> Void

    @State private var diveProgress: CGFloat = 0
    @State private var labelOpacity: CGFloat = 0
    @State private var showsFlyingLabel = true
    @State private var plusOneRise: CGFloat = 0
    @State private var plusOneOpacity: CGFloat = 1
    @State private var showsPlusOne = false

    /// Delay from tap → text fade-in.
    private static let initialDelayMs = 200
    private static let labelFadeInDuration: TimeInterval = 0.2
    private static let travelDuration: TimeInterval = 0.8
    private static let plusOneRiseDuration: TimeInterval = 0.65
    private static let plusOneFadeDuration: TimeInterval = 0.2

    var body: some View {
        GeometryReader { proxy in
            let localOrigin = proxy.frame(in: .global).origin
            let localStart = CGPoint(
                x: sourceFrame.midX - localOrigin.x,
                y: sourceFrame.midY - localOrigin.y
            )
            let localTarget = CGPoint(
                x: targetPoint.x - localOrigin.x,
                y: targetPoint.y - localOrigin.y
            )

            ZStack {
                if showsFlyingLabel {
                    Text(itemName)
                        .font(.body.weight(.bold))
                        .foregroundStyle(appTheme.color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        // AnimatableModifier samples each frame for a straight vertical dive.
                        .modifier(
                            FirstAddDiveFlightModifier(
                                progress: diveProgress,
                                start: localStart,
                                end: localTarget
                            )
                        )
                        .opacity(labelOpacity)
                        .allowsHitTesting(false)
                }

                if showsPlusOne {
                    Text("+1")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(appTheme.color))
                        .offset(y: -42 * plusOneRise)
                        .opacity(plusOneOpacity)
                        // Keep +1 on the dive’s vertical line (source x), not a lateral tab target.
                        .position(x: localStart.x, y: localTarget.y)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: runSequence)
    }

    private func runSequence() {
        if accessibilityReduceMotion {
            onPlusOneFinished()
            onFinished()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.initialDelayMs))

            withAnimation(.easeOut(duration: Self.labelFadeInDuration)) {
                labelOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(Int(Self.labelFadeInDuration * 1000)))

            withAnimation(.easeIn(duration: Self.travelDuration)) {
                diveProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(Int(Self.travelDuration * 1000)))

            showsFlyingLabel = false
            showsPlusOne = true
            withAnimation(.easeOut(duration: Self.plusOneRiseDuration)) {
                plusOneRise = 1
            }
            try? await Task.sleep(for: .milliseconds(Int(Self.plusOneRiseDuration * 1000)))

            withAnimation(.easeOut(duration: Self.plusOneFadeDuration)) {
                plusOneOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(Int(Self.plusOneFadeDuration * 1000)))

            onPlusOneFinished()
            onFinished()
        }
    }
}

/// Drives a straight vertical dive by animating `progress` (0…1).
/// X stays at the source; only Y moves — no parabolic lift or lateral drift.
private struct FirstAddDiveFlightModifier: AnimatableModifier {
    var progress: CGFloat
    var start: CGPoint
    var end: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = min(1, max(0, progress))
        let point = CGPoint(
            x: start.x,
            y: start.y + (end.y - start.y) * t
        )
        let travelOpacity: CGFloat = t < 0.88 ? 1 : max(0, (1 - t) / 0.12)

        content
            .opacity(travelOpacity)
            .position(point)
    }
}
