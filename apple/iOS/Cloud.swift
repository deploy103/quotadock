import Foundation
import Security
import AuthenticationServices
import SwiftUI
import UIKit

struct CloudAccount: Decodable, Identifiable {
    let id: UUID
    let provider: ProviderID
}

struct CloudMe: Decodable {
    enum Tier: String, Decodable { case free, plus, pro }
    struct LiveSession: Decodable {
        let accountIds: [UUID]
        let startedAt: String?
        let deadline: String?
        var deadlineDate: Date? {
            guard let deadline else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: deadline)
        }
    }
    struct Limits: Decodable {
        let accounts: Int?
        let autoMinutes: Int
        let allowedAutoMinutes: [Int]
        let earlyBatchesPerDay: Int?
        let live: Bool
    }
    let tier: Tier
    let limits: Limits
    let autoMinutes: Int
    let backgroundCollection: Bool?
    let earlyBatchesUsed: Int
    let liveSessionsUsed: Int
    let liveSessionsLimit: Int
    let liveSession: LiveSession?
    let purchasesAvailable: Bool
    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        let intervals = value.tier == .free ? [120] : value.tier == .plus ? [60] : [20, 30, 60, 120]
        guard value.limits.accounts == (value.tier == .free ? 3 : value.tier == .plus ? 10 : nil),
              value.limits.allowedAutoMinutes == intervals,
              intervals.contains(value.autoMinutes), value.autoMinutes == value.limits.autoMinutes,
              value.limits.live == (value.tier != .free),
              value.limits.earlyBatchesPerDay == (value.tier == .free ? 10 : nil),
              value.earlyBatchesUsed >= 0, value.liveSessionsUsed >= 0,
              value.liveSessionsLimit == (value.tier == .free ? 0 : 5) else { throw SnapshotError.invalid }
        if let live = value.liveSession {
            guard value.tier != .free, !live.accountIds.isEmpty, live.accountIds.count <= 50,
                  Set(live.accountIds).count == live.accountIds.count,
                  (live.startedAt == nil) == (live.deadline == nil),
                  live.deadline == nil || live.deadlineDate != nil else { throw SnapshotError.invalid }
        }
        return value
    }
    var budget: String {
        "\(tier.rawValue.capitalized) · \(limits.accounts.map(String.init) ?? "unlimited") slots · auto \(autoMinutes)m · early \(limits.earlyBatchesPerDay.map { "\(earlyBatchesUsed)/\($0) KST day" } ?? "unlimited") · Live \(liveSessionsUsed)/\(liveSessionsLimit) \(tier == .plus ? "subscription period" : "KST day")"
    }
}

struct CloudCollector: Decodable, Identifiable {
    let id: UUID
    let accountIds: [UUID]
    let expiresAt: Date
    private enum CodingKeys: String, CodingKey { case id, accountIds, expiresAt }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        accountIds = try values.decode([UUID].self, forKey: .accountIds)
        let timestamp = try values.decode(String.self, forKey: .expiresAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: timestamp)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: timestamp),
              accountIds.count <= 50, Set(accountIds).count == accountIds.count else { throw SnapshotError.invalid }
        expiresAt = date
    }
}

enum CollectorApproval {
    static func valid(code: String, selected: Set<UUID>, slots: [CloudAccount]) -> Bool {
        return code.count == 8 && code.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) }
            && CloudBatchSelection.valid(Array(selected), slots: slots)
    }
}

// In-memory only: selection is not an identity or a persisted credential.
struct CloudBatchSelection {
    private(set) var ids: [UUID] = []
    private var initialized = false
    static func valid(_ ids: [UUID], slots: [CloudAccount]) -> Bool {
        !ids.isEmpty && ids.count <= 50 && Set(ids).count == ids.count
            && Set(ids).isSubset(of: Set(slots.map(\.id)))
    }
    mutating func reconcile(slots: [CloudAccount]) {
        let owned = Set(slots.map(\.id))
        if !initialized, !slots.isEmpty {
            ids = Array(slots.map(\.id).prefix(50))
            initialized = true
        } else {
            ids.removeAll { !owned.contains($0) }
        }
    }
    mutating func select(_ ids: [UUID], slots: [CloudAccount]) -> Bool {
        guard ids.isEmpty || Self.valid(ids, slots: slots) else { return false }
        self.ids = ids
        initialized = true
        return true
    }
}

