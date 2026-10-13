import XCTest
@testable import QuotaDock

final class ContractTests: XCTestCase {
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
