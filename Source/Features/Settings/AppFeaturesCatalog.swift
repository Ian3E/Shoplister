import SwiftUI

enum AppFeatureSectionKind: String, CaseIterable {
    case shoppingList
    case itemLibrary
    case savedLists
    case personalization
    case dataSharing

    var title: String {
        switch self {
        case .shoppingList:
            return LocalizedCopy.appFeaturesShoppingListSection
        case .itemLibrary:
            return LocalizedCopy.appFeaturesItemLibrarySection
        case .savedLists:
            return LocalizedCopy.appFeaturesSavedListsSection
        case .personalization:
            return LocalizedCopy.appFeaturesPersonalizationSection
        case .dataSharing:
            return LocalizedCopy.appFeaturesDataSharingSection
        }
    }
}

struct AppFeatureCatalogEntry: Identifiable {
    let id: String
    let section: AppFeatureSectionKind
    let systemImage: String
    let title: String
    let description: String

    static func orderedEntries() -> [AppFeatureCatalogEntry] {
        [
            AppFeatureCatalogEntry(
                id: "storeSections",
                section: .shoppingList,
                systemImage: "storefront.fill",
                title: LocalizedCopy.appFeatureStoreSectionsTitle,
                description: LocalizedCopy.appFeatureStoreSectionsDescription
            ),
            AppFeatureCatalogEntry(
                id: "checkOff",
                section: .shoppingList,
                systemImage: "checkmark.app",
                title: LocalizedCopy.appFeatureCheckOffTitle,
                description: LocalizedCopy.appFeatureCheckOffDescription
            ),
            AppFeatureCatalogEntry(
                id: "longPress",
                section: .shoppingList,
                systemImage: "hand.tap.fill",
                title: LocalizedCopy.appFeatureLongPressTitle,
                description: LocalizedCopy.appFeatureLongPressDescription
            ),
            AppFeatureCatalogEntry(
                id: "pullDownToAdd",
                section: .shoppingList,
                systemImage: "arrow.down.circle.fill",
                title: LocalizedCopy.appFeaturePullDownToAddTitle,
                description: LocalizedCopy.appFeaturePullDownToAddDescription
            ),
            AppFeatureCatalogEntry(
                id: "plusMenu",
                section: .shoppingList,
                systemImage: "plus.circle.fill",
                title: LocalizedCopy.appFeaturePlusMenuTitle,
                description: LocalizedCopy.appFeaturePlusMenuDescription
            ),
            AppFeatureCatalogEntry(
                id: "pullUpClearChecked",
                section: .shoppingList,
                systemImage: "arrow.up.circle.fill",
                title: LocalizedCopy.appFeaturePullUpClearCheckedTitle,
                description: LocalizedCopy.appFeaturePullUpClearCheckedDescription
            ),
            AppFeatureCatalogEntry(
                id: "clearWhenDone",
                section: .shoppingList,
                systemImage: "checklist.checked",
                title: LocalizedCopy.appFeatureClearWhenDoneTitle,
                description: LocalizedCopy.appFeatureClearWhenDoneDescription
            ),
            AppFeatureCatalogEntry(
                id: "pinchSections",
                section: .shoppingList,
                systemImage: "arrow.up.left.and.arrow.down.right",
                title: LocalizedCopy.appFeaturePinchSectionsTitle,
                description: LocalizedCopy.appFeaturePinchSectionsDescription
            ),
            AppFeatureCatalogEntry(
                id: "shakeUndo",
                section: .shoppingList,
                systemImage: "arrow.uturn.backward.circle",
                title: LocalizedCopy.appFeatureShakeUndoTitle,
                description: LocalizedCopy.appFeatureShakeUndoDescription
            ),
            AppFeatureCatalogEntry(
                id: "shareList",
                section: .shoppingList,
                systemImage: "square.and.arrow.up",
                title: LocalizedCopy.shareList,
                description: LocalizedCopy.appFeatureShareListDescription
            ),
            AppFeatureCatalogEntry(
                id: "sortChecked",
                section: .shoppingList,
                systemImage: "arrow.up.arrow.down",
                title: LocalizedCopy.sortCheckedItems,
                description: LocalizedCopy.appFeatureSortCheckedDescription
            ),
            AppFeatureCatalogEntry(
                id: "hideSectionNames",
                section: .shoppingList,
                systemImage: "rectangle.compress.vertical",
                title: LocalizedCopy.hideSectionNames,
                description: LocalizedCopy.appFeatureHideSectionNamesDescription
            ),
            AppFeatureCatalogEntry(
                id: "shortcutToAllItems",
                section: .shoppingList,
                systemImage: "square.grid.2x2",
                title: LocalizedCopy.shortcutToAllItems,
                description: LocalizedCopy.appFeatureShortcutToAllItemsDescription
            ),
            AppFeatureCatalogEntry(
                id: "homeSections",
                section: .itemLibrary,
                systemImage: "house.fill",
                title: LocalizedCopy.appFeatureHomeSectionsTitle,
                description: LocalizedCopy.appFeatureHomeSectionsDescription
            ),
            AppFeatureCatalogEntry(
                id: "itemPhotos",
                section: .itemLibrary,
                systemImage: "photo.fill",
                title: LocalizedCopy.appFeatureItemPhotosTitle,
                description: LocalizedCopy.appFeatureItemPhotosDescription
            ),
            AppFeatureCatalogEntry(
                id: "searchOrCreate",
                section: .itemLibrary,
                systemImage: "magnifyingglass",
                title: LocalizedCopy.appFeatureSearchOrCreateTitle,
                description: LocalizedCopy.appFeatureSearchOrCreateDescription
            ),
            AppFeatureCatalogEntry(
                id: "edit",
                section: .itemLibrary,
                systemImage: "pencil",
                title: LocalizedCopy.appFeatureEditTitle,
                description: LocalizedCopy.appFeatureEditDescription
            ),
            AppFeatureCatalogEntry(
                id: "saveList",
                section: .savedLists,
                systemImage: "square.and.arrow.down",
                title: LocalizedCopy.saveList,
                description: LocalizedCopy.appFeatureSaveListDescription
            ),
            AppFeatureCatalogEntry(
                id: "addSavedList",
                section: .savedLists,
                systemImage: "text.badge.plus",
                title: LocalizedCopy.appFeatureAddSavedListTitle,
                description: LocalizedCopy.appFeatureAddSavedListDescription
            ),
            AppFeatureCatalogEntry(
                id: "theme",
                section: .personalization,
                systemImage: "paintpalette.fill",
                title: LocalizedCopy.appFeatureThemeTitle,
                description: LocalizedCopy.appFeatureThemeDescription
            ),
            AppFeatureCatalogEntry(
                id: "appearanceTextSize",
                section: .personalization,
                systemImage: "textformat.size",
                title: LocalizedCopy.appFeatureAppearanceTextSizeTitle,
                description: LocalizedCopy.appFeatureAppearanceTextSizeDescription
            ),
            AppFeatureCatalogEntry(
                id: "listTabBadge",
                section: .personalization,
                systemImage: "checklist",
                title: LocalizedCopy.listTabBadge,
                description: LocalizedCopy.appFeatureListTabBadgeDescription
            ),
            AppFeatureCatalogEntry(
                id: "appIconBadge",
                section: .personalization,
                systemImage: "app.badge.fill",
                title: LocalizedCopy.appIconBadge,
                description: LocalizedCopy.appFeatureAppIconBadgeDescription
            ),
            AppFeatureCatalogEntry(
                id: "deviceOptions",
                section: .personalization,
                systemImage: "iphone.gen3",
                title: LocalizedCopy.appFeatureDeviceOptionsTitle,
                description: LocalizedCopy.appFeatureDeviceOptionsDescription
            ),
            AppFeatureCatalogEntry(
                id: "iCloudSync",
                section: .dataSharing,
                systemImage: "icloud.fill",
                title: LocalizedCopy.iCloudSync,
                description: LocalizedCopy.appFeatureICloudSyncDescription
            ),
            AppFeatureCatalogEntry(
                id: "sharedHousehold",
                section: .dataSharing,
                systemImage: "person.2.fill",
                title: LocalizedCopy.appFeatureSharedHouseholdTitle,
                description: LocalizedCopy.appFeatureSharedHouseholdDescription
            ),
            AppFeatureCatalogEntry(
                id: "libraryLanguage",
                section: .dataSharing,
                systemImage: "globe",
                title: LocalizedCopy.libraryLanguage,
                description: LocalizedCopy.appFeatureLibraryLanguageDescription
            ),
            AppFeatureCatalogEntry(
                id: "backup",
                section: .dataSharing,
                systemImage: "doc.on.doc.fill",
                title: LocalizedCopy.appFeatureBackupTitle,
                description: LocalizedCopy.appFeatureBackupDescription
            ),
            AppFeatureCatalogEntry(
                id: "shareFromApps",
                section: .dataSharing,
                systemImage: "arrow.up.forward.app.fill",
                title: LocalizedCopy.appFeatureShareFromAppsTitle,
                description: LocalizedCopy.appFeatureShareFromAppsDescription
            ),
            AppFeatureCatalogEntry(
                id: "shortcutsImport",
                section: .dataSharing,
                systemImage: "bolt.fill",
                title: LocalizedCopy.appFeatureShortcutsImportTitle,
                description: LocalizedCopy.appFeatureShortcutsImportDescription
            ),
        ]
    }

    static func groupedSections() -> [(AppFeatureSectionKind, [AppFeatureCatalogEntry])] {
        let entries = orderedEntries()
        return AppFeatureSectionKind.allCases.compactMap { section in
            let sectionEntries = entries.filter { $0.section == section }
            guard !sectionEntries.isEmpty else { return nil }
            return (section, sectionEntries)
        }
    }
}