struct CloudSnapshot: Codable {
    struct Account: Codable, Identifiable {
        let accountId: UUID
        var id: UUID { accountId }
        let provider: ProviderID
        let plan: String?
        let state: ProviderState
        let source: QuotaSource
        let observedAt: Date?
        let windows: [QuotaWindow]
        let lastError: String?
        var reading: Provider {
            Provider(id: provider, name: provider.displayName, plan: plan, state: state,
                     source: source, message: nil, observedAt: observedAt, windows: windows)
        }
    }
    let schemaVersion: Int
    let generatedAt: Date
    let demo: Bool
    let accounts: [Account]
    static func decode(_ data: Data) throws -> CloudSnapshot {
        guard data.count <= 256 * 1024 else { throw SnapshotError.invalid }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw SnapshotError.invalid }
            return date
        }
        let result = try decoder.decode(Self.self, from: data)
        guard result.schemaVersion == 2,
              Set(result.accounts.map(\.id)).count == result.accounts.count else { throw SnapshotError.invalid }
        return result
    }
    // Small surfaces intentionally show only the first server-listed slot per provider.
    var smallSurfaceSnapshot: Snapshot {
        var seen = Set<ProviderID>()
        return Snapshot(schemaVersion: 1, generatedAt: generatedAt, demo: demo,
                        providers: accounts.filter { seen.insert($0.provider).inserted }.map(\.reading)).sanitized
    }
    func cacheData() throws -> Data {
        let clean = CloudSnapshot(schemaVersion: schemaVersion, generatedAt: generatedAt, demo: demo,
            accounts: accounts.map { account in
                let reading = Snapshot(schemaVersion: 1, generatedAt: generatedAt, demo: demo,
                                       providers: [account.reading]).sanitized.providers[0]
                return Account(accountId: account.id, provider: account.provider, plan: reading.plan,
                    state: reading.state, source: reading.source, observedAt: reading.observedAt,
                    windows: reading.windows, lastError: account.lastError == nil ? nil : "collection_unavailable")
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var value = encoder.singleValueContainer()
            try value.encode(formatter.string(from: date))
        }
        return try encoder.encode(clean)
    }
}

// Full slot list is local to the iPhone. Only the reduced sanitized v1 projection
// is exported to App Group / Watch. Neither cache contains a session or identity.
enum CloudCache {
    static var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("QuotaDock-cloud-snapshot.json")
    }
    static func load() -> CloudSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? CloudSnapshot.decode(data)
    }
    static func save(_ snapshot: CloudSnapshot) {
        guard !snapshot.demo, let url, let data = try? snapshot.cacheData() else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    static func clear() { if let url { try? FileManager.default.removeItem(at: url) } }
}

struct CloudSession: Codable {
    let baseURL: URL
    let token: String
    let expiresAt: Date
}

enum CloudSessionStore {
    // Deliberately no shared access group: widgets and Watch cannot read this session.
    static var query: [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "QuotaDock.cloud.v2", kSecAttrAccount as String: "session"]
        if let group = Bundle.main.object(forInfoDictionaryKey: "CloudKeychainGroup") as? String {
            result[kSecAttrAccessGroup as String] = group
        }
        return result
    }
    static func load() -> CloudSession? {
        var q = query
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(CloudSession.self, from: data) else { return nil }
        return session
    }
    static func save(_ session: CloudSession) throws {
        remove()
        var q = query
        q[kSecValueData as String] = try JSONEncoder().encode(session)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw SnapshotError.unpaired }
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}

final class CloudRequestScope {
    private let lock = NSLock()
    private var sessions: [UUID: URLSession] = [:]
    func insert(_ session: URLSession, id: UUID) { lock.lock(); defer { lock.unlock() }; sessions[id] = session }
    func remove(_ id: UUID) { lock.lock(); defer { lock.unlock() }; sessions.removeValue(forKey: id) }
    func cancel() {
        lock.lock()
        let active = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        active.forEach { $0.invalidateAndCancel() }
    }
}

