import Foundation

/// Saves each language's item library (catalog, sections, shopping list, saved lists) as a JSON file
/// in the App Group container: `Library/english.json`, `Library/hebrew.json`.
///
/// Household sync plan, Phase 0a: replaces UserDefaults as the library's home. `GroceryStore` owns
/// encoding/decoding and the migration rules; this type only reads, writes, and sets bad files aside.
enum LibraryFileStore {
    private static let directoryName = "Library"

    /// `nil` when the App Group container isn't available (signing/provisioning problem).
    /// Callers then keep using the UserDefaults copy, exactly like before Phase 0.
    private static var directoryURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareExtensionAppGroupSupport.appGroupIdentifier
        ) else { return nil }
        let directory = container.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fileURL(for language: AppContentLanguage) -> URL? {
        directoryURL?.appendingPathComponent("\(language.rawValue).json")
    }

    /// The saved file's bytes, or `nil` if there is no file yet (first launch after updating).
    static func load(_ language: AppContentLanguage) -> Data? {
        guard let url = fileURL(for: language) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Atomic write: a crash mid-save leaves the previous file intact, never a half-written one.
    @discardableResult
    static func save(_ data: Data, for language: AppContentLanguage) -> Bool {
        guard let url = fileURL(for: language) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Moves an unreadable file aside (e.g. `english.corrupt-2026-11-14T15-55-00Z.json`) instead of
    /// overwriting or deleting it, so the data can still be recovered by hand.
    static func setAsideUnreadableFile(_ language: AppContentLanguage) {
        guard let url = fileURL(for: language),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: destination)
    }
}
