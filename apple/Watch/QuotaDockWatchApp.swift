import SwiftUI

@main
struct QuotaDockWatchApp: App {
    var body: some Scene { WindowGroup { WatchDashboard() } }
}

struct WatchDashboard: View {
    @State private var snapshot = SnapshotStore.load()
    @State private var demo = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("QuotaDock").font(.headline)
                if demo || snapshot?.demo == true { Text("DEMO · sample data").foregroundStyle(DockTheme.mint) }
                if let snapshot {
                    ForEach(snapshot.providers) { ProviderCard(provider: $0, demo: snapshot.demo) }
                } else { Text("No readings. Pair and refresh on iPhone, then open both apps.") }
                Text("Last iPhone transfer · no direct Watch network fetch").font(.caption2).foregroundStyle(.secondary)
                Button(demo ? "Leave demo" : "Explore demo") {
                    demo.toggle()
                    snapshot = demo ? .preview : SnapshotStore.load()
                }
                Button("Reload local cache") { if !demo { snapshot = SnapshotStore.load() } }
            }
        }.background(DockTheme.graphite).tint(DockTheme.mint)
            .task { WatchSync.shared.start() }
            .onReceive(NotificationCenter.default.publisher(for: .snapshotUpdated).receive(on: RunLoop.main)) { _ in
                if !demo { snapshot = SnapshotStore.load() }
            }
    }
}
