import Foundation
import WatchConnectivity
import WidgetKit

// A latest-value outbox, not a delivery acknowledgement. Only sanitized quota
// bytes cross this boundary; activation always replaces memory with phone disk.
struct WatchTransfer {
    private(set) var pending: Data?

    mutating func enqueue(_ snapshot: Snapshot) {
        pending = Self.payload(snapshot)
    }

    mutating func reconcile(phoneSnapshot: Snapshot?, at date: Date = Date()) {
        enqueue(phoneSnapshot ?? Snapshot(schemaVersion: 1, generatedAt: date,
                                          demo: false, providers: []))
    }

    mutating func accepted() { pending = nil }

    private static func payload(_ snapshot: Snapshot) -> Data? {
        guard let data = try? snapshot.sanitized.encoded(),
              data.count <= SnapshotStore.maximumPayloadBytes,
              (try? Snapshot.decode(data)) != nil else { return nil }
        return data
    }
}

final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    // Access only on the main queue, alongside the phone's cache mutations.
    private var transfer = WatchTransfer()
    private override init() { super.init() }
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func send(_ snapshot: Snapshot) {
        #if os(iOS)
        guard WCSession.isSupported() else { return }
        onMain {
            self.transfer.enqueue(snapshot)
            self.flush(WCSession.default)
        }
        #endif
    }
    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread { action() } else { DispatchQueue.main.async(execute: action) }
    }
    private func flush(_ session: WCSession) {
        guard session.activationState == .activated, let data = transfer.pending else { return }
        do {
            try session.updateApplicationContext(["snapshot": data])
            transfer.accepted()
        } catch {
            // Keep the latest intention for a later send/activation; acceptance
            // by WCSession still does not promise immediate OS delivery.
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        guard activationState == .activated, error == nil else { return }
        onMain {
            // This is authoritative companion-phone state, never Watch-local
            // absence. Reconcile even after restart, when no outbox survives.
            self.transfer.reconcile(phoneSnapshot: SnapshotStore.load())
            self.flush(session)
        }
        #endif
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if os(watchOS)
        guard let data = applicationContext["snapshot"] as? Data,
              data.count <= SnapshotStore.maximumPayloadBytes,
              let snapshot = try? Snapshot.decode(data) else { return }
        // WCSession callbacks are not main-thread callbacks. Do not announce a
        // new cache (or reload widgets) if persistence failed, e.g. before unlock.
        do { try SnapshotStore.save(snapshot) } catch { return }
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .snapshotUpdated, object: nil)
        }
        #endif
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

extension Notification.Name { static let snapshotUpdated = Notification.Name("snapshotUpdated") }
