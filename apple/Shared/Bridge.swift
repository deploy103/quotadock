import Foundation
import Security

struct Pairing: Codable {
    let endpoint: URL
    let token: String

    init(baseURL: String, token: String) throws {
        guard let url = URL(string: baseURL), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, !token.isEmpty,
              token.utf8.count <= 128,
              token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw SnapshotError.insecureURL
        }
        endpoint = url.appendingPathComponent("v1/snapshot")
        self.token = token
        try validate()
    }

    private enum CodingKeys: String, CodingKey { case endpoint, token }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try values.decode(URL.self, forKey: .endpoint)
        token = try values.decode(String.self, forKey: .token)
        try validate()
    }

    func validate() throws {
        guard endpoint.scheme?.lowercased() == "https",
              let host = endpoint.host, !host.isEmpty,
              endpoint.absoluteString.utf8.count <= 2048,
              endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              !token.isEmpty, token.utf8.count <= 128,
              token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw SnapshotError.insecureURL
        }
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
              let data = result as? Data, data.count <= 8192 else { throw SnapshotError.unpaired }
        return try JSONDecoder().decode(Pairing.self, from: data)
    }

    static func save(_ pairing: Pairing) throws {
        try save(pairing, update: SecItemUpdate, add: SecItemAdd)
    }

    // Update in place; never delete the usable item to make replacement possible.
    static func save(_ pairing: Pairing,
                     update: (CFDictionary, CFDictionary) -> OSStatus,
                     add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus) throws {
        try pairing.validate()
        let data = try JSONEncoder().encode(pairing)
        guard data.count <= 8192 else { throw SnapshotError.invalid }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = update(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard add(item as CFDictionary, nil) == errSecSuccess else { throw SnapshotError.unpaired }
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
    private let configuration: URLSessionConfiguration
    init(session: URLSession? = nil) {
        let configuration = session?.configuration ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        self.configuration = configuration
    }

    func fetch(_ pairing: Pairing) async throws -> Snapshot {
        let transport = BridgeTransport()
        do {
            try Task.checkCancellation()
            try pairing.validate()
            var request = URLRequest(url: pairing.endpoint)
            request.httpShouldHandleCookies = false
            request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data = try await withTaskCancellationHandler(operation: {
                try await transport.load(request, configuration: configuration)
            }, onCancel: { transport.cancel() })
            try Task.checkCancellation()
            return try Snapshot.decode(data).sanitized
        } catch let error as BridgeTransportError {
            throw error
        } catch {
            throw BridgeTransportError.transport
        }
    }
}

// No server body, URL, token, or underlying network diagnostic escapes this boundary.
enum BridgeTransportError: Error, Equatable {
    case unauthorized
    case forbidden
    case transport
}

private final class BridgeTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = OperationQueue()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Data, Error>?
    private var data = Data()
    private var timer: DispatchWorkItem?
    private var cancelled = false
    private let deadline = ProcessInfo.processInfo.systemUptime + 20

    override init() {
        super.init()
        queue.maxConcurrentOperationCount = 1
    }

    func load(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.addOperation {
                self.continuation = continuation
                guard !self.cancelled else { self.finish(.failure(BridgeTransportError.transport)); return }
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.queue)
                self.session = session
                let task = session.dataTask(with: request)
                self.task = task
                let timer = DispatchWorkItem {
                    self.queue.addOperation { self.finish(.failure(BridgeTransportError.transport)) }
                }
                self.timer = timer
                // Independent of incoming bytes: stalled headers/bodies and trickles all expire.
                DispatchQueue.global().asyncAfter(deadline: .now() + max(0, self.deadline - ProcessInfo.processInfo.systemUptime), execute: timer)
                task.resume()
            }
        }
    }

    func cancel() {
        queue.addOperation {
            self.cancelled = true
            self.finish(.failure(BridgeTransportError.transport))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        timer?.cancel()
        timer = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(BridgeTransportError.transport))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= 256 * 1024 else {
            completionHandler(.cancel)
            let status = (response as? HTTPURLResponse)?.statusCode
            finish(.failure(status == 401 ? BridgeTransportError.unauthorized :
                            status == 403 ? BridgeTransportError.forbidden : .transport))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard continuation != nil else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline,
              chunk.count <= 256 * 1024 - data.count else {
            finish(.failure(BridgeTransportError.transport)); return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error == nil && ProcessInfo.processInfo.systemUptime < deadline
               ? .success(data) : .failure(BridgeTransportError.transport))
    }
}
