import CloudKit
import Foundation
import os
import UIKit

/// iCloud sync for the active language's library (household sync plan, Phase 1).
///
/// **1b:** turning on **iCloud Sync** uploads every item, section, shopping-list entry, and saved
/// list into the `Household` zone of the user's private database.
/// **1c:** before uploading, check whether iCloud already has a library; if so, ask, then replace
/// this device's library with a full download. Later downloaded changes are merged in.
/// **1d:** every user edit is reported by `GroceryStore.onLibraryChange` and queued for upload;
/// other devices learn about it via CloudKit push (plus a fetch whenever the app comes to the front).
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

        var id: Self { self }
    }

    @Published var enablePrompt: EnablePrompt?

    /// All household data lives in one custom zone (Phase 2 shares this whole zone).
    static let zoneID = CKRecordZone.ID(zoneName: "Household", ownerName: CKCurrentUserDefaultName)

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

    private init() {}

    // MARK: - Lifecycle (called from ShoplisterApp)

    /// Call once at launch. Starts syncing if the switch is already on.
    func attach(store: GroceryStore) {
        guard self.store == nil else { return }
        self.store = store
        systemFieldsByRecordName = Self.loadSystemFields()
        if UserDefaults.standard.bool(forKey: AppICloudSync.storageKey) {
            startEngine()
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
            enablePrompt = nil
            isReplacingLocalLibrary = false
            replacementBuffer = []
            stopEngine()
        }
    }

    /// Turning sync on: upload if iCloud is empty, otherwise ask before replacing this device's library.
    private func checkICloudThenEnable() async {
        do {
            if try await iCloudHasLibrary() {
                enablePrompt = .replaceLocalLibrary
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
        let database = CKContainer(identifier: AppICloudSync.containerIdentifier).privateCloudDatabase
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
        Self.deleteLocalSyncFiles()
        systemFieldsByRecordName = [:]
        isReplacingLocalLibrary = true
        replacementBuffer = []
        startEngine()
        status = .syncing
        Task {
            do {
                try await engine?.fetchChanges()
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

    private func turnSwitchOff() {
        // ShoplisterApp observes this key and calls `setEnabled(false)`.
        UserDefaults.standard.set(false, forKey: AppICloudSync.storageKey)
        status = .off
    }

    private func startEngine() {
        guard engine == nil else { return }
        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: AppICloudSync.containerIdentifier).privateCloudDatabase,
            stateSerialization: Self.loadEngineState(),
            delegate: self
        )
        engine = CKSyncEngine(configuration)
        // Lets CloudKit's silent pushes reach the app so other devices' edits arrive promptly.
        UIApplication.shared.registerForRemoteNotifications()
        updateStatusFromPendingChanges()
        logger.info("Sync engine started")
    }

    private func stopEngine() {
        guard let engine else {
            status = .off
            return
        }
        self.engine = nil
        status = .off
        Task { await engine.cancelOperations() }
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
        engine.state.add(pendingRecordZoneChanges: saves.map { .saveRecord($0) } + deletes.map { .deleteRecord($0) })
        if status != .failed {
            status = .syncing
        }
    }

    /// Checks iCloud for other devices' changes now (called when the app comes to the front).
    func fetchNow() {
        guard let engine else { return }
        Task {
            do {
                try await engine.fetchChanges()
            } catch {
                logger.info("Foreground fetch didn't complete: \(error.localizedDescription)")
            }
        }
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
        // An unsent local edit is newer than whatever iCloud has; skip that record's download so the
        // edit isn't briefly undone (it uploads next and wins — "last to sync wins").
        let pendingSaveNames: Set<String> = Set(
            (engine?.state.pendingRecordZoneChanges ?? []).compactMap { change in
                if case .saveRecord(let id) = change { return id.recordName }
                return nil
            }
        )
        let records = fetched.modifications.map(\.record)
            .filter { !pendingSaveNames.contains($0.recordID.recordName) }
        for record in records {
            systemFieldsByRecordName[record.recordID.recordName] = Self.encodeSystemFields(of: record)
        }
        for deletion in fetched.deletions {
            systemFieldsByRecordName[deletion.recordID.recordName] = nil
        }
        Self.saveSystemFields(systemFieldsByRecordName)

        if isReplacingLocalLibrary {
            replacementBuffer += records
            return
        }
        var changes = Self.libraryChanges(from: records)
        for deletion in fetched.deletions {
            Self.addDeletion(recordName: deletion.recordID.recordName, to: &changes)
        }
        store?.applySyncedChanges(changes, replacingActiveLibrary: false)
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
            case .zoneNotFound:
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                systemFieldsByRecordName[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                // Our stored stamp points at a record the server no longer has; upload it fresh.
                systemFieldsByRecordName[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                // The engine retries these on its own.
                break
            default:
                hadPermanentFailure = true
                logger.error("Couldn't save \(recordID.recordName): \(failure.error.localizedDescription)")
            }
        }
        if !retry.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: retry)
        }
        Self.saveSystemFields(systemFieldsByRecordName)
        if hadPermanentFailure {
            status = .failed
        }
    }

    private func updateStatusFromPendingChanges() {
        guard let engine else {
            status = .off
            return
        }
        if status == .failed || isReplacingLocalLibrary { return }
        status = engine.state.pendingRecordZoneChanges.isEmpty
            && engine.state.pendingDatabaseChanges.isEmpty ? .upToDate : .syncing
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
