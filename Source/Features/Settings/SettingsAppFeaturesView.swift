import SwiftUI
import UIKit

struct SettingsAppFeaturesView: View {
    private var groupedSections: [(AppFeatureSectionKind, [AppFeatureCatalogEntry])] {
        AppFeatureCatalogEntry.groupedSections()
    }

    var body: some View {
        List {
            ForEach(groupedSections, id: \.0) { section, features in
                Section(section.title) {
                    ForEach(features) { feature in
                        AppFeatureRow(feature: feature)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(LocalizedCopy.appFeatures)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppFeatureRow: View {
    let feature: AppFeatureCatalogEntry

    private static let iconColumnWidth: CGFloat = 42

    private var iconFont: Font {
        let pointSize = UIFont.preferredFont(forTextStyle: .body).pointSize * 1.5
        return .system(size: pointSize)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(iconFont)
                .foregroundStyle(.secondary)
                .frame(width: Self.iconColumnWidth, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                AppFeatureText.make(feature.title)
                AppFeatureText.make(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .catalogListRowSeparatorFullWidth(true)
        .accessibilityElement(children: .combine)
    }
}

/// Tips text with `{plus}` markers drawn as the + button's own symbol (plus.circle), inline.
private enum AppFeatureText {
    static let plusMarker = "{plus}"

    static func make(_ string: String) -> Text {
        let parts = string.components(separatedBy: plusMarker)
        var text = Text(parts[0])
        for part in parts.dropFirst() {
            text = text + Text(Image(systemName: "plus.circle")) + Text(part)
        }
        return text
    }
}
