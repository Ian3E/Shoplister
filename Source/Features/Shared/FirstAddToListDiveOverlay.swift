import SwiftUI
import UIKit

/// One-shot controller for the Home → List tab “dive” celebration before the first-item explainer.
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

/// Continuously resolves the List tab icon center in window coordinates.
struct ListTabDiveTargetReader: UIViewRepresentable {
    @Binding var point: CGPoint

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onPointChange = { point = $0 }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onPointChange = { point = $0 }
        uiView.publishIfPossible()
    }

    final class ProbeView: UIView {
        var onPointChange: ((CGPoint) -> Void)?
        private var lastPoint: CGPoint = .zero

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publishIfPossible()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publishIfPossible()
        }

        func publishIfPossible() {
            guard let next = ListTabIconFrameLocator.listTabIconCenterInWindow() else { return }
            // Ignore sub-point jitter from repeated layout passes.
            guard hypot(next.x - lastPoint.x, next.y - lastPoint.y) > 0.5 else { return }
            lastPoint = next
            onPointChange?(next)
        }
    }
}

/// Resolves the List tab symbol center in window coordinates.
enum ListTabIconFrameLocator {
    static func listTabIconCenterInWindow() -> CGPoint? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden && window.alpha > 0.01 {
                if let center = listTabIconCenter(in: window) {
                    return center
                }
            }
        }
        return nil
    }

    private static func listTabIconCenter(in root: UIView) -> CGPoint? {
        guard let tabBar = findTabBar(in: root) else { return nil }
        let buttons = tabBarButtons(in: tabBar)
        guard !buttons.isEmpty else { return nil }

        let listTitle = LocalizedCopy.tabList
        let itemsTitle = LocalizedCopy.tabLibrary
        let sideTitles = [LocalizedCopy.addItem, LocalizedCopy.search]

        if let listButton = buttons.first(where: {
            buttonMatchesTitle($0, title: listTitle) && !buttonMatchesTitle($0, title: itemsTitle)
        }) {
            return center(of: listButton)
        }

        if let listButton = buttons.first(where: { buttonContainsSystemImageHint($0, hint: "checklist") }) {
            return center(of: listButton)
        }

        // Capsule primary tabs only — never the separated side control or Items tab.
        let primary = buttons.filter { button in
            !sideTitles.contains(where: { buttonMatchesTitle(button, title: $0) })
                && !buttonMatchesTitle(button, title: itemsTitle)
                && !buttonContainsSystemImageHint(button, hint: "square.grid")
                && !buttonContainsSystemImageHint(button, hint: "magnifyingglass")
                && !buttonContainsSystemImageHint(button, hint: "plus")
        }
        let candidates = primary.isEmpty ? buttons : primary
        let isRTL = tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        // List is the first root tab: leading edge of the capsule in LTR, trailing in RTL.
        let sorted = candidates.sorted {
            isRTL ? $0.frame.maxX > $1.frame.maxX : $0.frame.minX < $1.frame.minX
        }
        guard let button = sorted.first else { return nil }
        return center(of: button)
    }

    private static func center(of button: UIView) -> CGPoint {
        if let image = preferredImageView(in: button) {
            return image.convert(CGPoint(x: image.bounds.midX, y: image.bounds.midY), to: nil)
        }
        return button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    }

    private static func buttonMatchesTitle(_ button: UIView, title: String) -> Bool {
        guard !title.isEmpty else { return false }
        if let label = button.accessibilityLabel, label.localizedCaseInsensitiveContains(title) {
            return true
        }
        for label in descendantLabels(in: button) {
            if label.text?.localizedCaseInsensitiveContains(title) == true {
                return true
            }
        }
        return false
    }

    private static func buttonContainsSystemImageHint(_ button: UIView, hint: String) -> Bool {
        for imageView in descendants(of: button).compactMap({ $0 as? UIImageView }) {
            let description = String(describing: imageView.image)
            if description.localizedCaseInsensitiveContains(hint) {
                return true
            }
        }
        return false
    }

    private static func tabBarButtons(in tabBar: UITabBar) -> [UIView] {
        descendants(of: tabBar).filter { view in
            let name = String(describing: type(of: view))
            return name.contains("TabBarButton") || name.contains("UITabBarButton")
        }
    }

    private static func preferredImageView(in root: UIView) -> UIImageView? {
        let images = descendants(of: root).compactMap { $0 as? UIImageView }
        return images
            .filter { $0.bounds.width >= 8 && $0.bounds.height >= 8 && !$0.isHidden && $0.alpha > 0.01 }
            .sorted { ($0.bounds.width * $0.bounds.height) > ($1.bounds.width * $1.bounds.height) }
            .first
    }

    private static func descendantLabels(in root: UIView) -> [UILabel] {
        descendants(of: root).compactMap { $0 as? UILabel }
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for subview in view.subviews {
            if let tabBar = findTabBar(in: subview) { return tabBar }
        }
        return nil
    }

    private static func descendants(of root: UIView) -> [UIView] {
        var result: [UIView] = []
        var stack = root.subviews
        while let view = stack.popLast() {
            result.append(view)
            stack.append(contentsOf: view.subviews)
        }
        return result
    }
}

/// Item name dives into the List tab icon, then a short +1 bubble rises and fades.
struct FirstAddToListDiveOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.appTheme) private var appTheme

    let itemName: String
    let sourceFrame: CGRect
    let targetPoint: CGPoint
    /// Fired when the +1 bubble finishes (reveal List tab badge).
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
