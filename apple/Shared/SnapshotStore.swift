import Foundation

enum SnapshotStore {
    private static var url: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("snapshot.json")
    }
    static func load() -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? Snapshot.decode(data)
    }
    static func save(_ snapshot: Snapshot) throws {
        guard let url else { throw SnapshotError.invalid }
        try snapshot.sanitized.encoded().write(to: url, options: .atomic)
    }
    static func clear() { if let url { try? FileManager.default.removeItem(at: url) } }
}
