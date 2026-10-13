import XCTest
@testable import QuotaDock

final class ContractTests: XCTestCase {
    private let cloudFixture = Data("""
    {"schemaVersion":2,"generatedAt":"2026-10-13T10:30:00Z","demo":false,"sessionToken":"must-not-cache","accounts":[
      {"accountId":"11111111-1111-4111-8111-111111111111","provider":"codex","name":"ignored private name","plan":"ChatGPT Pro","state":"available","source":"codexbar","observedAt":"2026-10-13T10:00:00.123Z","windows":[{"id":"primary","label":"Session","remainingPercent":75,"resetsAt":null},{"id":"secondary","label":"Weekly","remainingPercent":28,"resetsAt":null}],"lastError":"private diagnostic"},
      {"accountId":"22222222-2222-4222-8222-222222222222","provider":"codex","name":"Codex","plan":null,"state":"unavailable","source":"codexbar","observedAt":null,"windows":[{"id":"primary","label":"Session","remainingPercent":null,"resetsAt":null}],"lastError":null}
    ]}
    """.utf8)

    func testCloudPreservesSameProviderSlotsAndUnknownWindows() throws {
        let snapshot = try CloudSnapshot.decode(cloudFixture)
        XCTAssertEqual(snapshot.accounts.count, 2)
        XCTAssertNotEqual(snapshot.accounts[0].id, snapshot.accounts[1].id)
        XCTAssertEqual(snapshot.accounts.map(\.provider), [.codex, .codex])
        XCTAssertEqual(snapshot.accounts[0].windows.count, 2)
        XCTAssertEqual(snapshot.accounts[0].reading.displayWindows[1].clampedRemaining, 28)
        XCTAssertNil(snapshot.accounts[1].reading.displayWindows.first?.clampedRemaining)
        XCTAssertNil(snapshot.accounts[1].observedAt)
        XCTAssertEqual(snapshot.smallSurfaceSnapshot.providers.count, 1)
        XCTAssertEqual(snapshot.smallSurfaceSnapshot.providers[0].windows[0].clampedRemaining, 75)
        XCTAssertEqual(snapshot.smallSurfaceSnapshot.providers[0].observedAt, snapshot.accounts[0].observedAt)
    }

    func testCloudCacheExportsOnlySanitizedQuotaAndOriginalTime() throws {
        let snapshot = try CloudSnapshot.decode(cloudFixture)
        let full = try snapshot.cacheData()
        let shared = try snapshot.smallSurfaceSnapshot.encoded()
        for data in [full, shared] {
            let text = String(decoding: data, as: UTF8.self)
            for secret in ["sessionToken", "must-not-cache", "private diagnostic", "ignored private name"] {
                XCTAssertFalse(text.contains(secret))
            }
        }
        let cached = try CloudSnapshot.decode(full)
        XCTAssertEqual(cached.accounts.count, 2)
        XCTAssertEqual(cached.accounts[0].observedAt, snapshot.accounts[0].observedAt)
        XCTAssertEqual(cached.accounts[0].lastError, "collection_unavailable")
        XCTAssertNil(cached.accounts[1].windows[0].clampedRemaining)
        XCTAssertEqual(try Snapshot.decode(shared).providers[0].observedAt, snapshot.accounts[0].observedAt)
    }

