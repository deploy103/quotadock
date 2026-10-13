import XCTest
@testable import QuotaDock

final class CloudPaginationTests: XCTestCase {
    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "%08x-0000-4000-8000-000000000000", index))!
    }
    private func page(_ ids: [UUID], next: UUID? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "accounts": ids.map { ["id": $0.uuidString, "provider": "codex"] },
            "nextCursor": next.map { $0.uuidString as Any } ?? NSNull()
        ])
    }
    private func snapshotPage(_ ids: [UUID], next: UUID? = nil, demo: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2, "generatedAt": "2026-10-13T10:30:00Z", "demo": demo,
            "accounts": ids.map { ["accountId": $0.uuidString, "provider": "codex",
                "state": "available", "source": "codexbar", "observedAt": "2026-10-13T10:00:00Z",
                "windows": []] as [String: Any] },
            "nextCursor": next.map { $0.uuidString as Any } ?? NSNull()
        ])
    }
    func testCursorTraversalPreservesDistinctSameProviderSlotsAndBatch() async throws {
        let ids = (1...75).map(uuid)
        let slots = try await CloudPagination.accounts { path in
            let after = URLComponents(string: "https://example.com/" + path)?.queryItems?
                .first(where: { $0.name == "after" })?.value
            let start = after.flatMap { UUID(uuidString: $0) }.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            let end = min(start + 50, ids.count)
            return try self.page(Array(ids[start..<end]), next: end < ids.count ? ids[end - 1] : nil)
        }
        XCTAssertEqual(slots.map(\.id), ids)
        var batch = CloudBatchSelection()
        batch.reconcile(slots: slots)
        XCTAssertEqual(batch.ids, Array(ids.prefix(50)))
        XCTAssertTrue(batch.select([ids[74]], slots: slots))
        batch.reconcile(slots: slots)
        XCTAssertEqual(batch.ids, [ids[74]])
        let snapshot = try await CloudPagination.snapshot(slots: slots) { path in
            let after = URLComponents(string: "https://example.com/" + path)?.queryItems?
                .first(where: { $0.name == "after" })?.value
            let start = after.flatMap { UUID(uuidString: $0) }.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            let end = min(start + 50, ids.count)
            return try self.snapshotPage(Array(ids[start..<end]), next: end < ids.count ? ids[end - 1] : nil)
        }
        XCTAssertEqual(snapshot.accounts.map(\.id), ids)
        XCTAssertEqual(snapshot.smallSurfaceSnapshot.providers.count, 1)
    }
    func testRejectsDuplicateUnsortedNonadvancingAndMissingCursor() async throws {
        let invalid = [try page([uuid(1), uuid(1)]), try page([uuid(2), uuid(1)]),
                       try page([uuid(1)], next: uuid(2)), try page([], next: uuid(1)),
                       Data("{\"accounts\":[]}".utf8)]
        for data in invalid {
            do {
                _ = try await CloudPagination.accounts { _ in data }
                XCTFail("Malformed page accepted")
            } catch { }
        }
        do {
            _ = try await CloudPagination.accounts { _ in try self.page([self.uuid(1)], next: self.uuid(1)) }
            XCTFail("Repeated page accepted")
        } catch { }
    }
    func testLegacyFallbackOnlyForMissingFirstEndpoint() async throws {
        let legacy = Data("{\"accounts\":[{\"id\":\"\(uuid(1))\",\"provider\":\"codex\"}]}".utf8)
        let result = try await CloudPagination.accounts { path in
            if path.hasPrefix("v2/accounts/page") { throw CloudHTTPError.notFound }
            return legacy
        }
        XCTAssertEqual(result.map(\.id), [uuid(1)])
        for failure in [SnapshotError.response, SnapshotError.invalid] {
            do {
                _ = try await CloudPagination.accounts { path in
                    if path.hasPrefix("v2/accounts/page") { throw failure }
                    XCTFail("Non-404 failure attempted legacy fallback")
                    return legacy
                }
                XCTFail("Failed endpoint accepted")
            } catch { }
        }
        do {
            _ = try await CloudPagination.accounts { path in
                if path.contains("after=") { throw CloudHTTPError.notFound }
                if path.hasPrefix("v2/accounts/page") { return try self.page([self.uuid(1)], next: self.uuid(1)) }
                XCTFail("Mid-traversal 404 attempted fallback")
                return legacy
            }
            XCTFail("Incomplete traversal accepted")
        } catch { }
    }
    func testRejectsForeignMissingAndDemoSnapshotRows() async throws {
        let slots = [CloudAccount(id: uuid(1), provider: .codex)]
        for data in [try snapshotPage([uuid(2)]), try snapshotPage([]), try snapshotPage([uuid(1)], demo: true)] {
            do {
                _ = try await CloudPagination.snapshot(slots: slots) { _ in data }
                XCTFail("Invalid snapshot accepted")
            } catch { }
        }
    }
    func testEndlessAdvancingPagesAreBounded() async throws {
        do {
            _ = try await CloudPagination.accounts { path in
                let after = URLComponents(string: "https://example.com/" + path)?.queryItems?
                    .first(where: { $0.name == "after" })?.value
                let value = after.flatMap { Int($0.prefix(8), radix: 16) } ?? 0
                return try self.page([self.uuid(value + 1)], next: self.uuid(value + 1))
            }
            XCTFail("Unending pagination accepted")
        } catch { }
    }
    func testLargeCacheIsExplicitSubsetWithOriginalTimes() throws {
        let original = try CloudSnapshot.decode(snapshotPage([uuid(1)]))
        let account = original.accounts[0]
        let rows = (1...5000).map { index in
            CloudSnapshot.Account(accountId: uuid(index), provider: account.provider, plan: account.plan,
                state: account.state, source: account.source, observedAt: account.observedAt,
                windows: account.windows, lastError: nil)
        }
        let large = CloudSnapshot(schemaVersion: 2, generatedAt: original.generatedAt, demo: false, accounts: rows)
        let data = try large.cacheData()
        XCTAssertLessThanOrEqual(data.count, 256 * 1024)
        let cached = try CloudSnapshot.decode(data)
        XCTAssertEqual(cached.cachedSubset, true)
        XCTAssertEqual(cached.accounts.map(\.id), Array(rows.prefix(50)).map(\.id))
        XCTAssertEqual(cached.generatedAt, original.generatedAt)
        XCTAssertEqual(cached.accounts[0].observedAt, account.observedAt)
        XCTAssertEqual(large.accounts.count, 5000)
        XCTAssertEqual(try CloudSnapshot.decode(cached.cacheData()).cachedSubset, true)
    }
    @MainActor
    func testReadWithoutAuthorityOrForegroundRetainsObservationsAndSelection() async throws {
        let model = CloudModel()
        model.session = nil
        let original = try CloudSnapshot.decode(snapshotPage([uuid(1)]))
        model.snapshot = original
        model.slots = [CloudAccount(id: uuid(1), provider: .codex)]
        await model.read()
        XCTAssertEqual(model.snapshot?.accounts.map(\.id), original.accounts.map(\.id))
        XCTAssertEqual(model.snapshot?.generatedAt, original.generatedAt)
        XCTAssertEqual(model.refreshSelection.ids, [uuid(1)])
        model.foreground = false
        await model.read(internalWork: true)
        XCTAssertEqual(model.snapshot?.accounts[0].observedAt, original.accounts[0].observedAt)
        XCTAssertEqual(model.refreshSelection.ids, [uuid(1)])
    }
}
