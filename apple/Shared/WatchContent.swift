import SwiftUI

// Shared with the DEBUG iPhone host: no connectivity or credentials in this view.
struct WatchContent: View {
    @Environment(\.locale) private var locale
    let snapshot: Snapshot?
    let savedAt: Date?
    let demo: Bool
    let toggleDemo: () -> Void
    let reloadCache: () -> Void

    var body: some View {
        let _ = locale
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("QuotaDock").font(.headline)
                if demo || snapshot?.demo == true {
                    Text(DockL10n.text("DEMO · sample data, not live usage")).foregroundStyle(DockTheme.mint)
                }
                Text(DockL10n.text("Cached readings · not live")).font(.caption)
                if let snapshot {
                    if snapshot.providers.isEmpty {
                        Text(DockL10n.text("No provider readings in this snapshot. Refresh on iPhone."))
                    }
                    if !demo && !snapshot.demo {
                        Text(DockL10n.format("Snapshot prepared on iPhone: %@", DockL10n.date(snapshot.generatedAt)))
                            .font(.caption2).foregroundStyle(.secondary)
                        if let savedAt {
                            Text(DockL10n.format("Saved on Watch: %@", DockL10n.date(savedAt)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(snapshot.providers) { ProviderCard(provider: $0, demo: snapshot.demo) }
                    Text(DockL10n.text("Observed times belong to each provider. Stale readings are over 15 minutes old; missing observation times mean freshness is unknown."))
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(DockL10n.text("No readable local cache"))
                    Text(DockL10n.text("Pair with iPhone, refresh there, then open both apps. A cache may also be unavailable before the first unlock after restart."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(DockL10n.text("Works offline with saved data. Watch cannot fetch usage or sign in. Refresh on iPhone for new readings; transfer may be delayed and is not guaranteed."))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(DockL10n.text("First account per provider only")).font(.caption2).foregroundStyle(.secondary)
                Button(DockL10n.text(demo ? "Leave demo" : "Explore demo"), action: toggleDemo)
                Button(DockL10n.text("Reload local cache"), action: reloadCache).disabled(demo)
                Text(DockL10n.text("Reload only reads this Watch’s cache; it does not request an iPhone refresh."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.background(DockTheme.graphite).tint(DockTheme.mint).preferredColorScheme(.dark)
    }
}