    func testCloudVerifiedTierLimitsIntervalsAndCounters() throws {
        for (tier, cap, minutes, allowed, early, liveLimit) in [
            ("free", "3", 120, "[120]", "10", 0),
            ("plus", "10", 60, "[60]", "null", 5),
            ("pro", "null", 20, "[20,30,60,120]", "null", 5)
        ] {
            let json = """
            {"tier":"\(tier)","limits":{"accounts":\(cap),"autoMinutes":\(minutes),"allowedAutoMinutes":\(allowed),"earlyBatchesPerDay":\(early),"live":\(tier != "free")},"autoMinutes":\(minutes),"earlyBatchesUsed":2,"liveSessionsUsed":0,"liveSessionsLimit":\(liveLimit),"purchasesAvailable":false,"identity":"never display"}
            """
            let me = try CloudMe.decode(Data(json.utf8))
            XCTAssertEqual(me.autoMinutes, minutes)
            XCTAssertEqual(me.earlyBatchesUsed, 2)
            XCTAssertEqual(me.limits.accounts, Int(cap))
            XCTAssertFalse(me.purchasesAvailable)
            XCTAssertTrue(me.budget.contains(tier.capitalized))
            XCTAssertFalse(me.budget.contains("never display"))
            XCTAssertThrowsError(try CloudMe.decode(Data(json.replacingOccurrences(of: "\"earlyBatchesUsed\":2", with: "\"earlyBatchesUsed\":-1").utf8)))
            XCTAssertThrowsError(try CloudMe.decode(Data(json.replacingOccurrences(of: "\"tier\":\"\(tier)\"", with: "\"tier\":\"clientPaid\"").utf8)))
            XCTAssertThrowsError(try CloudMe.decode(Data(json.replacingOccurrences(of: "\"autoMinutes\":\(minutes)", with: "\"autoMinutes\":7").utf8)))
            if tier == "pro" {
                for interval in [20, 30, 60, 120] {
                    XCTAssertEqual(try CloudMe.decode(Data(json.replacingOccurrences(of: "\"autoMinutes\":20", with: "\"autoMinutes\":\(interval)").utf8)).autoMinutes, interval)
                }
                var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
                root["liveSession"] = ["accountIds": ["11111111-1111-4111-8111-111111111111"], "startedAt": "2026-10-13T10:00:00.000Z", "deadline": "2026-10-13T10:30:00.000Z"]
                let resumed = try CloudMe.decode(JSONSerialization.data(withJSONObject: root))
                XCTAssertEqual(resumed.liveSessionsUsed, 0) // Renewal can reset counters during an active session.
                XCTAssertEqual(resumed.liveSession?.deadlineDate, Date(timeIntervalSince1970: 1791887400))
            }
        }
    }

