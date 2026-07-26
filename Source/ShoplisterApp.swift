import SwiftUI
import UIKit

/// Orientation preference persisted in `UserDefaults` via `@AppStorage`.
enum AppOrientationLock {
    static let lockPortraitStorageKey = "app.lockPortrait"
}

enum OrientationLock {
    static func currentMask() -> UIInterfaceOrientationMask {
        let locked = UserDefaults.standard.object(forKey: AppOrientationLock.lockPortraitStorageKey) as? Bool ?? true
        if locked { return .portrait }
        return [.portrait, .landscapeLeft, .landscapeRight]
    }

    static func applyCurrentSetting() {
        let mask = currentMask()

        // Best-effort: update the active scene's geometry so rotations behave immediately.
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            scene.requestGeometryUpdate(prefs) { _ in }
        }

        // Tell the visible controller hierarchy to re-query supported orientations.
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        {
            root.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

/// Matches `LaunchScreen.storyboard` / App Icon blue so home-gesture minimize
/// composites brand color instead of system white behind the shrinking snapshot.
enum AppIconBackdrop {
    static let uiColor = UIColor(
        red: 0.16145926713943481,
        green: 0.45925337076187134,
        blue: 0.93589794635772705,
        alpha: 1
    )

    static var color: Color { Color(uiColor: uiColor) }

    static func applyToWindows() {
        UIWindow.appearance().backgroundColor = uiColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.backgroundColor = uiColor
            }
        }
    }
}

private final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UserDefaults.standard.register(defaults: [
            AppShoppingBadgeUnchecked.storageKey: false,
            AppShoppingConfirmClearWhenAllChecked.storageKey: true,
            AppContentLanguage.storageKey: AppSystemLocale.firstLaunchCatalogLanguageDefault,
        ])
        // Before the first window mounts so new windows inherit icon blue.
        UIWindow.appearance().backgroundColor = AppIconBackdrop.uiColor
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.currentMask()
    }
}

@main
struct ShoplisterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = GroceryStore()
    @StateObject private var fullWindowOverlay = FullWindowOverlayCoordinator()
    @AppStorage(AppTextSize.storageKey) private var textSizeRaw: String = AppTextSize.defaultSize.rawValue
    @AppStorage(AppContentLanguage.storageKey) private var catalogLanguageRaw: String = AppSystemLocale.firstLaunchCatalogLanguageDefault
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(AppTheme.storageKey) private var themeRaw: String = AppTheme.blue.rawValue
    @AppStorage(AppTheme.customColorStorageKey) private var customColorHex: String = AppTheme.defaultCustomColorHex
    @AppStorage(AppAutoLock.disableAutoLockStorageKey) private var disableAutoLock: Bool = false
    @AppStorage(AppShoppingBadgeUnchecked.storageKey) private var showUncheckedCountAppBadge: Bool = false

    var body: some Scene {
        WindowGroup {
            rootContent
                .environmentObject(store)
                .environmentObject(fullWindowOverlay)
                .environment(\.appContentLanguage, catalogLanguage)
                .onAppear {
                    AppIconBackdrop.applyToWindows()
                    AppAutoLock.applyFromUserDefaults()
                    AppTextSize.migrateStoredRawValueIfNeeded(&textSizeRaw)
                    store.mergeShareExtensionShoppingOpsIfNeeded()
                    syncShoppingIconBadge()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    store.mergeShareExtensionShoppingOpsIfNeeded()
                    syncShoppingIconBadge()
                }
                .onReceive(NotificationCenter.default.publisher(for: .shareExtensionPendingShoppingOpsEnqueued)) { _ in
                    store.mergeShareExtensionShoppingOpsIfNeeded()
                    syncShoppingIconBadge()
                }
                .onChange(of: disableAutoLock) { _, _ in
                    AppAutoLock.applyFromUserDefaults()
                }
                .onChange(of: catalogLanguageRaw) { _, _ in
                    store.applyContentLanguageFromUserDefaults()
                }
                .onChange(of: showUncheckedCountAppBadge) { _, _ in
                    syncShoppingIconBadge()
                }
                .onChange(of: store.shopping) { _, _ in
                    syncShoppingIconBadge()
                }
                .onChange(of: store.catalog) { _, _ in
                    syncShoppingIconBadge()
                }
        }
    }

    private func syncShoppingIconBadge() {
        ShoppingIconBadge.sync(enabled: showUncheckedCountAppBadge, store: store)
    }

    private var catalogLanguage: AppContentLanguage {
        AppContentLanguage(rawValue: catalogLanguageRaw) ?? .english
    }

    @ViewBuilder
    private var rootContent: some View {
        let size = AppTextSize.resolved(from: textSizeRaw)
        let appearance = AppAppearance(rawValue: appearanceRaw) ?? .system
        let theme = AppThemeSelection(presetRaw: themeRaw, customColorHex: customColorHex)
        ContentView()
            .environment(\.appTheme, theme)
            .environment(\.layoutDirection, AppSystemLocale.interfaceLayoutDirection)
            // Chrome (toolbars, dialogs, tab bar): fixed medium. Home/Store **item names** opt in via list `dynamicTypeSize`.
            .dynamicTypeSize(AppTextSize.defaultSize.dynamicTypeSize)
            .environment(\.shoppingListSpacingScale, size.listSpacingScale)
            .animation(AppTextSize.layoutCommitAnimation, value: textSizeRaw)
            .preferredColorScheme(appearance.colorSchemeOverride)
            // Behind opaque list chrome; shows during home-gesture morph instead of system white.
            .background(AppIconBackdrop.color.ignoresSafeArea())
    }
}
