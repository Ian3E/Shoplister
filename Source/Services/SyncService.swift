import CloudKit
import Foundation
import Network
import os
import SwiftUI
import UIKit

/// iCloud sync for the active language's library (household sync plan, Phase 1).
///
/// **1b:** turning on **iCloud Sync** uploads every item, section, shopping-list entry, and saved
/// list into the `Household` zone of the user's private database.
/// **1c:** before uploading, check whether iCloud already has a library; if so, ask, then replace
/// this device's library with a full download. Later downloaded changes are merged in.
/// **1d:** every user edit is reported by `GroceryStore.onLibraryChange` and queued for upload;
/// other devices learn about it via CloudKit push (plus a fetch whenever the app comes to the front).
/// **1e:** whole-library operations (language change, Clear Library, Import) sync like big edits; a
/// language change from another device triggers a fresh full download. Signing out of iCloud or
/// iCloud data being deleted turns sync off and keeps the local lists.
///
/// Built on `CKSyncEngine`, which batches, retries network/account problems, and remembers what is
/// still unsent (its state is saved to disk on every `.stateUpdate`). Conflicts follow the plan's
/// v1 rule — **the device that syncs last wins**: on `serverRecordChanged` we adopt the server's
/// version stamp and resend our copy.
@MainActor
final class SyncService: ObservableObject, CKSyncEngineDelegate {
    static let shared = SyncService()

    enum Status: Equatable {
        /// Switch is off (or the app hasn't attached the store yet).
        case off
        case syncing
        case upToDate
        /// Unsent changes, but no network connection; they send automatically later.
        case waitingForNetwork
        /// A send failed for a reason the engine won't retry by itself.
        case failed
    }

    @Published private(set) var status: Status = .off

    /// Questions/notices Settings shows while turning sync on.
    enum EnablePrompt: Identifiable {
        /// iCloud already has a library: replace this device's library with it?
        case replaceLocalLibrary
        /// Couldn't reach iCloud to check; the switch was turned back off.
        case couldNotReachICloud
        /// Signed out of iCloud / switched Apple ID; sync was turned off, local lists kept.
        case iCloudAccountChanged
        /// Shoplister's data was deleted from iCloud; sync was turned off, local lists kept.
        case iCloudDataDeleted
        /// The owner removed this member or stopped sharing; sync was turned off, local lists kept.
        case removedFromHousehold

        var id: Self { self }
    }

    @Published var enablePrompt: EnablePrompt?

    /// A household invite the person tapped (Phase 2a). Step 2c turns this into the join flow.
    struct HouseholdInvite {
        let metadata: CKShare.Metadata
        /// Inviter's name as iCloud reports it, if available.
        let ownerName: String?
    }

    @Published var pendingHouseholdInvite: HouseholdInvite?
    /// Accepting an invite and downloading the household's lists.
    @Published private(set) var isJoiningHousehold = false
    /// Accepting the invite failed (alert at the app root).
    @Published var householdJoinFailed = false
    /// Removing this member from the household in iCloud (Leave Household).
    @Published private(set) var isLeavingHousehold = false
    /// Leaving failed (usually offline); shown as an alert in Settings.
    @Published var householdLeaveFailed = false
    /// For the "no longer in X's household" message (membership is already cleared by then).
    @Published private(set) var endedHouseholdOwnerName: String?

    /// The household share for this zone, if the owner has created one (Phase 2b).
    @Published private(set) var householdShare: CKShare?
    /// Getting the share ready before Apple's sharing screen opens.
    @Published private(set) var isPreparingHouseholdSharing = false
    /// Creating or opening the household failed (shown as an alert in Settings).
    @Published var householdSharingFailed = false
    private var householdSharingDelegate: HouseholdSharingDelegate?

