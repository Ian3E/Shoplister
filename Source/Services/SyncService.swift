import CloudKit
import Foundation
import os

/// iCloud sync for the active language's library (household sync plan, Phase 1).
///
/// **1b (this step): upload only.** Turning on **iCloud Sync** uploads every item, section,
/// shopping-list entry, and saved list into the `Household` zone of the user's private database.
/// Receiving changes (1c) and sending each edit as it happens (1d) come next.
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

    private init() {}

    // MARK: - Lifecycle (called from ShoplisterApp)

    /// Call once at launch. Starts syncing if the switch is already on.
    func attach(store: GroceryStore) {
        self.store = store
        systemFieldsByRecordName = Self.loadSystemFields()
        if UserDefaults.standard.bool(forKey: AppICloudSync.storageKey) {
            startEngine()
        }
    }

    /// Called when the **iCloud Sync** switch changes.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            startEngine()
            queueFullUpload()
        } else {
            stopEngine()
        }
    }

    private func startEngine() {
        guard engine == nil else { return }
        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: AppICloudSync.containerIdentifier).privateCloudDatabase,
            stateSerialization: Self.loadEngineState(),
            delegate: self
        )
        engine = CKSyncEngine(configuration)
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

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // Ignore events from an engine we've already stopped.
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            Self.saveEngineState(update.stateSerialization)
        case .accountChange(let change):
            logger.info("iCloud account changed: \(String(describing: change))")
        case .willSendChanges:
            status = .syncing
        case .sentRecordZoneChanges(let sent):
            handleSentRecordZoneChanges(sent, syncEngine: syncEngine)
        case .didSendChanges:
            updateStatusFromPendingChanges()
        default:
            // Fetching (1c) and database-level events aren't used yet.
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

    // MARK: - Sent changes

    private func handleSentRecordZoneChanges(
        _ sent: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) {
        for record in sent.savedRecords {
            systemFieldsByRecordName[record.recordID.recordName] = Self.encodeSystemFields(of: record)
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
        if status == .failed { return }
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
