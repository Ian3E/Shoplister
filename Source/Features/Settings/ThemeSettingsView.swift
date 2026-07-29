import SwiftUI

/// Theme picker with a live Store-list preview showing themed chrome.
struct ThemeSettingsView: View {
    @Binding var draftThemeRaw: String
    @Binding var draftCustomColorHex: String

    private var draftTheme: AppTheme {
        AppTheme(rawValue: draftThemeRaw) ?? .blue
    }

    private var draftThemeSelection: AppThemeSelection {
        AppThemeSelection(presetRaw: draftThemeRaw, customColorHex: draftCustomColorHex)
    }

    private var draftCustomColor: Binding<Color> {
        Binding(
            get: {
                Color(hex: draftCustomColorHex) ?? AppTheme.blue.builtinColor
            },
            set: { newColor in
                draftThemeRaw = AppTheme.custom.rawValue
                draftCustomColorHex = newColor.hexString
            }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                List {
                    Section {
                        themeColorPicker
                            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                // Swatch row is app chrome — follow phone language, not library language.
                .environment(\.layoutDirection, AppSystemLocale.interfaceLayoutDirection)
                .frame(height: Self.colorPickerSectionHeight)

                previewHeader

                themeStoreListPreview
                    .frame(
                        width: geometry.size.width,
                        height: max(
                            0,
                            geometry.size.height
                                - Self.colorPickerSectionHeight
                                - Self.previewHeaderHeight
                        )
                    )
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(Color.shoppingListBackground)
        }
        .background(Color.shoppingListBackground)
        .navigationTitle(LocalizedCopy.theme)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewHeader: some View {
        Text(LocalizedCopy.preview)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color(uiColor: .label))
            .frame(maxWidth: .infinity)
            .textCase(nil)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .frame(height: Self.previewHeaderHeight, alignment: .top)
    }

    private var themeColorPicker: some View {
        HStack(spacing: 12) {
            ForEach(AppTheme.presetCases) { option in
                Button {
                    draftThemeRaw = option.rawValue
                } label: {
                    Circle()
                        .fill(option.builtinColor)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if draftTheme == option {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(draftTheme == option ? .isSelected : [])
            }

            ColorPicker("", selection: draftCustomColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .simultaneousGesture(TapGesture().onEnded {
                    draftThemeRaw = AppTheme.custom.rawValue
                })
                .overlay {
                    if draftTheme == .custom {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(LocalizedCopy.customColor)
                .accessibilityAddTraits(draftTheme == .custom ? .isSelected : [])
        }
        .frame(maxWidth: .infinity)
    }

    /// Swatch row: 16 + 28 + 16 vertical insets.
    private static let colorPickerSectionHeight: CGFloat = 60
    /// Matches prior preview section header spacing.
    private static let previewHeaderHeight: CGFloat = 40
    /// Trailing inset for the preview bottom-bar + button.
    private static let themePreviewTrailingToolbarInset: CGFloat = 20
    /// Bottom inset within the preview pane — mirrors Store `bottomBar` placement.
    private static let themePreviewBottomToolbarInset: CGFloat = 10
    /// Nudge the preview + down to align with the live Store bottom toolbar.
    private static let themePreviewBottomToolbarOffset: CGFloat = 20

    private var themeStoreListPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.shoppingListBackground

            VStack(spacing: 0) {
                SettingsStoreListPreview(textSize: .medium)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            SettingsThemePreviewAddButton()
                .padding(.trailing, Self.themePreviewTrailingToolbarInset)
                .padding(.bottom, Self.themePreviewBottomToolbarInset)
                .offset(y: Self.themePreviewBottomToolbarOffset)
        }
        .environment(\.appTheme, draftThemeSelection)
        .allowsHitTesting(false)
    }
}

/// Clear-glass "+" for the theme preview — mirrors the Store side-tab add control
/// (separated Liquid Glass circle + theme-colored symbol).
private struct SettingsThemePreviewAddButton: View {
    @Environment(\.appTheme) private var appTheme

    private static let buttonDiameter = CatalogToolbarTapChrome.iconTapDiameter + 10
    private static let symbolPointSize: CGFloat = 21

    var body: some View {
        Button(action: {}) {
            Image(systemName: "plus")
                .font(.system(size: Self.symbolPointSize, weight: .semibold))
                .foregroundStyle(appTheme.color)
                .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(LocalizedCopy.addItem)
        .allowsHitTesting(false)
    }
}
