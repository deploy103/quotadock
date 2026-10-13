import Foundation

enum RefreshSettings {
    static let foregroundKey = "foregroundAutoRefresh"
    static func foregroundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: foregroundKey) == nil || defaults.bool(forKey: foregroundKey)
    }
}

enum SnapshotStore {
    static let maximumPayloadBytes = 256 * 1024
    private static var url: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("snapshot.json")
    }
    static func load() -> Snapshot? {
        guard let url,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size <= maximumPayloadBytes,
              let data = try? Data(contentsOf: url), data.count <= maximumPayloadBytes else { return nil }
        return try? Snapshot.decode(data).sanitized
    }
    // Local persistence time, not a provider observation or delivery acknowledgement.
    static var savedAt: Date? {
        guard let url else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    static func save(_ snapshot: Snapshot) throws {
        guard let url else { throw SnapshotError.invalid }
        let data = try snapshot.sanitized.encoded()
        guard data.count <= maximumPayloadBytes else { throw SnapshotError.invalid }
        // Validate before replacing a usable cache, including the schema version.
        _ = try Snapshot.decode(data)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear() { if let url { try? FileManager.default.removeItem(at: url) } }
}
