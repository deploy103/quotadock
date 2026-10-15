import SwiftUI

@main
struct QuotaDockWatchApp: App {
    var body: some Scene { WindowGroup { WatchDashboard() } }
}

struct WatchDashboard: View {
    @State private var snapshot = SnapshotStore.load()
    @State private var savedAt = SnapshotStore.savedAt
    @State private var locale = DockL10n.locale
    @State private var demo = false
    var body: some View {
        WatchContent(snapshot: snapshot, savedAt: savedAt, demo: demo, toggleDemo: {
            demo.toggle()
            if demo { snapshot = .preview } else { reload() }
        }, reloadCache: { if !demo { reload() } })
            .environment(\.locale, locale)
            .task { WatchSync.shared.start() }
            .onReceive(NotificationCenter.default.publisher(for: .snapshotUpdated).receive(on: RunLoop.main)) { _ in
                locale = DockL10n.locale
                if !demo { reload() }
            }
    }

    private func reload() {
        snapshot = SnapshotStore.load()
        savedAt = SnapshotStore.savedAt
    }
}