struct CloudClient {
    let baseURL: URL
    let token: String?
    let scope: CloudRequestScope?
    init(baseURL: String, token: String? = nil, scope: CloudRequestScope? = nil) throws {
        let pairing = try Pairing(baseURL: baseURL, token: token ?? "validation")
        self.baseURL = pairing.endpoint.deletingLastPathComponent().deletingLastPathComponent()
        self.token = token
        self.scope = scope
    }
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 20) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = min(15, timeout)
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: HTTPSRedirectPolicy(), delegateQueue: nil)
        let requestID = UUID()
        scope?.insert(session, id: requestID)
        defer { scope?.remove(requestID); session.invalidateAndCancel() }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            guard (request.httpBody?.count ?? 0) <= 32 * 1024 else { throw SnapshotError.invalid }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw SnapshotError.response
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 256 * 1024 else { throw SnapshotError.invalid }
            data.append(byte)
        }
        return data
    }
}

@MainActor
final class CloudModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var session = CloudSessionStore.load()
    @Published var snapshot = CloudSessionStore.load() == nil ? nil : CloudCache.load()
    @Published var slots: [CloudAccount] = [] {
        didSet { refreshSelection.reconcile(slots: slots) }
    }
    @Published private(set) var refreshSelection = CloudBatchSelection()
    var selectionLocked: Bool { liveEnabled || me?.liveSession != nil || !liveSlotIDs.isEmpty }
    func selectRefreshSlots(_ ids: [UUID]) {
        guard !busy, !selectionLocked else { return }
        if !refreshSelection.select(ids, slots: slots) {
            status = "Select distinct owned slots, at most 50 per batch."
        }
    }
    @Published var status = "Cloud is optional. A local collector is required; this phone cannot collect provider quotas."
    @Published var budget = ""
    @Published var busy = false
    @Published var me: CloudMe?
    @Published var collectors: [CloudCollector] = []
    @Published var liveEnabled = false
    @Published var liveDeadline: Date?
    private var liveTask: Task<Void, Never>?
    private var liveStartedAt: Date?
    private var liveSlotIDs: [UUID] = []
    private var lastLiveRequest: Date?
    private var reading = false
    private let requests = CloudRequestScope()
    var foreground = true {
        didSet {
            if !foreground { pollingTask?.cancel(); liveTask?.cancel(); requests.cancel() }
            else if liveEnabled { scheduleLive() }
        }
    }
    var revision = 0
    var onSwitch: (() -> Void)?
    var onSnapshot: ((Snapshot) -> Void)?
    private var challenge: (id: String, base: String, revision: Int)?
    private var controller: ASAuthorizationController?
    private var pollingTask: Task<Void, Never>?
    var client: CloudClient? { session.flatMap { try? CloudClient(baseURL: $0.baseURL.absoluteString, token: $0.token, scope: requests) } }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(protectedDataUnavailable), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    }
    @objc private func protectedDataUnavailable() { foreground = false }

    func connect(base: String, quotaStorageConsent: Bool, collectorProcessingConsent: Bool) async {
        guard !busy, !reading, foreground else { return }
        guard quotaStorageConsent, collectorProcessingConsent else {
            status = "Consent required for quota storage and local collector processing. No sign-in started."
            return
        }
        busy = true
        let current = revision
        do {
            let client = try CloudClient(baseURL: base, scope: requests)
            let data = try await client.request("v2/auth/challenge", method: "POST", body: [:])
            struct Challenge: Decodable { let challengeId: String; let nonce: String }
            let response = try JSONDecoder().decode(Challenge.self, from: data)
            guard current == revision else { return }
            challenge = (response.challengeId, base, current)
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            request.nonce = response.nonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        } catch {
            if current == revision {
                status = "Cloud sign-in unavailable. Check HTTPS/DNS, server Apple configuration and your signed Apple capability."
                busy = false
            }
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard self.controller === controller else { return }
        challenge = nil; self.controller = nil; busy = false
        status = "Apple authorization did not complete. No cloud account was connected."
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard self.controller === controller else { return }
        guard let challenge, let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let jwt = String(data: data, encoding: .utf8) else {
            busy = false; status = "Apple did not return an identity token."; return
        }
        self.challenge = nil; self.controller = nil
        Task {
            defer { if revision == challenge.revision { busy = false } }
            do {
                let client = try CloudClient(baseURL: challenge.base, scope: requests)
                let data = try await client.request("v2/auth/apple", method: "POST", body: [
                    "challengeId": challenge.id, "identityToken": jwt,
                    "consent": ["quotaStorage": true, "collectorProcessing": true]])
                struct Login: Decodable { let sessionToken: String; let expiresIn: Int }
                let login = try JSONDecoder().decode(Login.self, from: data)
                guard login.sessionToken.count == 43,
                      login.sessionToken.unicodeScalars.allSatisfy({
                          CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").contains($0)
                      }), (1...3600).contains(login.expiresIn) else { throw SnapshotError.invalid }
                guard revision == challenge.revision else {
                    let stale = try CloudClient(baseURL: challenge.base, token: login.sessionToken)
                    _ = try? await stale.request("v2/auth/logout", method: "POST", body: [:])
                    return
                }
                let next = CloudSession(baseURL: client.baseURL, token: login.sessionToken,
                                        expiresAt: Date().addingTimeInterval(Double(min(login.expiresIn, 3600))))
                onSwitch?()
                try CloudSessionStore.save(next)
                liveTask?.cancel(); liveEnabled = false; liveDeadline = nil; liveStartedAt = nil
                liveSlotIDs = []; lastLiveRequest = nil; me = nil; slots = []
                refreshSelection = CloudBatchSelection()
                PairingStore.remove(); session = next
                await read(internalWork: true)
            } catch { if revision == challenge.revision { status = "Server sign-in failed. No cloud session saved." } }
        }
    }
    func clear() {
        pollingTask?.cancel()
        requests.cancel()
        liveTask?.cancel(); liveEnabled = false; liveDeadline = nil; liveStartedAt = nil; me = nil; collectors = []
        liveSlotIDs = []; lastLiveRequest = nil
        busy = false
        revision += 1; challenge = nil; controller = nil; session = nil; snapshot = nil; slots = []; budget = ""
        refreshSelection = CloudBatchSelection()
        CloudSessionStore.remove(); CloudCache.clear(); onSwitch?()
    }
    func disconnect(delete: Bool) async {
        let old = client
        clear() // Revoke local authority immediately, including in-flight completions.
        let current = revision
        do {
            _ = try await old?.request(delete ? "v2/me" : "v2/auth/logout", method: delete ? "DELETE" : "POST", body: [:])
            guard revision == current else { return }
            status = delete ? "Cloud account erased." : "Signed out."
        } catch { if revision == current { status = "Local session cleared; server erasure/revocation could not be confirmed. Reconnect to retry erasure. Session expires within one hour." } }
    }
    func read(internalWork: Bool = false) async {
        guard let client, !reading, (!busy || internalWork), foreground, !Task.isCancelled else { return }
        reading = true
        defer { reading = false }
        let current = revision
        do {
            let me = try await client.request("v2/me")
            guard current == revision, foreground, !Task.isCancelled else { return }
            let accounts = try await client.request("v2/accounts")
            guard current == revision, foreground, !Task.isCancelled else { return }
            let data = try await client.request("v2/snapshot")
            guard current == revision, foreground, !Task.isCancelled else { return }
            let verified = try CloudMe.decode(me)
            struct Collectors: Decodable { let collectors: [CloudCollector] }
            let paired = try? JSONDecoder().decode(Collectors.self, from: try await client.request("v2/collectors"))
            struct Accounts: Decodable { let accounts: [CloudAccount] }
            let next = try CloudSnapshot.decode(data)
            let nextSlots = try JSONDecoder().decode(Accounts.self, from: accounts).accounts
            guard current == revision, session != nil, foreground, !Task.isCancelled else { return }
            slots = nextSlots; snapshot = next
            if liveEnabled, !CloudBatchSelection.valid(liveSlotIDs, slots: nextSlots) {
                liveEnabled = false; liveTask?.cancel()
            }
            self.me = verified; collectors = paired?.collectors ?? []
            reconcileLive(verified: verified)
            CloudCache.save(next)
            budget = verified.budget
            if !verified.limits.live { liveEnabled = false; liveTask?.cancel() }
            onSnapshot?(next.smallSurfaceSnapshot)
            status = "Cached server observations. Local collector required for new readings."
        } catch { if current == revision { status = "Cloud read unavailable or session expired. Original observations retained; sign in again if needed." } }
    }
    func mutate(path: String, method: String, body: [String: Any] = [:]) async {
        guard let client, !busy, !reading, !liveEnabled else { return }
        busy = true
        var current = revision
        defer { if current == revision { busy = false } }
        do {
            _ = try await client.request(path, method: method, body: body)
            guard current == revision else { return }
            if path == "v2/live/stop" { liveDeadline = nil; liveStartedAt = nil; liveSlotIDs = []; lastLiveRequest = nil }
            revision += 1
            current = revision
            if method == "DELETE", path.hasPrefix("v2/accounts/") {
                snapshot = nil
                slots.removeAll { path.hasSuffix($0.id.uuidString) }
                onSwitch?()
            }
            await read(internalWork: true)
        } catch { if current == revision { status = "Request refused or unavailable. Server slot, spacing and Free budget limits apply." } }
    }
    func refresh(force: Bool, live: Bool = false) async {
        guard !busy, !reading, foreground, !Task.isCancelled, !liveEnabled || live else { return }
        guard let client, !slots.isEmpty else { await read(); return }
        let ids = live ? liveSlotIDs : refreshSelection.ids
        guard CloudBatchSelection.valid(ids, slots: slots) else {
            status = "Select 1–50 distinct owned slots per refresh."; return
        }
        busy = true
        let current = revision
        defer { if current == revision { busy = false } }
        do {
            if live { lastLiveRequest = Date() }
            let data = try await client.request("v2/refresh", method: "POST", body: [
                "accountIds": ids.map(\.uuidString), "mode": live ? "live" : force ? "force" : "auto",
                "idempotencyKey": UUID().uuidString])
            let job = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard current == revision, foreground, !Task.isCancelled else { return }
            await read(internalWork: true)
            guard current == revision, foreground else { return }
            if job?["status"] as? String == "pending" {
                status = "Waiting for local collector — quota has not been updated."
                let task = Task { await poll(client: client, current: current, live: live) }
                pollingTask = task
                await task.value
                if current == revision { pollingTask = nil }
            }
        } catch { if current == revision { status = "Refresh unavailable. Old observations retained; verified tier limits or collector availability may apply." } }
    }

    func startLive() {
        guard me?.limits.live == true, !busy, !reading else { return }
        guard liveDeadline.map({ Date() < $0 }) ?? true else { status = "Stop the previous Live session before starting another."; return }
        if let active = me?.liveSession {
            liveSlotIDs = active.accountIds
            liveDeadline = active.deadlineDate
        }
        if liveSlotIDs.isEmpty { liveSlotIDs = refreshSelection.ids }
        guard CloudBatchSelection.valid(liveSlotIDs, slots: slots) else {
            status = "Live requires 1–50 distinct owned slots. Stop an obsolete session before changing slots."; return
        }
        if liveStartedAt == nil { liveStartedAt = Date() }
        liveEnabled = true
        scheduleLive()
    }

    func stopLive() async {
        let current = revision
        liveEnabled = false; liveTask?.cancel(); pollingTask?.cancel()
        for _ in 0..<25 where busy || reading {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard current == revision else { return }
        await mutate(path: "v2/live/stop", method: "POST")
    }

    private func scheduleLive() {
        liveTask?.cancel()
        let current = revision
        liveTask = Task {
            while !Task.isCancelled, foreground, liveEnabled, current == revision {
                if let liveDeadline, Date() >= liveDeadline { liveEnabled = false; return }
                await read()
                guard liveEnabled, foreground, current == revision, !Task.isCancelled else { return }
                if let lastLiveRequest {
                    let wait = 60 - Date().timeIntervalSince(lastLiveRequest)
                    if wait > 0 {
                        do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                        catch { return }
                    }
                }
                guard liveEnabled, foreground, current == revision, !Task.isCancelled else { return }
                if let liveDeadline, Date() >= liveDeadline { liveEnabled = false; return }
                // Failed first collection has no server deadline or charge.
                // Bound unconfirmed attempts locally rather than run indefinitely.
                if liveDeadline == nil, let liveStartedAt, Date().timeIntervalSince(liveStartedAt) >= 1800 {
                    liveEnabled = false; status = "Live deadline unconfirmed. Checks paused; stop before starting a new session."; return
                }
                let started = Date()
                await refresh(force: false, live: true)
                if liveDeadline == nil {
                    liveEnabled = false
                    status = "Live deadline unconfirmed. Automatic checks paused; explicitly resume to retry. The server alone charges fresh successes."
                    return
                }
                do { try await Task.sleep(nanoseconds: UInt64(max(1, 60 - Date().timeIntervalSince(started)) * 1_000_000_000)) }
                catch { return }
            }
        }
    }

    private func reconcileLive(verified: CloudMe) {
        guard liveEnabled else { return }
        guard let active = verified.liveSession else {
            if lastLiveRequest == nil && liveDeadline == nil { return }
            liveEnabled = false; liveTask?.cancel(); return
        }
        guard Set(active.accountIds) == Set(liveSlotIDs) else {
            liveEnabled = false; liveTask?.cancel(); return
        }
        // Source observation time is not the server's first completion time.
        // Always use the authoritative deadline, including cross-device resumes.
        liveDeadline = active.deadlineDate
    }

    private func poll(client: CloudClient, current: Int, live: Bool) async {
        // Cancellation on leaving foreground cancels sleeps and URLSession async requests.
        let deadline = Date().addingTimeInterval(60)
        let original = snapshot?.accounts.map(\.observedAt)
        do {
            for _ in 0..<12 {
                let wait = min(5, deadline.timeIntervalSinceNow)
                guard wait > 0 else { break }
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard foreground, current == revision, session != nil else { return }
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { break }
                let data = try await client.request("v2/snapshot", timeout: min(20, remaining))
                try Task.checkCancellation()
                guard foreground, current == revision, session != nil else { return }
                let next = try CloudSnapshot.decode(data)
                snapshot = next; CloudCache.save(next); onSnapshot?(next.smallSurfaceSnapshot)
                if next.accounts.map(\.observedAt) != original {
                    if live, liveDeadline == nil {
                        let verified = try CloudMe.decode(try await client.request("v2/me", timeout: min(20, max(1, deadline.timeIntervalSinceNow))))
                        guard current == revision, foreground, !Task.isCancelled else { return }
                        me = verified; budget = verified.budget
                        reconcileLive(verified: verified)
                        if liveDeadline == nil {
                            // Do not keep issuing requests that might silently start a new session.
                            liveEnabled = false
                            status = "Live success/deadline cannot be confirmed. Checks paused; server owns session accounting. Stop before a new session."
                            return
                        }
                    }
                    status = "New collector observation received. See original observation time."
                    return
                }
                status = "Collector requested; showing cached observations. Polling ends after 60 seconds."
            }
            status = "Collector wait timed out. Cached observations retained; retry later."
        } catch {
            if current == revision {
                status = "Collector wait stopped or unavailable. Original observations retained."
            }
        }
    }
}

struct CloudReadingsView: View {
    @ObservedObject var model: CloudModel
    var body: some View {
        VStack(alignment: .leading) {
            Text(model.status).font(.caption)
            Text(model.budget).font(.caption)
            ForEach(model.snapshot?.accounts ?? []) { account in
                Text("\(account.provider.displayName) · \(account.id.uuidString.prefix(8))").font(.caption)
                ProviderCard(provider: account.reading, demo: model.snapshot?.demo == true)
                if account.lastError != nil { Text("Last collection unavailable; original observation retained.").font(.caption) }
            }
            Text("Watch/widgets show the first server-listed account per provider only, from sanitized cache.").font(.caption)
        }
    }
}

struct CloudBatchView: View {
    let slots: [CloudAccount]
    let ids: [UUID]
    let locked: Bool
    let select: ([UUID]) -> Void
    var body: some View {
        Section("Refresh batch · \(ids.count)/50") {
            Text("Force, foreground auto and new Live use these slots. First 50 are selected initially; registration remains tier-dependent. Stop Live before changing its batch; resumed Live keeps the server's slot set.").font(.caption)
            ForEach(slots) { slot in
                Toggle(isOn: Binding(get: {
                    ids.contains(slot.id)
                }, set: { enabled in
                    var next = ids
                    if enabled { next.append(slot.id) } else { next.removeAll { $0 == slot.id } }
                    select(next)
                })) {
                    HStack {
                        ProviderIcon(id: slot.provider)
                        Text("\(slot.provider.displayName) · \(slot.id.uuidString.prefix(8))")
                    }
                }.disabled(locked || (!ids.contains(slot.id) && ids.count >= 50))
            }
        }
    }
}

#if DEBUG
// Isolated UI sample: no Apple identity, session, entitlement or network client.
struct CloudBatchPreview: View {
    @State private var selection: [UUID] = []
    private let slots = [ProviderID.claude, .codex, .codex, .gemini, .grok].enumerated().map { index, provider in
        CloudAccount(id: UUID(uuidString: "0000000\(index)-0000-4000-8000-000000000000")!, provider: provider)
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("DEMO · selection sample only, no account or server").font(.headline)
                CloudBatchView(slots: slots, ids: selection, locked: false) { ids in
                    if ids.isEmpty || CloudBatchSelection.valid(ids, slots: slots) { selection = ids }
                }
            }.navigationTitle("Refresh selection")
                .onAppear { selection = [slots[0].id, slots[2].id] }
        }
    }
}
#endif

