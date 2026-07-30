import SwiftUI
import UIKit

private enum StoreToolbarGlyph {
    static let font = Font.system(size: 15, weight: .semibold)
}

/// Menu icons painted with `.alwaysOriginal` so Store’s `.tint(.primary)` cannot keep
/// disabled glyphs label-colored (or keep Clear List red while the row is disabled).
private enum StoreEllipsisMenuSymbol {
    static func image(systemName: String, enabled: Bool, destructive: Bool = false) -> UIImage {
        let color: UIColor
        if !enabled {
            color = .tertiaryLabel
        } else if destructive {
            color = .systemRed
        } else {
            color = .label
        }
        let image = UIImage(systemName: systemName) ?? UIImage()
        return image.withTintColor(color, renderingMode: .alwaysOriginal)
    }
}

/// Store tab leading toolbar control — opens Settings.
struct StoreSettingsToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(LocalizedCopy.settings, systemImage: "gear")
                .labelStyle(.iconOnly)
                .font(StoreToolbarGlyph.font)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .catalogToolbarCircularTapTarget()
        .accessibilityLabel(LocalizedCopy.settings)
    }
}

/// Store tab trailing ⋯ menu (store sections, clear checked, clear list, share, save as recipe).
struct StoreTabEllipsisMenu: View {
    @EnvironmentObject private var store: GroceryStore

    let canShareShoppingList: Bool
    let hasCheckedLines: Bool
    let hasVisibleLines: Bool
    let hasUncheckedLines: Bool
    @Binding var isPresentingClearAllConfirm: Bool
    let onManageStoreSections: () -> Void
    let onShare: () -> Void
    let onSaveAsRecipe: () -> Void
    let onClearChecked: () -> Void

    private var canClearChecked: Bool {
        hasVisibleLines && hasCheckedLines
    }

    var body: some View {
        Menu {
            Section {
                Button(action: onManageStoreSections) {
                    Label(LocalizedCopy.storeSections, systemImage: "storefront.fill")
                }
            }

            Section {
                if store.canUndoClearChecked {
                    Button {
                        withAnimation(.snappy) {
                            store.undoClearChecked()
                        }
                    } label: {
                        Label(LocalizedCopy.undoClearChecked, systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button(action: onClearChecked) {
                        ellipsisLabel(
                            LocalizedCopy.clearChecked,
                            systemName: "xmark.app",
                            enabled: canClearChecked
                        )
                    }
                    .disabled(!canClearChecked)
                }

                if store.canUndoClearShoppingList {
                    Button {
                        withAnimation(.snappy) {
                            store.undoClearShoppingList()
                        }
                    } label: {
                        Label(LocalizedCopy.undoClearList, systemImage: "arrow.uturn.backward")
                    }
                } else {
                    // Store NavigationStack uses `.tint(.primary)`, which keeps Menu SF Symbols
                    // label-colored even with `role: .destructive`. Paint the trash glyph red
                    // when enabled; tertiary grey when the row is disabled.
                    Button(role: .destructive) {
                        isPresentingClearAllConfirm = true
                    } label: {
                        ellipsisLabel(
                            LocalizedCopy.clearList,
                            systemName: "trash",
                            enabled: hasVisibleLines,
                            destructive: true
                        )
                    }
                    .disabled(!hasVisibleLines)
                }

                Button(action: onShare) {
                    ellipsisLabel(
                        LocalizedCopy.shareList,
                        systemName: "square.and.arrow.up",
                        enabled: canShareShoppingList
                    )
                }
                .disabled(!canShareShoppingList)

                Button(action: onSaveAsRecipe) {
                    ellipsisLabel(
                        LocalizedCopy.saveList,
                        systemName: "square.and.arrow.down",
                        enabled: hasUncheckedLines
                    )
                }
                .disabled(!hasUncheckedLines)
            }
        } label: {
            Label(LocalizedCopy.menu, systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(StoreToolbarGlyph.font)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .catalogToolbarCircularTapTarget()
        .accessibilityLabel(LocalizedCopy.menu)
    }

    private func ellipsisLabel(
        _ title: String,
        systemName: String,
        enabled: Bool,
        destructive: Bool = false
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(uiImage: StoreEllipsisMenuSymbol.image(
                systemName: systemName,
                enabled: enabled,
                destructive: destructive
            ))
        }
    }
}
