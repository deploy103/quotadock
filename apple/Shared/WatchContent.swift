import SwiftUI

// Shared with the DEBUG iPhone host: no connectivity or credentials in this view.
struct WatchContent: View {
    let snapshot: Snapshot?
    let savedAt: Date?
    let demo: Bool
    let toggleDemo: () -> Void
    let reloadCache: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("QuotaDock").font(.headline)
                if demo || snapshot?.demo == true {
                    Text("DEMO · sample data, not live usage").foregroundStyle(DockTheme.mint)
                }
                Text("Cached readings · not live").font(.caption)
                if let snapshot {
                    if snapshot.providers.isEmpty {
                        Text("No provider readings in this snapshot. Refresh on iPhone.")
                    }
                    if !demo && !snapshot.demo {
                        Text("Snapshot prepared on iPhone: \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let savedAt {
                            Text("Saved on Watch: \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(snapshot.providers) { ProviderCard(provider: $0, demo: snapshot.demo) }
                    Text("Observed times belong to each provider. Stale readings are over 15 minutes old; missing observation times mean freshness is unknown.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("No readable local cache")
                    Text("Pair with iPhone, refresh there, then open both apps. A cache may also be unavailable before the first unlock after restart.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Works offline with saved data. Watch cannot fetch usage or sign in. Refresh on iPhone for new readings; transfer may be delayed and is not guaranteed.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("First account per provider only").font(.caption2).foregroundStyle(.secondary)
                Button(demo ? "Leave demo" : "Explore demo", action: toggleDemo)
                Button("Reload local cache", action: reloadCache).disabled(demo)
                Text("Reload only reads this Watch’s cache; it does not request an iPhone refresh.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.background(DockTheme.graphite).tint(DockTheme.mint).preferredColorScheme(.dark)
    }
}
