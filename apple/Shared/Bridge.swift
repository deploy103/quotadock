import Foundation
import Security

struct Pairing: Codable {
    let endpoint: URL
    let token: String

    init(baseURL: String, token: String) throws {
        guard let url = URL(string: baseURL), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, !token.isEmpty,
              !token.contains(where: { $0.isNewline || $0 == "\r" }) else {
            throw SnapshotError.insecureURL
        }
        endpoint = url.appendingPathComponent("v1/snapshot")
        self.token = token
    }
}

enum PairingStore {
    private static var query: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "QuotaDock.bridge",
                                  kSecAttrAccount as String: "pairing"]
        if let group = Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    static func load() throws -> Pairing {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { throw SnapshotError.unpaired }
        return try JSONDecoder().decode(Pairing.self, from: data)
    }

    static func save(_ pairing: Pairing) throws {
        let data = try JSONEncoder().encode(pairing)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SnapshotError.unpaired }
        } else if status != errSecSuccess { throw SnapshotError.unpaired }
    }

    static func remove() { SecItemDelete(query as CFDictionary) }
}

final class HTTPSRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward bearer credentials to a redirect, even another HTTPS host.
        completionHandler(nil)
    }
}

struct BridgeClient {
    private let session: URLSession
    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: HTTPSRedirectPolicy(), delegateQueue: nil)
    }

    func fetch(_ pairing: Pairing) async throws -> Snapshot {
        guard pairing.endpoint.scheme?.lowercased() == "https",
              pairing.endpoint.host != nil, pairing.endpoint.user == nil,
              pairing.endpoint.password == nil else { throw SnapshotError.insecureURL }
        var request = URLRequest(url: pairing.endpoint)
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw SnapshotError.response
        }
        return try Snapshot.decode(data).sanitized
    }
}