    /// All household data lives in one custom zone (Phase 2 shares this whole zone).
    /// The Household zone this device syncs: its own (owner) or, after joining, the owner's shared zone.
    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Household", ownerName: memberZoneOwnerName ?? CKCurrentUserDefaultName)
    }

    // MARK: Household membership (Phase 2c), persisted so it survives relaunch

    private static let memberZoneOwnerKey = "app.householdMemberZoneOwner"
    private static let memberOwnerDisplayNameKey = "app.householdMemberOwnerDisplayName"

    /// Set while this device is a member of someone else's household (the owner's iCloud record name).
    private static var memberZoneOwnerName: String? {
        get { UserDefaults.standard.string(forKey: memberZoneOwnerKey) }
        set { UserDefaults.standard.set(newValue, forKey: memberZoneOwnerKey) }
    }

    /// True while this device syncs someone else's household (shared database) instead of its own.
    static var isHouseholdMember: Bool { memberZoneOwnerName != nil }

    /// The owner's name for Settings ("Member of Dana's household"), if iCloud provided one.
    static var householdOwnerDisplayName: String? {
        UserDefaults.standard.string(forKey: memberOwnerDisplayNameKey)
    }

    private static func setMembership(ownerZoneName: String?, ownerDisplayName: String?) {
        memberZoneOwnerName = ownerZoneName
        UserDefaults.standard.set(ownerDisplayName, forKey: memberOwnerDisplayNameKey)
    }

    /// Members sync through the shared database; owners (and solo users) through their private one.
    private var database: CKDatabase {
        Self.isHouseholdMember ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    /// Records/zone events for the zone this device syncs (the shared database can hold other zones).
    private static func isOurZone(_ id: CKRecordZone.ID) -> Bool {
        guard id.zoneName == zoneID.zoneName else { return false }
        return !isHouseholdMember || id.ownerName == zoneID.ownerName
    }

    private enum RecordType {
        static let item = "Item"
        static let section = "Section"
        static let shoppingEntry = "ShoppingEntry"
        static let savedList = "SavedList"
        static let householdInfo = "HouseholdInfo"
        /// `HouseholdInfo` is a single record.
        static let householdInfoName = "main"
    }

    private let logger = Logger(subsystem: "com.byteloft.apps.shoplister", category: "Sync")
    private weak var store: GroceryStore?
    private var engine: CKSyncEngine?
    /// Last known server "system fields" per record name, so updates aren't rejected as conflicts.
    private var systemFieldsByRecordName: [String: Data] = [:]
    /// True while downloading everything to replace this device's library (1c). Fetched records
    /// are held in `replacementBuffer` and applied in one go when the fetch finishes, so the UI
    /// never shows a half-downloaded library.
    private var isReplacingLocalLibrary = false
    private var replacementBuffer: [CKRecord] = []
    private let pathMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                self?.isNetworkAvailable = available
                self?.updateStatusFromPendingChanges()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.byteloft.apps.shoplister.sync.network"))
    }

    // MARK: - Lifecycle (called from ShoplisterApp)

    /// Call once at launch. Starts syncing if the switch is already on.
    func attach(store: GroceryStore) {
        guard self.store == nil else { return }
        self.store = store
        systemFieldsByRecordName = Self.loadSystemFields()
        if UserDefaults.standard.bool(forKey: AppICloudSync.storageKey) {
            startEngine()
            if Self.isHouseholdMember {
                Task { await verifyHouseholdMembership() }
            }
        }
        // After the engine starts: setting this delivers edits made before launch finished
        // (e.g. share-extension items merged in GroceryStore.init), which need the engine running.
        store.onLibraryChange = { [weak self] change in
            self?.queueLocalChanges(change)
        }
    }

    /// Called when the **iCloud Sync** switch changes.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard engine == nil, enablePrompt == nil else { return }
            status = .syncing
            Task { await checkICloudThenEnable() }
        } else {
            // Keep notices that explain why sync turned itself off; only drop an unanswered question.
            if enablePrompt == .replaceLocalLibrary {
                enablePrompt = nil
            }
            isReplacingLocalLibrary = false
            replacementBuffer = []
            stopEngine()
        }
    }

    /// Turning sync on: upload if iCloud is empty, otherwise ask before replacing this device's library.
    private func checkICloudThenEnable() async {
        do {
            let hasLibrary = try await iCloudHasLibrary()
            if hasLibrary {
                enablePrompt = .replaceLocalLibrary
            } else if Self.isHouseholdMember {
                // The household isn't there any more (sharing stopped).
                householdEndedForMember()
            } else {
                startEngine()
                queueFullUpload()
            }
        } catch {
            logger.error("Couldn't check iCloud before enabling sync: \(error.localizedDescription)")
            enablePrompt = .couldNotReachICloud
            turnSwitchOff()
        }
    }

    /// The single `HouseholdInfo` record exists once any device has uploaded a library.
    private func iCloudHasLibrary() async throws -> Bool {
        let infoID = Self.recordID(Self.recordName(RecordType.householdInfo, RecordType.householdInfoName))
        do {
            _ = try await database.record(for: infoID)
            return true
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return false
        }
    }

    /// "Replace" in the prompt: forget this device's sync history and download everything.
    func confirmReplaceLocalLibrary() {
        enablePrompt = nil
        restartWithFullDownload()
    }

    /// Fresh engine with no history: fetches the whole zone into `replacementBuffer`, then
    /// `finishReplacingLocalLibraryIfNeeded` swaps the active library in one step.
    private func restartWithFullDownload() {
        stopEngine()
        Self.deleteLocalSyncFiles()
        systemFieldsByRecordName = [:]
        isReplacingLocalLibrary = true
        replacementBuffer = []
        startEngine()
        status = .syncing
        guard let engine else { return }
        let logger = self.logger
        // Detached: this can run from inside a CKSyncEngine delegate callback (a language change
        // from another device), and CloudKit forbids awaiting the engine from that context.
        Task.detached {
            do {
                try await engine.fetchChanges()
            } catch {
                logger.error("Initial download failed: \(error.localizedDescription)")
                // The engine keeps retrying on its own; the buffer applies when a fetch completes.
            }
        }
    }

    /// "Cancel" (or "Back Up First") in the prompt: leave everything as it was.
    func cancelEnable() {
        enablePrompt = nil
        turnSwitchOff()
    }

    /// Sync can't continue (account gone, iCloud data deleted, left or removed from the household):
    /// forget this device's sync history and household membership, keep the lists, explain why
    /// (if `notice` is set), and turn the switch off.
    private func turnOffKeepingLocalLists(notice: EnablePrompt?) {
        stopEngine()
        Self.deleteLocalSyncFiles()
        Self.setMembership(ownerZoneName: nil, ownerDisplayName: nil)
        systemFieldsByRecordName = [:]
        isReplacingLocalLibrary = false
        replacementBuffer = []
        isJoiningHousehold = false
        enablePrompt = notice
        turnSwitchOff()
    }

    private func turnSwitchOff() {
        // ShoplisterApp observes this key and calls `setEnabled(false)`.
        UserDefaults.standard.set(false, forKey: AppICloudSync.storageKey)
        status = .off
    }

    private func startEngine() {
        guard engine == nil else { return }
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: Self.loadEngineState(),
            delegate: self
        )
        engine = CKSyncEngine(configuration)
        // Lets CloudKit's silent pushes reach the app so other devices' edits arrive promptly.
        UIApplication.shared.registerForRemoteNotifications()
        updateStatusFromPendingChanges()
        logger.info("Sync engine started (\(Self.isHouseholdMember ? "household member" : "own iCloud"))")
    }

    private func stopEngine() {
        guard let engine else {
            status = .off
            return
        }
        self.engine = nil
        status = .off
        // Detached for the same reason as `restartWithFullDownload` (may run inside a delegate callback).
        Task.detached { await engine.cancelOperations() }
        logger.info("Sync engine stopped")
    }

    /// Queues the zone plus every object in the active library (and the language record) for upload.
    private func queueFullUpload() {
        guard let engine, let store else { return }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        var names: [String] = [Self.recordName(RecordType.householdInfo, RecordType.householdInfoName)]
        names += store.catalog.map { Self.recordName(RecordType.item, $0.id.uuidString) }
        names += (store.inventoryTags + store.shoppingTags).map { Self.recordName(RecordType.section, $0.id.uuidString) }
        names += store.shopping.map { Self.recordName(RecordType.shoppingEntry, $0.id.uuidString) }
        names += store.recipes.map { Self.recordName(RecordType.savedList, $0.id.uuidString) }
        engine.state.add(pendingRecordZoneChanges: names.map { .saveRecord(Self.recordID($0)) })
        status = .syncing
        logger.info("Queued full upload of \(names.count) records")
    }

    /// Queues one user edit (from `GroceryStore`) for upload. Ignored while sync is off.
    private func queueLocalChanges(_ change: GroceryStore.LibraryChangeSet) {
        // Safety net for Phase 2e (Settings already blocks this): a member must never push a language
        // change, which would delete the whole household's library. Restore the household's lists instead.
        if change.householdInfoChanged, Self.isHouseholdMember, engine != nil {
            logger.error("Blocked a library language change from a household member; restoring household lists")
            restartWithFullDownload()
            return
        }
        guard let engine, !isReplacingLocalLibrary else { return }
        func ids(_ type: String, _ uuids: Set<UUID>) -> [CKRecord.ID] {
            uuids.map { Self.recordID(Self.recordName(type, $0.uuidString)) }
        }
        let saves = ids(RecordType.item, change.savedItemIDs)
            + ids(RecordType.section, change.savedTagIDs)
            + ids(RecordType.shoppingEntry, change.savedShoppingEntryIDs)
            + ids(RecordType.savedList, change.savedRecipeIDs)
        let deletes = ids(RecordType.item, change.deletedItemIDs)
            + ids(RecordType.section, change.deletedTagIDs)
            + ids(RecordType.shoppingEntry, change.deletedShoppingEntryIDs)
            + ids(RecordType.savedList, change.deletedRecipeIDs)
        var changes = saves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) }
            + deletes.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord($0) }
        if change.householdInfoChanged {
            changes.append(.saveRecord(Self.recordID(Self.recordName(RecordType.householdInfo, RecordType.householdInfoName))))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
        updateStatusFromPendingChanges()
    }

    /// Checks iCloud for other devices' changes now (called when the app comes to the front).
    func fetchNow() {
        guard let engine else { return }
        if Self.isHouseholdMember {
            Task { await verifyHouseholdMembership() }
        }
        let logger = self.logger
        Task.detached {
            do {
                try await engine.fetchChanges()
            } catch {
                logger.info("Foreground fetch didn't complete: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Household invites (Phase 2)

    /// Called by `SceneDelegate` when an invite link opens the app.
    func receivedHouseholdInvite(_ metadata: CKShare.Metadata) {
        let ownerName = metadata.ownerIdentity.nameComponents.map {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
        }
        logger.info("Household invite received from \(ownerName ?? "unknown", privacy: .private)")
        // The owner tapping their own link, or a member re-opening the link: nothing to join.
        if metadata.participantRole == .owner {
            logger.info("Ignoring invite: this is the owner's own household")
            return
        }
        if metadata.share.recordID.zoneID.ownerName == Self.memberZoneOwnerName,
           UserDefaults.standard.bool(forKey: AppICloudSync.storageKey)
        {
            logger.info("Ignoring invite: already a member of this household")
            fetchNow()
            return
        }
        pendingHouseholdInvite = HouseholdInvite(metadata: metadata, ownerName: ownerName)
    }

    /// "Join" in the invite prompt: accept, switch to the owner's shared zone, download everything.
    func joinHousehold() {
        guard let invite = pendingHouseholdInvite, !isJoiningHousehold else { return }
        pendingHouseholdInvite = nil
        isJoiningHousehold = true
        Task {
            do {
                _ = try await container.accept(invite.metadata)
            } catch {
                logger.error("Couldn't accept household invite: \(error.localizedDescription)")
                isJoiningHousehold = false
                householdJoinFailed = true
                return
            }
            stopEngine()
            Self.setMembership(
                ownerZoneName: invite.metadata.share.recordID.zoneID.ownerName,
                ownerDisplayName: invite.ownerName
            )
            enablePrompt = nil
            // Turning the switch on here is harmless: the engine below is already running by the time
            // ShoplisterApp's onChange calls setEnabled(true), so it does nothing.
            UserDefaults.standard.set(true, forKey: AppICloudSync.storageKey)
            restartWithFullDownload()
            logger.info("Joined household; downloading its lists")
        }
    }

    /// Settings → Leave Household: take this person out of the share in iCloud, then keep the current
    /// lists on this device as its own (sync off).
    func leaveHousehold() async {
        guard Self.isHouseholdMember, !isLeavingHousehold else { return }
        isLeavingHousehold = true
        defer { isLeavingHousehold = false }
        do {
            // A participant leaves a share by deleting it from their shared database.
            _ = try await container.sharedCloudDatabase.deleteRecord(withID: Self.householdShareID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Already removed (e.g. the owner stopped sharing): just clean up here.
        } catch {
            logger.error("Couldn't leave household: \(error.localizedDescription)")
            householdLeaveFailed = true
            return
        }
        logger.info("Left household")
        turnOffKeepingLocalLists(notice: nil)
    }

    /// iCloud doesn't reliably notify a member that they were removed, so check directly: a removed
    /// member can no longer read the household's share. Runs at launch and whenever the app comes to
    /// the front. Network trouble is ignored (we'll check again next time).
    private func verifyHouseholdMembership() async {
        guard Self.isHouseholdMember, engine != nil, !isReplacingLocalLibrary, !isLeavingHousehold else { return }
        let shareID = Self.householdShareID
        do {
            let record = try await container.sharedCloudDatabase.record(for: shareID)
            // Still readable: make sure we're still an accepted participant.
            if let share = record as? CKShare,
               let me = share.currentUserParticipant,
               me.acceptanceStatus == .removed
            {
                logger.info("Household check: this member was removed")
                endHouseholdIfStillMember(of: shareID)
            }
        } catch let error as CKError
            where error.code == .unknownItem || error.code == .zoneNotFound || error.code == .permissionFailure
        {
            logger.info("Household check: share no longer available (\(error.code.rawValue))")
            endHouseholdIfStillMember(of: shareID)
        } catch {
            logger.info("Household check skipped: \(error.localizedDescription)")
        }
    }

    /// Guards against a slow check finishing after the person already left or joined another household.
    private func endHouseholdIfStillMember(of shareID: CKRecord.ID) {
        guard Self.isHouseholdMember, Self.householdShareID == shareID else { return }
        householdEndedForMember()
    }

    /// The owner removed this member or stopped sharing.
    private func householdEndedForMember() {
        logger.info("Household sharing ended for this member")
        endedHouseholdOwnerName = Self.householdOwnerDisplayName
        turnOffKeepingLocalLists(notice: .removedFromHousehold)
    }

    /// "Back Up First" in the invite prompt: share a backup file, then ask again.
    func backUpBeforeJoining() {
        guard let invite = pendingHouseholdInvite, let store else { return }
        pendingHouseholdInvite = nil
        let languageRaw = UserDefaults.standard.string(forKey: AppContentLanguage.storageKey) ?? ""
        let url: URL
        do {
            url = try store.exportLibraryBackup(for: AppContentLanguage(rawValue: languageRaw) ?? .english)
        } catch {
            logger.error("Backup before joining failed: \(error.localizedDescription)")
            pendingHouseholdInvite = invite
            return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
            Task { @MainActor in self?.pendingHouseholdInvite = invite }
        }
        // Let the alert finish dismissing before presenting the share sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Self.topPresenter()?.present(controller, animated: true)
        }
    }

    // MARK: - Household sharing, owner side (Phase 2b)

    private var container: CKContainer { CKContainer(identifier: AppICloudSync.containerIdentifier) }

    /// The whole Household zone is shared with one zone-wide share record.
    private static var householdShareID: CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
    }

    /// Settings → Household calls this to show "Invite People" vs "Manage Household".
    func refreshHouseholdShare() async {
        guard engine != nil, !Self.isHouseholdMember else {
            householdShare = nil
            return
        }
        do {
            householdShare = try await fetchHouseholdShare()
        } catch {
            // Offline etc.: keep showing what we knew.
            logger.info("Couldn't check household share: \(error.localizedDescription)")
        }
    }

    /// "Invite People" / "Manage Household": make sure the share exists, then open Apple's sharing screen.
    func presentHouseholdSharing() async {
        guard engine != nil, !Self.isHouseholdMember, !isPreparingHouseholdSharing else { return }
        isPreparingHouseholdSharing = true
        defer { isPreparingHouseholdSharing = false }
        do {
            let share: CKShare
            if let existing = try await fetchHouseholdShare() {
                share = existing
            } else {
                share = try await createHouseholdShare()
            }
            householdShare = share
            guard let presenter = Self.topPresenter() else { return }
            let controller = UICloudSharingController(share: share, container: container)
            // Invite-only (no public link), and invited people can edit.
            controller.availablePermissions = [.allowPrivate, .allowReadWrite]
            let delegate = HouseholdSharingDelegate(service: self)
            householdSharingDelegate = delegate
            controller.delegate = delegate
            presenter.present(controller, animated: true)
        } catch {
            logger.error("Couldn't open household sharing: \(error.localizedDescription)")
            householdSharingFailed = true
        }
    }

    /// Nil when there's no share yet (or the zone hasn't reached iCloud yet).
    private func fetchHouseholdShare() async throws -> CKShare? {
        do {
            return try await container.privateCloudDatabase.record(for: Self.householdShareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    private func createHouseholdShare() async throws -> CKShare {
        let share = CKShare(recordZoneID: Self.zoneID)
        share[CKShare.SystemFieldKey.title] = LocalizedCopy.householdShareTitle
        share.publicPermission = .none
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw CKError(.internalError)
        }
        logger.info("Household share created")
        return saved
    }

    fileprivate func householdShareDidChange(_ share: CKShare?) {
        householdShare = share
    }

    private static func topPresenter() -> UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        else { return nil }
        var presenter = root
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // Ignore events from an engine we've already stopped.
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            Self.saveEngineState(update.stateSerialization)
        case .accountChange(let change):
            logger.info("iCloud account changed: \(String(describing: change))")
            switch change.changeType {
            case .signIn:
                break
            case .signOut, .switchAccounts:
                turnOffKeepingLocalLists(notice: .iCloudAccountChanged)
            @unknown default:
                break
            }
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { Self.isOurZone($0.zoneID) }) {
                if Self.isHouseholdMember {
                    // For a member, the shared zone disappearing means removed / sharing stopped.
                    householdEndedForMember()
                } else {
                    logger.info("Household zone was deleted from iCloud")
                    turnOffKeepingLocalLists(notice: .iCloudDataDeleted)
                }
            }
        case .willSendChanges, .willFetchChanges:
            status = .syncing
        case .sentRecordZoneChanges(let sent):
            handleSentRecordZoneChanges(sent, syncEngine: syncEngine)
        case .didSendChanges:
            updateStatusFromPendingChanges()
        case .fetchedRecordZoneChanges(let fetched):
            handleFetchedRecordZoneChanges(fetched)
        case .didFetchChanges:
            finishReplacingLocalLibraryIfNeeded()
            updateStatusFromPendingChanges()
        default:
            // Database-level events (e.g. zone deleted elsewhere) are handled in 1e.
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        var recordsByID: [CKRecord.ID: CKRecord] = [:]
        var vanished: [CKSyncEngine.PendingRecordZoneChange] = []

        for change in syncEngine.state.pendingRecordZoneChanges where scope.contains(change) {
            switch change {
            case .saveRecord(let recordID):
                if let record = makeRecord(for: recordID) {
                    recordsByID[recordID] = record
                    changes.append(change)
                } else {
                    // The object was deleted locally before it was sent; nothing to upload.
                    vanished.append(change)
                }
            case .deleteRecord:
                changes.append(change)
            @unknown default:
                break
            }
        }
        if !vanished.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: vanished)
        }
        guard !changes.isEmpty else { return nil }
        let records = recordsByID
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { records[$0] }
    }

    // MARK: - Fetched changes

    private func handleFetchedRecordZoneChanges(_ fetched: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        // A member's shared database could hold other zones; only this household's records count.
        let modifications = fetched.modifications.map(\.record).filter { Self.isOurZone($0.recordID.zoneID) }
        let fetchedDeletions = fetched.deletions.filter { Self.isOurZone($0.recordID.zoneID) }
        // An unsent local edit is newer than whatever iCloud has; skip that record's download so the
        // edit isn't briefly undone (it uploads next and wins — "last to sync wins").
        let pendingSaveNames: Set<String> = Set(
            (engine?.state.pendingRecordZoneChanges ?? []).compactMap { change in
                if case .saveRecord(let id) = change { return id.recordName }
                return nil
            }
        )
        let householdInfoName = Self.recordName(RecordType.householdInfo, RecordType.householdInfoName)

        // Another device changed the library language (Phase 1e): do what it did — reseed, switch
        // language — then download the new library in full rather than merging piece by piece.
        // Skipped if this device's own language change hasn't uploaded yet.
        if !isReplacingLocalLibrary,
           !pendingSaveNames.contains(householdInfoName),
           let info = modifications.first(where: { $0.recordType == RecordType.householdInfo }),
           let languageRaw = info["libraryLanguage"] as? String,
           AppContentLanguage(rawValue: languageRaw) != nil,
           languageRaw != (UserDefaults.standard.string(forKey: AppContentLanguage.storageKey) ?? AppContentLanguage.english.rawValue)
        {
            logger.info("Library language changed on another device to \(languageRaw)")
            store?.resetLibraryToInitialSeed()
            UserDefaults.standard.set(languageRaw, forKey: AppContentLanguage.storageKey)
            store?.applyContentLanguageFromUserDefaults()
            restartWithFullDownload()
            return
        }
        let records = modifications
            .filter { !pendingSaveNames.contains($0.recordID.recordName) }
        for record in records {
            systemFieldsByRecordName[record.recordID.recordName] = Self.encodeSystemFields(of: record)
        }
        for deletion in fetchedDeletions {
            systemFieldsByRecordName[deletion.recordID.recordName] = nil
        }
        Self.saveSystemFields(systemFieldsByRecordName)

        if isReplacingLocalLibrary {
            replacementBuffer += records
            return
        }
        var changes = Self.libraryChanges(from: records)
        for deletion in fetchedDeletions {
            Self.addDeletion(recordName: deletion.recordID.recordName, to: &changes)
        }
        // Same list animation as the user's own taps (`.snappy`), so rows slide/fade in and out
        // instead of jumping; none when Reduce Motion is on, matching the rest of the app.
        let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .snappy
        withAnimation(animation) {
            store?.applySyncedChanges(changes, replacingActiveLibrary: false)
        }
    }

    /// Applies the full download in one go once the first complete fetch finishes.
    private func finishReplacingLocalLibraryIfNeeded() {
        guard isReplacingLocalLibrary, let store else { return }
        // Safety: every uploaded library has a HouseholdInfo record. If a fetch "finished" without it
        // (interrupted or partial), keep waiting rather than replacing the library with nothing.
        guard replacementBuffer.contains(where: { $0.recordType == RecordType.householdInfo }) else {
            logger.info("Fetch finished without HouseholdInfo; still waiting for the full download")
            return
        }
        isReplacingLocalLibrary = false
        let records = replacementBuffer
        replacementBuffer = []

        // Match iCloud's library language first, so the download goes into the right library.
        if let info = records.first(where: { $0.recordType == RecordType.householdInfo }),
           let language = info["libraryLanguage"] as? String,
           AppContentLanguage(rawValue: language) != nil,
           UserDefaults.standard.string(forKey: AppContentLanguage.storageKey) != language
        {
            UserDefaults.standard.set(language, forKey: AppContentLanguage.storageKey)
            store.applyContentLanguageFromUserDefaults()
        }
        store.applySyncedChanges(Self.libraryChanges(from: records), replacingActiveLibrary: true)
        isJoiningHousehold = false
        logger.info("Replaced local library with \(records.count) records from iCloud")
    }

    // MARK: - CKRecords → local objects

    private static func libraryChanges(from records: [CKRecord]) -> GroceryStore.SyncedLibraryChanges {
        var changes = GroceryStore.SyncedLibraryChanges()
        for record in records {
            guard let parsed = parseRecordName(record.recordID.recordName),
                  let uuid = UUID(uuidString: parsed.id) else { continue }
            switch record.recordType {
            case RecordType.item:
                guard let name = record["name"] as? String,
                      let inventoryTagID = (record["inventoryTagID"] as? String).flatMap(UUID.init(uuidString:)),
                      let shoppingTagID = (record["shoppingTagID"] as? String).flatMap(UUID.init(uuidString:))
                else { continue }
                changes.items.append(GroceryItem(
                    id: uuid,
                    name: name,
                    inventoryTagID: inventoryTagID,
                    shoppingTagID: shoppingTagID,
                    sortOrder: (record["sortOrder"] as? Int) ?? 0,
                    hasImage: ((record["hasImage"] as? Int) ?? 0) != 0
                ))
            case RecordType.section:
                guard let kind = (record["kind"] as? String).flatMap(Tag.Kind.init(rawValue:)),
                      let title = record["title"] as? String else { continue }
                changes.tags.append(Tag(
                    id: uuid,
                    kind: kind,
                    title: title,
                    sortOrder: (record["sortOrder"] as? Int) ?? 0
                ))
            case RecordType.shoppingEntry:
                guard let itemID = (record["itemID"] as? String).flatMap(UUID.init(uuidString:)) else { continue }
                changes.shoppingEntries.append(ShoppingEntry(
                    id: uuid,
                    itemID: itemID,
                    quantity: (record["quantity"] as? Int) ?? 1,
                    isChecked: ((record["isChecked"] as? Int) ?? 0) != 0,
                    addedAt: (record["addedAt"] as? Date) ?? Date()
                ))
            case RecordType.savedList:
                guard let name = record["name"] as? String,
                      let linesData = record["lines"] as? Data,
                      let lines = try? JSONDecoder().decode([RecipeLine].self, from: linesData)
                else { continue }
                changes.recipes.append(Recipe(
                    id: uuid,
                    name: name,
                    sortOrder: (record["sortOrder"] as? Int) ?? 0,
                    lines: lines
                ))
            default:
                // HouseholdInfo is handled separately.
                continue
            }
        }
        return changes
    }

    private static func addDeletion(recordName: String, to changes: inout GroceryStore.SyncedLibraryChanges) {
        guard let parsed = parseRecordName(recordName),
              let uuid = UUID(uuidString: parsed.id) else { return }
        switch parsed.type {
        case RecordType.item: changes.deletedItemIDs.insert(uuid)
        case RecordType.section: changes.deletedTagIDs.insert(uuid)
        case RecordType.shoppingEntry: changes.deletedShoppingEntryIDs.insert(uuid)
        case RecordType.savedList: changes.deletedRecipeIDs.insert(uuid)
        default: break
        }
    }

    // MARK: - Sent changes

    private func handleSentRecordZoneChanges(
        _ sent: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) {
        for record in sent.savedRecords {
            systemFieldsByRecordName[record.recordID.recordName] = Self.encodeSystemFields(of: record)
        }
        for recordID in sent.deletedRecordIDs {
            systemFieldsByRecordName[recordID.recordName] = nil
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var hadPermanentFailure = false
        var householdEnded = false
        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Changed elsewhere since our last sync. v1 rule: last to sync wins — take the
                // server's version stamp and send our copy again.
                if let serverRecord = failure.error.serverRecord {
                    systemFieldsByRecordName[recordID.recordName] = Self.encodeSystemFields(of: serverRecord)
                }
                retry.append(.saveRecord(recordID))
            case .zoneNotFound where Self.isHouseholdMember, .permissionFailure where Self.isHouseholdMember:
                // The household's zone is gone or no longer ours to edit: removed from the household
                // or sharing stopped.
                householdEnded = true
            case .zoneNotFound:
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                systemFieldsByRecordName[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                // Our stored stamp points at a record the server no longer has; upload it fresh.
                systemFieldsByRecordName[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            case .networkFailure, .networkUnavailable:
                // The engine retries on its own once the connection is back.
                isNetworkAvailable = false
            case .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled, .requestRateLimited:
                // The engine retries these on its own.
                break
            default:
                hadPermanentFailure = true
                logger.error("Couldn't save \(recordID.recordName): \(failure.error.localizedDescription)")
            }
        }
        if householdEnded {
            householdEndedForMember()
            return
        }
        if !retry.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: retry)
        }
        Self.saveSystemFields(systemFieldsByRecordName)
        if hadPermanentFailure {
            status = .failed
        } else {
            updateStatusFromPendingChanges()
        }
    }

    private func updateStatusFromPendingChanges() {
        guard let engine else {
            status = .off
            return
        }
        if status == .failed || isReplacingLocalLibrary { return }
        let hasPending = !engine.state.pendingRecordZoneChanges.isEmpty
            || !engine.state.pendingDatabaseChanges.isEmpty
        if !hasPending {
            status = .upToDate
        } else {
            status = isNetworkAvailable ? .syncing : .waitingForNetwork
        }
    }

    // MARK: - Local objects → CKRecords

    private func makeRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let store, let parsed = Self.parseRecordName(recordID.recordName) else { return nil }
        let type = parsed.type
        let uuid = UUID(uuidString: parsed.id)

        switch type {
        case RecordType.householdInfo:
            let record = baseRecord(type: type, recordID: recordID)
            let language = UserDefaults.standard.string(forKey: AppContentLanguage.storageKey)
                ?? AppContentLanguage.english.rawValue
            record["libraryLanguage"] = language
            return record

        case RecordType.item:
            guard let item = store.catalog.first(where: { $0.id == uuid }) else { return nil }
            let record = baseRecord(type: type, recordID: recordID)
            record["name"] = item.name
            record["inventoryTagID"] = item.inventoryTagID.uuidString
            record["shoppingTagID"] = item.shoppingTagID.uuidString
            record["sortOrder"] = item.sortOrder
            record["hasImage"] = (item.hasImage ? 1 : 0)
            return record

        case RecordType.section:
            guard let tag = (store.inventoryTags + store.shoppingTags).first(where: { $0.id == uuid }) else { return nil }
            let record = baseRecord(type: type, recordID: recordID)
            record["kind"] = tag.kind.rawValue
            record["title"] = tag.title
            record["sortOrder"] = tag.sortOrder
            return record

        case RecordType.shoppingEntry:
            guard let entry = store.shopping.first(where: { $0.id == uuid }) else { return nil }
            let record = baseRecord(type: type, recordID: recordID)
            record["itemID"] = entry.itemID.uuidString
            record["quantity"] = entry.quantity
            record["isChecked"] = (entry.isChecked ? 1 : 0)
            record["addedAt"] = entry.addedAt
            return record

        case RecordType.savedList:
            guard let recipe = store.recipes.first(where: { $0.id == uuid }),
                  let lines = try? JSONEncoder().encode(recipe.lines) else { return nil }
            let record = baseRecord(type: type, recordID: recordID)
            record["name"] = recipe.name
            record["sortOrder"] = recipe.sortOrder
            record["lines"] = lines
            return record

        default:
            return nil
        }
    }

    /// A record carrying our last known server stamp (so it updates in place), or a brand-new one.
    private func baseRecord(type: String, recordID: CKRecord.ID) -> CKRecord {
        if let data = systemFieldsByRecordName[recordID.recordName],
           let record = Self.decodeSystemFields(data),
           record.recordType == type
        {
            return record
        }
        return CKRecord(recordType: type, recordID: recordID)
    }

    // MARK: - Record names

    /// `Item.<uuid>` etc.: the engine hands back only record IDs, so the type travels in the name.
    private static func recordName(_ type: String, _ id: String) -> String {
        "\(type).\(id)"
    }

    private static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    private static func parseRecordName(_ name: String) -> (type: String, id: String)? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    // MARK: - System fields (server version stamps)

    private static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: - Persistence (Application Support/Sync)

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("Sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var engineStateURL: URL { directoryURL.appendingPathComponent("engine-state.json") }
    private static var systemFieldsURL: URL { directoryURL.appendingPathComponent("record-system-fields.json") }

    private static func loadEngineState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: engineStateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private static func saveEngineState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: engineStateURL, options: [.atomic])
    }

    /// Forget this device's sync history (engine state + record stamps) before a fresh full download.
    private static func deleteLocalSyncFiles() {
        try? FileManager.default.removeItem(at: engineStateURL)
        try? FileManager.default.removeItem(at: systemFieldsURL)
    }

    private static func loadSystemFields() -> [String: Data] {
        guard let data = try? Data(contentsOf: systemFieldsURL),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: data) else { return [:] }
        return decoded
    }

    private static func saveSystemFields(_ fields: [String: Data]) {
        guard let data = try? JSONEncoder().encode(fields) else { return }
        try? data.write(to: systemFieldsURL, options: [.atomic])
    }
}

/// Hears back from Apple's sharing screen (people added, sharing stopped).
@MainActor
private final class HouseholdSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    private weak var service: SyncService?

    init(service: SyncService) {
        self.service = service
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        Logger(subsystem: "com.byteloft.apps.shoplister", category: "Sync")
            .error("Sharing screen couldn't save: \(error.localizedDescription)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        LocalizedCopy.householdShareTitle
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        service?.householdShareDidChange(csc.share)
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        service?.householdShareDidChange(nil)
    }
}
