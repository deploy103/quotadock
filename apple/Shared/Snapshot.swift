import Foundation

struct Snapshot: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let demo: Bool
    let providers: [Provider]

    static func decode(_ data: Data) throws -> Snapshot {
        guard data.count <= 256 * 1024 else { throw SnapshotError.invalid }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [[String: Any]] else { throw SnapshotError.invalid }
        for provider in providers {
            guard ["id", "name", "plan", "state", "source", "message", "observedAt", "windows"].allSatisfy({ provider.keys.contains($0) }),
                  let windows = provider["windows"] as? [[String: Any]] else { throw SnapshotError.invalid }
            for window in windows {
                guard ["id", "label", "remainingPercent", "resetsAt"].allSatisfy({ window.keys.contains($0) }) else { throw SnapshotError.invalid }
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw SnapshotError.invalid }
            return date
        }
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.schemaVersion == 1 else { throw SnapshotError.invalid }
        return snapshot
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Synthesized Codable omits nil keys; contract v1 requires explicit null.
        let data = try encoder.encode(self)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var providers = root["providers"] as? [[String: Any]] else { throw SnapshotError.invalid }
        for index in providers.indices {
            for key in ["plan", "message", "observedAt"] where providers[index][key] == nil {
                providers[index][key] = NSNull()
            }
            var windows = providers[index]["windows"] as? [[String: Any]] ?? []
            for window in windows.indices {
                for key in ["remainingPercent", "resetsAt"] where windows[window][key] == nil {
                    windows[window][key] = NSNull()
                }
            }
            providers[index]["windows"] = windows
        }
        root["providers"] = providers
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    // No arbitrary upstream message is persisted or forwarded to Watch.
    var sanitized: Snapshot {
        Snapshot(schemaVersion: schemaVersion, generatedAt: generatedAt, demo: demo,
                 providers: providers.map { provider in
            Provider(id: provider.id, name: provider.id.displayName, plan: provider.plan,
                     state: provider.state, source: provider.source,
                     message: provider.state == .available ? nil : "Usage unavailable",
                     observedAt: provider.observedAt, windows: provider.windows.map { window in
                QuotaWindow(id: window.id, label: window.label,
                            remainingPercent: provider.state == .available ? window.remainingPercent : nil,
                            resetsAt: window.resetsAt)
            })
        })
    }

    static var preview: Snapshot {
        Snapshot(schemaVersion: 1, generatedAt: Date(), demo: true, providers: [
            Provider(id: .claude, name: "Claude", plan: "Max", state: .available, source: .demo,
                     message: nil, observedAt: Date(), windows: [QuotaWindow(id: "primary", label: "Session", remainingPercent: 72, resetsAt: nil)]),
            Provider(id: .codex, name: "Codex", plan: "ChatGPT Plus", state: .available, source: .demo,
                     message: nil, observedAt: Date(), windows: [QuotaWindow(id: "weekly", label: "Weekly", remainingPercent: 43, resetsAt: nil)]),
            Provider(id: .gemini, name: "Gemini", plan: nil, state: .unavailable, source: .demo,
                     message: "Usage unavailable", observedAt: nil, windows: [QuotaWindow(id: "pro", label: "Pro tier", remainingPercent: nil, resetsAt: nil)]),
            Provider(id: .grok, name: "Grok", plan: nil, state: .unavailable, source: .demo,
                     message: "Usage unavailable", observedAt: nil, windows: [])
        ])
    }
}

enum SnapshotError: Error { case invalid, insecureURL, response, unpaired }
enum ProviderID: String, Codable {
    case claude, codex, gemini, grok
    var displayName: String { rawValue == "codex" ? "Codex" : rawValue.capitalized }
}
enum ProviderState: String, Codable { case available, unavailable, error }
enum QuotaSource: String, Codable { case codexbar, demo }

struct Provider: Codable, Identifiable, Equatable {
    let id: ProviderID
    let name: String
    let plan: String?
    let state: ProviderState
    let source: QuotaSource
    let message: String?
    let observedAt: Date?
    let windows: [QuotaWindow]

    func isStale(at date: Date = Date()) -> Bool {
        guard let observedAt else { return true }
        return date.timeIntervalSince(observedAt) > 15 * 60
    }
}

struct QuotaWindow: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let remainingPercent: Double?
    let resetsAt: Date?
    var clampedRemaining: Double? { remainingPercent.map { min(100, max(0, $0)) } }
}
