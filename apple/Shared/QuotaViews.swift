import SwiftUI

enum DockTheme {
    static let graphite = Color(red: 0.08, green: 0.10, blue: 0.11)
    static let mint = Color(red: 0.43, green: 0.94, blue: 0.74)
}

struct RemainingBar: View {
    let window: QuotaWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label).lineLimit(1)
                Spacer()
                Text(window.clampedRemaining.map { "\(Int($0))% left" } ?? "Unknown")
            }.font(.caption)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    if let remaining = window.clampedRemaining {
                        Capsule().fill(DockTheme.mint).frame(width: geometry.size.width * remaining / 100)
                    }
                }
            }.frame(height: 9)
            if let reset = window.resetsAt {
                Text("Reset: \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProviderCard: View {
    let provider: Provider
    let demo: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProviderIcon(id: provider.id)
                Text(provider.id.displayName).font(.headline)
                Spacer()
                if demo || provider.source == .demo { Text("DEMO").font(.caption).foregroundStyle(DockTheme.mint) }
            }
            Text(provider.plan ?? "Plan unknown").font(.caption).foregroundStyle(.secondary)
            if provider.id == .codex {
                Text("Codex allowance · not total ChatGPT usage").font(.caption2).foregroundStyle(.secondary)
            }
            if provider.state != .available { Text("Usage unavailable").foregroundStyle(.secondary) }
            if provider.isStale() { Text(provider.observedAt == nil ? "Not observed" : "Stale · over 15 minutes old").font(.caption).foregroundStyle(.orange) }
            ForEach(provider.windows) { RemainingBar(window: $0) }
            if provider.windows.isEmpty { Text("Remaining unknown").font(.caption) }
            if let observed = provider.observedAt {
                Text("Observed \(observed.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}
