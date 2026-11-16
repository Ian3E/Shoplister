import CloudKit
import Combine
import Foundation

/// iCloud sync settings shared across the app (household sync plan, Phase 1).
enum AppICloudSync {
    /// When **on**, the library and shopping list sync through the user's iCloud. Default **off**.
    static let storageKey = "app.iCloudSyncEnabled"
    /// Must match the container in `Shoplister.entitlements`. Container IDs are permanent.
    static let containerIdentifier = "iCloud.com.byteloft.apps.shoplister"
}

/// Watches whether this device can use iCloud right now, and re-checks automatically when the
/// user signs in or out (`CKAccountChanged`). Phase 1a: drives the Settings switch and status line.
@MainActor
final class ICloudAccountMonitor: ObservableObject {
    enum Status: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case couldNotDetermine

        /// Sync can be turned on only when an iCloud account is ready.
        var allowsEnablingSync: Bool { self == .available }
    }

    @Published private(set) var status: Status = .checking
    private var accountChangeObservation: AnyCancellable?

    init() {
        accountChangeObservation = NotificationCenter.default
            .publisher(for: .CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
        Task { await refresh() }
    }

    func refresh() async {
        let container = CKContainer(identifier: AppICloudSync.containerIdentifier)
        do {
            switch try await container.accountStatus() {
            case .available: status = .available
            case .noAccount: status = .noAccount
            case .restricted: status = .restricted
            case .temporarilyUnavailable: status = .temporarilyUnavailable
            case .couldNotDetermine: status = .couldNotDetermine
            @unknown default: status = .couldNotDetermine
            }
        } catch {
            status = .couldNotDetermine
        }
    }
}
