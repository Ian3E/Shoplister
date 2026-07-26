import SwiftUI
import UIKit
import MessageUI
import UniformTypeIdentifiers

// MARK: - Shopping list

struct SettingsGeneralView: View {
    @AppStorage(AppShoppingSortChecked.storageKey) private var sortCheckedShoppingItems: Bool = false
    @AppStorage(AppShoppingCollapseCompletedSections.storageKey) private var collapseCompletedSections: Bool = false
    @AppStorage(AppShoppingHideStoreGroupNames.storageKey) private var hideStoreGroupNames: Bool = false
    @AppStorage(AppShoppingConfirmClearWhenAllChecked.storageKey) private var confirmClearWhenAllChecked: Bool = true
    @AppStorage(AppLibraryAutoExpandQuantityPicker.storageKey) private var autoExpandQuantityPicker: Bool = true
    @AppStorage(AppListTabBadge.storageKey) private var showListTabBadge: Bool = true
    @AppStorage(AppShoppingBadgeUnchecked.storageKey) private var showUncheckedCountAppBadge: Bool = false

    var body: some View {
        List {
            Section {
                Toggle(LocalizedCopy.sortCheckedItems, isOn: $sortCheckedShoppingItems)
            } footer: {
                Text(LocalizedCopy.sortCheckedItemsFooter)
            }

            Section {
                Toggle(LocalizedCopy.collapseCompletedSections, isOn: $collapseCompletedSections)
            } footer: {
                Text(LocalizedCopy.collapseCompletedSectionsFooter)
            }

            Section {
                Toggle(LocalizedCopy.hideSectionNames, isOn: $hideStoreGroupNames)
            } footer: {
                Text(LocalizedCopy.hideSectionNamesFooter)
            }

            Section {
                Toggle(LocalizedCopy.confirmBeforeClearingList, isOn: $confirmClearWhenAllChecked)
            } footer: {
                Text(LocalizedCopy.confirmBeforeClearingListFooter)
            }

            Section {
                Toggle(LocalizedCopy.autoExpandQuantityPicker, isOn: $autoExpandQuantityPicker)
            } footer: {
                Text(LocalizedCopy.autoExpandQuantityPickerFooter)
            }

            Section {
                Toggle(LocalizedCopy.listTabBadge, isOn: $showListTabBadge)
            } footer: {
                Text(LocalizedCopy.listTabBadgeFooter)
            }

            Section {
                Toggle(LocalizedCopy.appIconBadge, isOn: $showUncheckedCountAppBadge)
            } footer: {
                Text(LocalizedCopy.appIconBadgeFooter)
            }
        }
        .navigationTitle(LocalizedCopy.shoppingListSectionTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Item library

struct SettingsItemLibraryView: View {
    @EnvironmentObject private var store: GroceryStore

    @AppStorage(AppContentLanguage.storageKey) private var catalogLanguageRaw: String = AppContentLanguage.english.rawValue

    @State private var pendingCatalogLanguageRaw: String?
    @State private var catalogLanguagePickerValue: String = AppContentLanguage.english.rawValue
    @State private var sharePayload: SettingsSharePayload?
    @State private var isPickingImportFile = false
    @State private var pendingImportURL: URL?
    @State private var isPresentingImportReplaceConfirm = false
    @State private var isPresentingExportConfirm = false
    @State private var isPresentingClearLibraryConfirm = false
    @State private var backupErrorMessage: String?
    @State private var backupSuccessMessage: String?

    var body: some View {
        List {
            Section {
                Picker(LocalizedCopy.libraryLanguage, selection: $catalogLanguagePickerValue) {
                    ForEach(AppContentLanguage.allCases) { option in
                        Text(option.title)
                            .tag(option.rawValue)
                            .contentTransition(.identity)
                    }
                }
                .onChange(of: catalogLanguagePickerValue) { _, newValue in
                    if newValue == catalogLanguageRaw {
                        pendingCatalogLanguageRaw = nil
                        return
                    }
                    pendingCatalogLanguageRaw = newValue
                }
            } footer: {
                Text(LocalizedCopy.libraryLanguageFooter)
            }

            Section(LocalizedCopy.backup) {
                Button(LocalizedCopy.export) { isPresentingExportConfirm = true }
                Button(LocalizedCopy.importAction) { isPickingImportFile = true }
            }

            Section {
                Button(LocalizedCopy.clearLibrary, role: .destructive) {
                    isPresentingClearLibraryConfirm = true
                }
            } footer: {
                Text(LocalizedCopy.clearLibraryFooter)
            }
        }
        .navigationTitle(LocalizedCopy.settingsItemLibrary)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { catalogLanguagePickerValue = catalogLanguageRaw }
        .onChange(of: catalogLanguageRaw) { _, newValue in
            catalogLanguagePickerValue = newValue
        }
        .modifier(SettingsItemLibraryAlertsModifier(
            pendingCatalogLanguageRaw: $pendingCatalogLanguageRaw,
            catalogLanguagePickerValue: $catalogLanguagePickerValue,
            catalogLanguageRaw: $catalogLanguageRaw,
            isPresentingExportConfirm: $isPresentingExportConfirm,
            isPresentingImportReplaceConfirm: $isPresentingImportReplaceConfirm,
            isPresentingClearLibraryConfirm: $isPresentingClearLibraryConfirm,
            backupErrorMessage: $backupErrorMessage,
            backupSuccessMessage: $backupSuccessMessage,
            pendingImportURL: $pendingImportURL,
            onExport: exportLibraryBackup,
            onImport: runPendingImport,
            onClearLibrary: { store.clearLibrary(for: catalogLanguage) },
            store: store
        ))
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: [payload.url])
        }
        .fileImporter(
            isPresented: $isPickingImportFile,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false,
            onCompletion: handleImportFilePickerResult
        )
    }

    private var catalogLanguage: AppContentLanguage {
        AppContentLanguage(rawValue: catalogLanguageRaw) ?? .english
    }

    private func handleImportFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shoplister-import-pending-\(UUID().uuidString).zip")
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                pendingImportURL = dest
                isPresentingImportReplaceConfirm = true
            } catch {
                backupErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            backupErrorMessage = error.localizedDescription
        }
    }

    private func exportLibraryBackup() {
        do {
            let url = try store.exportLibraryBackup(for: catalogLanguage)
            sharePayload = SettingsSharePayload(url: url)
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func runPendingImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let skippedRecipeRows = try store.importLibraryBackup(from: url, into: catalogLanguage)
            if skippedRecipeRows > 0 {
                backupSuccessMessage = LocalizedCopy.importSuccessMessage
                    + "\n"
                    + LocalizedCopy.backupSkippedRecipeRows(skippedRecipeRows)
            } else {
                backupSuccessMessage = LocalizedCopy.importSuccessMessage
            }
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - Appearance

struct SettingsAppearanceDetailView: View {
    @Binding var draftTextSizeRaw: String
    @Binding var draftThemeRaw: String
    @Binding var draftCustomColorHex: String

    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String = AppAppearance.system.rawValue

    private var draftThemeSelection: AppThemeSelection {
        AppThemeSelection(presetRaw: draftThemeRaw, customColorHex: draftCustomColorHex)
    }

    private var themeSummary: String {
        draftThemeSelection.title
    }

    private var textSizeSummary: String {
        AppTextSize.resolved(from: draftTextSizeRaw).title
    }

    var body: some View {
        List {
            Section {
                Picker(LocalizedCopy.appearance, selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                NavigationLink {
                    ThemeSettingsView(
                        draftThemeRaw: $draftThemeRaw,
                        draftCustomColorHex: $draftCustomColorHex
                    )
                } label: {
                    LabeledContent(LocalizedCopy.theme, value: themeSummary)
                }

                NavigationLink {
                    TextSizeSettingsView(
                        draftTextSizeRaw: $draftTextSizeRaw,
                        draftThemeRaw: $draftThemeRaw,
                        draftCustomColorHex: $draftCustomColorHex
                    )
                } label: {
                    LabeledContent(LocalizedCopy.textSize, value: textSizeSummary)
                }
            }
        }
        .navigationTitle(LocalizedCopy.appearance)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Device

struct SettingsDeviceView: View {
    @AppStorage(AppOrientationLock.lockPortraitStorageKey) private var lockPortrait: Bool = true
    @AppStorage(AppHaptics.storageKey) private var hapticsEnabled: Bool = true
    @AppStorage(AppAutoLock.disableAutoLockStorageKey) private var disableAutoLock: Bool = false

    var body: some View {
        List {
            Section {
                Toggle(LocalizedCopy.lockPortrait, isOn: $lockPortrait)
                    .onChange(of: lockPortrait) { _, _ in
                        OrientationLock.applyCurrentSetting()
                    }
                Toggle(LocalizedCopy.hapticFeedback, isOn: $hapticsEnabled)
                Toggle(LocalizedCopy.disableAutoLock, isOn: $disableAutoLock)
            }
        }
        .navigationTitle(LocalizedCopy.device)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About

struct SettingsAboutView: View {
    private static let appIconPreviewSize: CGFloat = 120
    private static let appIconPreviewCornerRadius: CGFloat = 27

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("AboutAppIconPreview")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: Self.appIconPreviewSize, height: Self.appIconPreviewSize)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: Self.appIconPreviewCornerRadius,
                                style: .continuous
                            )
                        )
                        .accessibilityHidden(true)

                    Text(LocalizedCopy.appName)
                        .font(.title2.weight(.semibold))

                    Text(SettingsAboutAppInfo.versionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink {
                    SettingsAppFeaturesView()
                } label: {
                    Text(LocalizedCopy.appFeatures)
                }
                SettingsAboutPrivacyPolicyRow()
                SettingsAboutContactSupportRow()
            }
        }
        .navigationTitle(LocalizedCopy.settingsAbout)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum SettingsAboutAppInfo {
    static var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return LocalizedCopy.appVersionLabel(version: version, build: build)
    }
}

private enum AppLegalLinks {
    static let privacyPolicy = URL(string: "https://ian3e.github.io/Shoplister/privacy.html")!
}

private struct SettingsAboutPrivacyPolicyRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(AppLegalLinks.privacyPolicy)
        } label: {
            HStack {
                Text(LocalizedCopy.privacyPolicy)
                    .foregroundStyle(.blue)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(LocalizedCopy.opensInBrowser)
    }
}

private struct SettingsAboutContactSupportRow: View {
    var body: some View {
        Button {
            openSupportMail()
        } label: {
            HStack {
                Text(LocalizedCopy.contactSupport)
                    .foregroundStyle(.blue)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func openSupportMail() {
        guard SupportContactMail.tryBeginOpen() else { return }
        if SupportContactMail.canSendInAppMail {
            SupportMailComposePresenter.shared.present(onDismiss: SupportContactMail.endOpen)
        } else {
            SupportContactMail.openMailto()
        }
    }
}

private final class SupportMailComposePresenter: NSObject, MFMailComposeViewControllerDelegate {
    static let shared = SupportMailComposePresenter()

    private var onDismiss: (() -> Void)?

    func present(onDismiss: @escaping () -> Void) {
        guard MFMailComposeViewController.canSendMail(), self.onDismiss == nil else {
            onDismiss()
            return
        }

        self.onDismiss = onDismiss

        let draft = SupportContactMail.draft
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = self
        controller.setToRecipients(draft.recipients)
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)

        guard let presenter = Self.topPresentingViewController() else {
            self.onDismiss = nil
            onDismiss()
            return
        }

        presenter.present(controller, animated: true)
    }

    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        controller.dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
            self?.onDismiss = nil
        }
    }

    private static func topPresentingViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return topPresentingViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = base as? UITabBarController {
            return topPresentingViewController(base: tabBarController.selectedViewController)
        }
        if let presentedViewController = base?.presentedViewController {
            return topPresentingViewController(base: presentedViewController)
        }
        return base
    }
}

private enum SupportContactMail {
    static let address = "support.shoplister@gmail.com"

    struct Draft {
        let recipients: [String]
        let subject: String
        let body: String
    }

    static var canSendInAppMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    static var draft: Draft {
        Draft(
            recipients: [address],
            subject: mailSubject,
            body: mailBody
        )
    }

    static var mailSubject: String {
        "\(LocalizedCopy.appName) Support"
    }

    static var mailBody: String {
        """

        ---
        The details below help us resolve your issue:
        App version: \(appVersion)
        iOS version: \(iosVersion)
        Device: \(deviceDescription)
        """
    }

    private static var isOpeningMailto = false
    private static var isOpeningSupportMail = false

    static func tryBeginOpen() -> Bool {
        guard !isOpeningSupportMail else { return false }
        isOpeningSupportMail = true
        return true
    }

    static func endOpen() {
        isOpeningSupportMail = false
    }

    static func openMailto() {
        guard let url = mailtoURL else {
            endOpen()
            return
        }
        guard !isOpeningMailto else { return }
        isOpeningMailto = true
        UIApplication.shared.open(url) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isOpeningMailto = false
                endOpen()
            }
        }
    }

    private static var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: mailSubject),
            URLQueryItem(name: "body", value: mailBody),
        ]
        return components.url
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private static var iosVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private static var deviceDescription: String {
        "\(UIDevice.current.model) (\(machineIdentifier))"
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "Unknown" : identifier
    }
}

