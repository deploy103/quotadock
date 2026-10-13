import Foundation
import WatchConnectivity
import WidgetKit

final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    private override init() { super.init() }
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func send(_ snapshot: Snapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? snapshot.sanitized.encoded(),
              data.count <= SnapshotStore.maximumPayloadBytes,
              (try? Snapshot.decode(data)) != nil else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        if let snapshot = SnapshotStore.load() { send(snapshot) }
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