    func testCloudSnapshotAllowsMoreThanFreeRegistrationCap() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: cloudFixture) as? [String: Any])
        let template = try XCTUnwrap((root["accounts"] as? [[String: Any]])?.first)
        root["accounts"] = (0..<11).map { _ -> [String: Any] in
            var account = template
            account["accountId"] = UUID().uuidString
            return account
        }
        let snapshot = try CloudSnapshot.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(snapshot.accounts.count, 11)
        XCTAssertEqual(snapshot.smallSurfaceSnapshot.providers.count, 1)
    }

    func testRefreshBatchPreservesSubsetAndEnforcesOwnershipAndFiftyLimit() {
        let slots = (0..<61).map { _ in CloudAccount(id: UUID(), provider: .codex) }
        var batch = CloudBatchSelection()
        batch.reconcile(slots: slots)
        XCTAssertEqual(batch.ids, Array(slots.prefix(50).map(\.id)))
        let subset = [slots[3].id, slots[27].id, slots[60].id]
        XCTAssertTrue(batch.select(subset, slots: slots))
        batch.reconcile(slots: Array(slots.reversed()))
        XCTAssertEqual(batch.ids, subset)
        for invalid in [Array(slots.prefix(51).map(\.id)), [slots[3].id, slots[3].id], [slots[3].id, UUID()]] {
            XCTAssertFalse(CloudBatchSelection.valid(invalid, slots: slots))
            XCTAssertFalse(batch.select(invalid, slots: slots))
            XCTAssertEqual(batch.ids, subset)
        }
        XCTAssertTrue(CloudBatchSelection.valid(Array(slots.prefix(50).map(\.id)), slots: slots))
        batch.reconcile(slots: slots.filter { $0.id != slots[27].id })
        XCTAssertEqual(batch.ids, [slots[3].id, slots[60].id])
        XCTAssertTrue(batch.select([], slots: slots))
        batch.reconcile(slots: slots)
        XCTAssertTrue(batch.ids.isEmpty) // An explicit empty selection is not silently refilled.
        XCTAssertFalse(CloudBatchSelection.valid(batch.ids, slots: slots))
        XCTAssertFalse(CollectorApproval.valid(code: "AB0123EF", selected: Set(slots.prefix(51).map(\.id)), slots: slots))
    }

    @MainActor
    func testLiveAcceptsSelectedSubsetAndRestoresDifferentServerSubset() throws {
        let model = CloudModel()
        model.foreground = false // No network work is scheduled by this contract test.
        let slots = (0..<60).map { _ in CloudAccount(id: UUID(), provider: .codex) }
        model.slots = slots
        let selected = [slots[4].id, slots[58].id]
        model.selectRefreshSlots(selected)
        let json = """
        {"tier":"pro","limits":{"accounts":null,"autoMinutes":20,"allowedAutoMinutes":[20,30,60,120],"earlyBatchesPerDay":null,"live":true},"autoMinutes":20,"earlyBatchesUsed":0,"liveSessionsUsed":0,"liveSessionsLimit":5,"purchasesAvailable":false}
        """
        model.me = try CloudMe.decode(Data(json.utf8))
        model.startLive()
        XCTAssertTrue(model.liveEnabled) // More than 50 registrations do not block a small batch.
        model.clear()
        model.slots = slots
        model.selectRefreshSlots(selected)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        root["liveSession"] = ["accountIds": [slots[22].id.uuidString],
                               "startedAt": "2099-01-01T00:00:00.000Z", "deadline": "2099-01-01T00:30:00.000Z"]
        model.me = try CloudMe.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertTrue(model.selectionLocked)
        model.selectRefreshSlots([slots[1].id])
        XCTAssertEqual(model.refreshSelection.ids, selected)
        model.startLive()
        XCTAssertTrue(model.liveEnabled) // Restore need not equal every registration or the UI selection.
        XCTAssertEqual(model.liveDeadline, model.me?.liveSession?.deadlineDate)
        model.clear()
    }

    @MainActor
    func testCloudModelSelectionSurvivesReadsAndClearsOnLogout() {
        let model = CloudModel()
        let slots = (0..<60).map { _ in CloudAccount(id: UUID(), provider: .claude) }
        model.slots = slots
        model.selectRefreshSlots([slots[9].id, slots[59].id])
        model.slots = Array(slots.reversed())
        XCTAssertEqual(model.refreshSelection.ids, [slots[9].id, slots[59].id])
        model.liveEnabled = true
        model.selectRefreshSlots([slots[1].id])
        XCTAssertEqual(model.refreshSelection.ids, [slots[9].id, slots[59].id])
        model.clear()
        XCTAssertTrue(model.refreshSelection.ids.isEmpty)
        model.slots = [slots[1]]
        XCTAssertEqual(model.refreshSelection.ids, [slots[1].id])
    }

    func testCollectorApprovalRequiresOwnedSlotsAndExactCode() {
        let first = CloudAccount(id: UUID(), provider: .codex)
        let duplicate = CloudAccount(id: UUID(), provider: .codex)
        let other = CloudAccount(id: UUID(), provider: .claude)
        let slots = [first, duplicate, other]
        XCTAssertTrue(CollectorApproval.valid(code: "AB0123EF", selected: [first.id, other.id], slots: slots))
        XCTAssertTrue(CollectorApproval.valid(code: "AB0123EF", selected: [first.id, duplicate.id], slots: slots))
        XCTAssertFalse(CollectorApproval.valid(code: "AB0123EF", selected: [UUID()], slots: slots))
        XCTAssertFalse(CollectorApproval.valid(code: "AB0123EF", selected: [], slots: slots))
        for code in ["ab0123ef", "AB0123EG", " AB0123EF", "AB0123E", "ＡＢ0123EF"] {
            XCTAssertFalse(CollectorApproval.valid(code: code, selected: [first.id], slots: slots))
        }
    }

    func testCloudRejectsDuplicateAccountsAndInsecureServer() throws {
        let duplicate = String(decoding: cloudFixture, as: UTF8.self).replacingOccurrences(
            of: "22222222-2222-4222-8222-222222222222", with: "11111111-1111-4111-8111-111111111111")
        XCTAssertThrowsError(try CloudSnapshot.decode(Data(duplicate.utf8)))
        XCTAssertThrowsError(try CloudSnapshot.decode(Data(repeating: 32, count: 256 * 1024 + 1)))
        XCTAssertThrowsError(try CloudClient(baseURL: "http://usage.mvtp.cloud"))
        XCTAssertThrowsError(try CloudClient(baseURL: "https://user:password@example.com"))
        XCTAssertThrowsError(try CloudClient(baseURL: "https://example.com?secret=x"))
        XCTAssertEqual(try CloudClient(baseURL: "https://usage.mvtp.cloud").baseURL.host, "usage.mvtp.cloud")
    }

    @MainActor
    func testModeSwitchInvalidatesOldCompletionsAndClearsBothCaches() {
        let model = DockModel()
        model.snapshot = .preview
        let oldRevision = model.pairingRevision
        let oldCloudRevision = model.cloud.revision
        model.cloud.clear()
        XCTAssertGreaterThan(model.pairingRevision, oldRevision)
        XCTAssertGreaterThan(model.cloud.revision, oldCloudRevision)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.cloud.snapshot)
        XCTAssertNil(SnapshotStore.load())
        XCTAssertNil(CloudCache.load())
    }

    private let fixture = Data("""
    {"schemaVersion":1,"generatedAt":"2026-10-13T10:00:00Z","demo":false,"providers":[{"id":"codex","name":"Codex","plan":null,"state":"unavailable","source":"codexbar","message":null,"observedAt":null,"windows":[{"id":"primary","label":"Session","remainingPercent":null,"resetsAt":null}]}]}
    """.utf8)

    func testNullRemainsUnknownAndRoundTripsAsNull() throws {
        let snapshot = try Snapshot.decode(fixture)
        let provider = try XCTUnwrap(snapshot.providers.first)
        XCTAssertNil(provider.plan)
        XCTAssertNil(provider.windows.first?.clampedRemaining)
        XCTAssertTrue(provider.isStale())
        let data = try snapshot.encoded()
        XCTAssertEqual(try Snapshot.decode(data), snapshot)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedProvider = try XCTUnwrap((root["providers"] as? [[String: Any]])?.first)
        XCTAssertTrue(encodedProvider["plan"] is NSNull)
        XCTAssertTrue(encodedProvider["observedAt"] is NSNull)
        let window = try XCTUnwrap((encodedProvider["windows"] as? [[String: Any]])?.first)
        XCTAssertTrue(window["remainingPercent"] is NSNull)
        XCTAssertTrue(window["resetsAt"] is NSNull)
    }

    func testClampDoesNotTurnUnknownIntoZero() {
        for (input, expected) in [(Double(-8), Double(0)), (180, 100), (0, 0)] {
            XCTAssertEqual(QuotaWindow(id: "x", label: "x", remainingPercent: input, resetsAt: nil).clampedRemaining, expected)
        }
        XCTAssertNil(QuotaWindow(id: "x", label: "x", remainingPercent: nil, resetsAt: nil).clampedRemaining)
    }

    func testStalenessAndDemo() throws {
        let snapshot = Snapshot.preview
        XCTAssertTrue(snapshot.demo)
        XCTAssertTrue(snapshot.providers.allSatisfy { $0.source == .demo })
        let provider = try XCTUnwrap(snapshot.providers.first)
        let observed = try XCTUnwrap(provider.observedAt)
        XCTAssertFalse(provider.isStale(at: observed.addingTimeInterval(900)))
        XCTAssertTrue(provider.isStale(at: observed.addingTimeInterval(901)))
    }

    func testDisplayWindowsNeverGaugeLookupFailuresAndPreserveWindows() {
        let reset = Date(timeIntervalSince1970: 1234)
        let windows = [QuotaWindow(id: "session", label: "Session", remainingPercent: 0, resetsAt: reset),
                       QuotaWindow(id: "weekly", label: "Weekly", remainingPercent: 72, resetsAt: nil)]
        for state in [ProviderState.available, .unavailable, .error] {
            let provider = Provider(id: .codex, name: "Codex", plan: nil, state: state,
                                    source: .codexbar, message: nil, observedAt: reset, windows: windows)
            XCTAssertEqual(provider.displayWindows.map(\.id), ["session", "weekly"])
            XCTAssertEqual(provider.displayWindows.first?.resetsAt, reset)
            XCTAssertEqual(provider.observedAt, reset)
            if state == .available {
                XCTAssertEqual(provider.displayWindows, windows)
            } else {
                XCTAssertTrue(provider.displayWindows.allSatisfy { $0.clampedRemaining == nil })
            }
        }
    }

    func testForegroundRefreshDefaultsOnAndHonorsManualOnly() throws {
        let suite = "QuotaDockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(RefreshSettings.foregroundEnabled(in: defaults))
        defaults.set(false, forKey: RefreshSettings.foregroundKey)
        XCTAssertFalse(RefreshSettings.foregroundEnabled(in: defaults))
        defaults.set(true, forKey: RefreshSettings.foregroundKey)
        XCTAssertTrue(RefreshSettings.foregroundEnabled(in: defaults))
    }

    func testRejectsUnsupportedVersionOversizeAndBadDates() {
        XCTAssertThrowsError(try Snapshot.decode(Data(String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2").utf8)))
        XCTAssertThrowsError(try Snapshot.decode(Data(repeating: 32, count: 256 * 1024 + 1)))
        XCTAssertThrowsError(try Snapshot.decode(Data(String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "2026-10-13T10:00:00Z", with: "bad-date").utf8)))
    }

    func testHTTPSOnlyPairing() throws {
        XCTAssertThrowsError(try Pairing(baseURL: "http://example.com", token: "secret"))
        XCTAssertThrowsError(try Pairing(baseURL: "https://user:pass@example.com", token: "secret"))
        XCTAssertThrowsError(try Pairing(baseURL: "https://example.com?token=secret", token: "secret"))
        XCTAssertThrowsError(try Pairing(baseURL: "https://example.com", token: "secret\nheader"))
        XCTAssertEqual(try Pairing(baseURL: "https://example.com", token: "secret").endpoint.path, "/v1/snapshot")
    }

    func testNetworkRequestAndSafeResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = BridgeClient(session: URLSession(configuration: configuration))
        let snapshot = try await client.fetch(Pairing(baseURL: "https://example.com", token: "test-token"))
        XCTAssertEqual(snapshot.providers.first?.message, "Usage unavailable")
        XCTAssertNil(snapshot.providers.first?.windows.first?.clampedRemaining)
        do {
            _ = try await client.fetch(Pairing(baseURL: "https://example.com/reject", token: "test-token"))
            XCTFail("Must reject non-200 responses")
        } catch SnapshotError.response { } catch { XCTFail("Unexpected error type") }
    }
}

private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertTrue(request.url?.path.hasSuffix("/v1/snapshot") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let status = request.url?.path.contains("reject") == true ? 401 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("""
        {"schemaVersion":1,"generatedAt":"2026-10-13T10:00:00.123Z","demo":false,"providers":[{"id":"codex","name":"Codex","plan":null,"state":"error","source":"codexbar","message":"private diagnostic","observedAt":null,"windows":[{"id":"primary","label":"Session","remainingPercent":99,"resetsAt":null}]}]}
        """.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