struct CloudView: View {
    @ObservedObject var model: CloudModel
    @State private var quotaStorageConsent = false
    @State private var collectorProcessingConsent = false
    @AppStorage("cloudTrustedBaseURL") private var base = "https://usage.mvtp.cloud"
    @State private var provider = ProviderID.claude
    @State private var confirmDelete = false
    @State private var collectorCode = ""
    @State private var selectedSlots = Set<UUID>()
    @State private var collectorConsent = false
    var body: some View {
        Form {
            Text(model.status).font(.caption)
            if model.session == nil {
                TextField("Trusted HTTPS server", text: $base).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Only connect to a server you trust. The server stores sanitized quota, a pseudonymous Apple account, sessions and refresh counters — not provider credentials. A local collector processes quota for your slots. You can instead use Pair bridge without cloud.")
                Toggle("Store sanitized quota and account metadata", isOn: $quotaStorageConsent)
                Toggle("Allow local collector quota processing", isOn: $collectorProcessingConsent)
                Text("Both consents are required for cloud. Purchases are unavailable in this preview.").font(.caption).foregroundStyle(.secondary)
                Button("Connect with Apple") {
                    let trustedBase = base
                    let storage = quotaStorageConsent
                    let processing = collectorProcessingConsent
                    Task { await model.connect(base: trustedBase, quotaStorageConsent: storage, collectorProcessingConsent: processing) }
                }.disabled(!quotaStorageConsent || !collectorProcessingConsent || model.busy)
            } else {
                Text(model.budget)
                Text("Local collector required. No provider login or purchases on this phone.")
                Text("Purchases unavailable in this app: Apple products and signing configuration are not ready. Only server-verified entitlements apply.").font(.caption)
                if let me = model.me {
                    Toggle("Local collector automatic updates", isOn: Binding(get: { model.me?.backgroundCollection ?? true }, set: { enabled in
                        Task { await model.mutate(path: "v2/settings", method: "PUT", body: ["autoMinutes": me.autoMinutes, "backgroundCollection": enabled]) }
                    })).disabled(model.busy || model.liveEnabled)
                    Text("The local computer must stay online. Its due checks run about every 20 minutes; the server enforces your tier interval. This is independent of the phone's foreground setting, not guaranteed iOS background execution.").font(.caption)
                    if me.tier == .pro {
                        Picker("Due-check interval", selection: Binding(get: { model.me?.autoMinutes ?? 20 }, set: { minutes in
                            Task { await model.mutate(path: "v2/settings", method: "PUT", body: ["autoMinutes": minutes]) }
                        })) {
                            ForEach(me.limits.allowedAutoMinutes, id: \.self) { Text("\($0) minutes").tag($0) }
                        }.disabled(model.busy || model.liveEnabled)
                    }
                    if me.limits.live {
                        Text("Paid Live: explicit opt-in, target 60-second foreground checks. One allowance begins on first fresh success; the server's 30-minute wall deadline continues while hidden or locked. Resuming uses the same server session.").font(.caption)
                        Button(model.liveEnabled ? "Live checks running" : "Start / resume Live") { model.startLive() }
                            .disabled(model.busy || model.liveEnabled || model.slots.isEmpty)
                        Button("Stop Live session") { Task { await model.stopLive() } }
                        if let deadline = model.liveDeadline { Text("Live ends: \(deadline.formatted())").font(.caption) }
                    } else { Text("Live requires a verified paid entitlement. Purchases are unavailable here.").font(.caption) }
                }
                Picker("New slot", selection: $provider) {
                    ForEach([ProviderID.claude, .codex, .gemini, .grok], id: \.self) { Text($0.displayName).tag($0) }
                }
                Button("Add provider slot") { Task { await model.mutate(path: "v2/accounts", method: "POST", body: ["provider": provider.rawValue]) } }.disabled(model.busy || model.liveEnabled || model.me == nil || model.me?.limits.accounts.map { model.slots.count >= $0 } == true)
                CloudBatchView(slots: model.slots, ids: model.refreshSelection.ids, locked: model.busy || model.selectionLocked) { ids in
                    model.selectRefreshSlots(ids)
                }
                ForEach(model.slots) { slot in
                    VStack(alignment: .leading) {
                        Text("\(slot.provider.displayName) · \(slot.id.uuidString.prefix(8))")
                        Text(slot.id.uuidString).font(.caption).textSelection(.enabled)
                        Button("Copy nonsecret slot UUID") { UIPasteboard.general.string = slot.id.uuidString }
                        if let account = model.snapshot?.accounts.first(where: { $0.id == slot.id }) {
                            ProviderCard(provider: account.reading, demo: model.snapshot?.demo == true)
                            if account.lastError != nil { Text("Last collection unavailable; original observation retained.").font(.caption) }
                        } else { Text("Unknown — awaiting local collector") }
                        Button("Remove slot", role: .destructive) { Task { await model.mutate(path: "v2/accounts/\(slot.id.uuidString)", method: "DELETE") } }.disabled(model.busy || model.liveEnabled)
                    }
                }
                Section("Local collector approval") {
                    Text("Duplicate-provider slots require independent CLI account mappings; Gemini remains limited to one local account. Approval authorizes slot access, not validation of real provider identities. It grants quota jobs for these slots only, not your Apple session. Never copy or export the Apple session.").font(.caption)
                    TextField("Eight uppercase hex pairing code", text: $collectorCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: collectorCode) { _, _ in collectorConsent = false }
                    ForEach(model.slots) { slot in
                        Toggle("\(slot.provider.displayName) · \(slot.id.uuidString)", isOn: Binding(get: { selectedSlots.contains(slot.id) }, set: { enabled in
                            if enabled { selectedSlots.insert(slot.id) } else { selectedSlots.remove(slot.id) }
                            collectorConsent = false
                        }))
                    }
                    Toggle("I authorize this collector to process the selected slots", isOn: $collectorConsent)
                    Button("Approve selected slots") {
                        let code = collectorCode
                        let ids = selectedSlots
                        guard collectorConsent, CollectorApproval.valid(code: code, selected: ids, slots: model.slots) else { return }
                        collectorConsent = false
                        Task { await model.mutate(path: "v2/collector/approve", method: "POST", body: ["code": code, "accountIds": ids.map(\.uuidString).sorted()]) }
                    }.disabled(!collectorConsent || !CollectorApproval.valid(code: collectorCode, selected: selectedSlots, slots: model.slots) || model.busy || model.liveEnabled)
                    ForEach(model.collectors) { collector in
                        Text("Collector \(collector.id.uuidString) · expires \(collector.expiresAt.formatted())").font(.caption)
                        Text(collector.accountIds.map(\.uuidString).joined(separator: "\n")).font(.caption).textSelection(.enabled)
                        Button("Revoke collector", role: .destructive) { Task { await model.mutate(path: "v2/collectors/\(collector.id.uuidString)", method: "DELETE") } }.disabled(model.busy || model.liveEnabled)
                    }
                    Text("Collector list requires a successful server read; an unavailable list is not proof of revocation.").font(.caption)
                }
                Button("Force refresh (verified budget applies)") { Task { await model.refresh(force: true) } }.disabled(model.busy || model.liveEnabled)
                Button("Read cached snapshot") { Task { await model.read() } }
                Button("Log out", role: .destructive) { Task { await model.disconnect(delete: false) } }
                Button("Delete cloud account and data", role: .destructive) { confirmDelete = true }
            }
        }.navigationTitle("Optional cloud")
            .onChange(of: base) { _, _ in
                quotaStorageConsent = false; collectorProcessingConsent = false
            }
            .onChange(of: model.session?.token) { _, _ in
                selectedSlots = []; collectorConsent = false; collectorCode = ""
                quotaStorageConsent = false; collectorProcessingConsent = false
            }
            .onChange(of: model.slots.map(\.id)) { _, ids in
                selectedSlots.formIntersection(Set(ids)); collectorConsent = false
            }
            .confirmationDialog("Permanently erase cloud account, quota and all sessions?", isPresented: $confirmDelete) {
                Button("Erase account", role: .destructive) { Task { await model.disconnect(delete: true) } }
            }
    }
}
