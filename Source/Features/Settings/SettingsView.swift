import SwiftUI
import UIKit

private enum SettingsRoute: Hashable {
    case shoppingList
    case itemLibrary
    case appearance
    case device
    case about
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var draftTextSizeRaw: String
    @Binding var draftThemeRaw: String
    @Binding var draftCustomColorHex: String
    var onClose: (() -> Void)? = nil

    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String = AppAppearance.system.rawValue
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    settingsLink(.shoppingList, title: LocalizedCopy.shoppingListSectionTitle, systemImage: "checklist")
                    settingsLink(.itemLibrary, title: LocalizedCopy.settingsItemLibrary, systemImage: "square.grid.2x2.fill")
                    settingsLink(.appearance, title: LocalizedCopy.appearance, systemImage: "paintbrush.fill")
                    settingsLink(.device, title: LocalizedCopy.device, systemImage: "iphone")
                    settingsLink(.about, title: LocalizedCopy.settingsAbout, systemImage: "info.circle.fill")
                }
            }
            .navigationTitle(LocalizedCopy.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedCopy.done) { closeSettings() }
                        .labelStyle(.titleOnly)
                        .font(.body.weight(.semibold))
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
        }
        .preferredColorScheme(SettingsAppearanceResolver.colorScheme(for: appearance, fallback: colorScheme))
    }

    @ViewBuilder
    private func settingsLink(_ route: SettingsRoute, title: String, systemImage: String) -> some View {
        NavigationLink(value: route) {
            SettingsRootRowLabel(title: title, systemImage: systemImage, route: route)
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .shoppingList:
            SettingsGeneralView()
        case .itemLibrary:
            SettingsItemLibraryView()
        case .appearance:
            SettingsAppearanceDetailView(
                draftTextSizeRaw: $draftTextSizeRaw,
                draftThemeRaw: $draftThemeRaw,
                draftCustomColorHex: $draftCustomColorHex
            )
        case .device:
            SettingsDeviceView()
        case .about:
            SettingsAboutView()
        }
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private func closeSettings() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

private enum SettingsRootRowIconMetrics {
    static let tileSize: CGFloat = 30
    static let tileCornerRadius: CGFloat = 8
}

private extension SettingsRoute {
    var iconTileGradient: LinearGradient {
        let colors: (top: Color, bottom: Color) = switch self {
        case .shoppingList, .itemLibrary:
            (
                Color(red: 0.38, green: 0.68, blue: 1.00),
                Color(red: 0.00, green: 0.41, blue: 0.94)
            )
        case .appearance:
            (
                Color(red: 1.00, green: 0.70, blue: 0.22),
                Color(red: 0.95, green: 0.50, blue: 0.00)
            )
        case .device:
            (
                Color(red: 0.38, green: 0.86, blue: 0.48),
                Color(red: 0.16, green: 0.70, blue: 0.30)
            )
        case .about:
            (
                Color(red: 0.68, green: 0.68, blue: 0.70),
                Color(red: 0.48, green: 0.48, blue: 0.50)
            )
        }
        return LinearGradient(
            colors: [colors.top, colors.bottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct SettingsRootRowLabel: View {
    let title: String
    let systemImage: String
    let route: SettingsRoute

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.subheadline)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .frame(
                    width: SettingsRootRowIconMetrics.tileSize,
                    height: SettingsRootRowIconMetrics.tileSize
                )
                .background {
                    RoundedRectangle(
                        cornerRadius: SettingsRootRowIconMetrics.tileCornerRadius,
                        style: .continuous
                    )
                    .fill(route.iconTileGradient)
                }
        }
    }
}

/// Resolves appearance for Settings sheets; System must not use `preferredColorScheme(nil)`.
private enum SettingsAppearanceResolver {
    static func colorScheme(for appearance: AppAppearance, fallback: ColorScheme) -> ColorScheme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemColorScheme(fallback: fallback)
        }
    }

    private static func systemColorScheme(fallback: ColorScheme) -> ColorScheme {
        let style: UIUserInterfaceStyle
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: \.isKeyWindow)
        {
            style = window.traitCollection.userInterfaceStyle
        } else {
            style = UITraitCollection.current.userInterfaceStyle
        }
        switch style {
        case .dark: return .dark
        case .light, .unspecified: return .light
        @unknown default: return fallback
        }
    }
}