// MARK: - Shared

struct SettingsSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SettingsItemLibraryAlertsModifier: ViewModifier {
    @Binding var pendingCatalogLanguageRaw: String?
    @Binding var catalogLanguagePickerValue: String
    @Binding var catalogLanguageRaw: String
    @Binding var isPresentingExportConfirm: Bool
    @Binding var isPresentingImportReplaceConfirm: Bool
    @Binding var isPresentingClearLibraryConfirm: Bool
    @Binding var backupErrorMessage: String?
    @Binding var backupSuccessMessage: String?
    @Binding var pendingImportURL: URL?
    let onExport: () -> Void
    let onImport: () -> Void
    let onClearLibrary: () -> Void
    let store: GroceryStore

    private var pendingLanguageChangePresented: Binding<Bool> {
        Binding(
            get: { pendingCatalogLanguageRaw != nil },
            set: { if !$0 { pendingCatalogLanguageRaw = nil } }
        )
    }

    private var backupErrorPresented: Binding<Bool> {
        Binding(
            get: { backupErrorMessage != nil },
            set: { if !$0 { backupErrorMessage = nil } }
        )
    }

    private var backupSuccessPresented: Binding<Bool> {
        Binding(
            get: { backupSuccessMessage != nil },
            set: { if !$0 { backupSuccessMessage = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(LocalizedCopy.changeLibraryLanguageAlertTitle, isPresented: pendingLanguageChangePresented) {
                Button(LocalizedCopy.cancel, role: .cancel) {
                    pendingCatalogLanguageRaw = nil
                    catalogLanguagePickerValue = catalogLanguageRaw
                }
                Button(LocalizedCopy.changeLanguage, role: .destructive) {
                    guard let pending = pendingCatalogLanguageRaw else { return }
                    store.resetLibraryToInitialSeed()
                    catalogLanguageRaw = pending
                    catalogLanguagePickerValue = pending
                    pendingCatalogLanguageRaw = nil
                }
            } message: {
                Text(LocalizedCopy.changeLibraryLanguageMessage)
            }
            .alert(LocalizedCopy.export, isPresented: $isPresentingExportConfirm) {
                Button(LocalizedCopy.cancel, role: .cancel) {}
                Button(LocalizedCopy.continueAction, action: onExport)
            } message: {
                Text(LocalizedCopy.exportBackupExplainer)
            }
            .alert(LocalizedCopy.importAction, isPresented: $isPresentingImportReplaceConfirm) {
                Button(LocalizedCopy.cancel, role: .cancel) { pendingImportURL = nil }
                Button(LocalizedCopy.replace, role: .destructive, action: onImport)
            } message: {
                Text(LocalizedCopy.importBackupExplainer)
            }
            .alert(LocalizedCopy.clearLibraryAlertTitle, isPresented: $isPresentingClearLibraryConfirm) {
                Button(LocalizedCopy.cancel, role: .cancel) {}
                Button(LocalizedCopy.clearLibrary, role: .destructive, action: onClearLibrary)
            } message: {
                Text(LocalizedCopy.clearLibraryAlertMessage)
            }
            .alert(LocalizedCopy.backup, isPresented: backupErrorPresented) {
                Button(LocalizedCopy.done, role: .cancel) { backupErrorMessage = nil }
            } message: {
                if let backupErrorMessage {
                    Text(backupErrorMessage)
                }
            }
            .alert(LocalizedCopy.importComplete, isPresented: backupSuccessPresented) {
                Button(LocalizedCopy.done, role: .cancel) { backupSuccessMessage = nil }
            } message: {
                if let backupSuccessMessage {
                    Text(backupSuccessMessage)
                }
            }
    }
}
