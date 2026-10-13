import SwiftUI

// Explicit layout keeps the same presentation usable outside WidgetKit.
enum WidgetSurface { case small, medium, large, rectangular, circular, inline }

struct ProviderWidgetContent: View {
    let snapshot: Snapshot?
    let providerID: ProviderID
    let date: Date
    let surface: WidgetSurface

    private var provider: Provider? { snapshot?.providers.first { $0.id == providerID } }
    private var window: QuotaWindow? { provider?.displayWindows.first }
    private var value: String { window?.remainingPercentText ?? "?" }
    private var demo: Bool { snapshot?.demo == true || provider?.source == .demo }
    private var freshness: String {
        guard let provider, let observed = provider.observedAt else { return "Not observed" }
        let stamp = observed.formatted(date: .abbreviated, time: .shortened)
        return "\(provider.isStale(at: date) ? "Stale" : "Observed") · \(stamp)"
    }

    var body: some View {
        Group {
            switch surface {
            case .inline:
                Text("\(demo ? "DEMO · " : "")\(providerID.displayName) \(value == "?" ? "unknown" : value + " left") · \(provider?.observedAt == nil ? "not observed" : provider?.isStale(at: date) == true ? "stale" : "cached")")
            case .circular:
                VStack(spacing: 1) {
                    if demo { Text("DEMO").font(.system(size: 9)) }
                    else { ProviderIcon(id: providerID, size: 12) }
                    Text(value).font(.headline).monospacedDigit()
                    Text(value == "?" ? "Unknown" : provider?.isStale(at: date) == true ? "Stale" : "left").font(.system(size: 9))
                }
            case .rectangular:
                VStack(alignment: .leading, spacing: 3) {
                    header(compact: true)
                    HStack {
                        Text(window?.label ?? "Remaining").lineLimit(1)
                        Spacer(minLength: 3)
                        Text(value == "?" ? "Unknown" : value + " left").monospacedDigit().fixedSize()
                    }.font(.caption)
                    Text(freshness).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    header(compact: false)
                    Text(provider?.plan ?? "Plan unknown").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if let provider {
                        ForEach(Array(provider.displayWindows.prefix(surface == .medium ? 2 : 1))) { window in
                            WidgetQuotaBar(window: window)
                        }
                        if provider.windows.isEmpty { Text("Remaining unknown").font(.caption) }
                    } else { Text("No cached quota").font(.caption) }
                    Spacer(minLength: 0)
                    Text(freshness).font(.caption2).foregroundStyle(.secondary).lineLimit(surface == .medium ? 1 : 2)
                    Text(provider == nil ? "No stored observation" : surface == .medium ? "Cached · first account · first 2 windows" : "Cached · first account / window")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(surface == .medium ? 1 : 2).minimumScaleFactor(0.85)
                    if providerID == .codex && surface == .medium {
                        Text("Not total ChatGPT usage").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("First cached account; compact widgets show the first window. \(freshness). Open QuotaDock for all accounts. Codex is not total ChatGPT usage.")
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 5) {
            ProviderIcon(id: providerID, size: compact ? 14 : 18)
            Text(providerID.displayName).font(compact ? .caption : .headline).lineLimit(1)
            Spacer(minLength: 0)
            if demo { Text("DEMO").font(.caption2).fixedSize() }
        }
    }
}

struct WidgetQuotaBar: View {
    let window: QuotaWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(window.label).lineLimit(1)
                Spacer(minLength: 0)
                Text(window.remainingPercentText.map { "\($0) left" } ?? "Unknown")
                    .monospacedDigit().fixedSize()
            }.font(.caption)
            if let remaining = window.clampedRemaining {
                ProgressView(value: remaining, total: 100).tint(DockTheme.mint)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct OverviewWidgetContent: View {
    let snapshot: Snapshot?
    let date: Date
    let surface: WidgetSurface

    var body: some View {
        VStack(alignment: .leading, spacing: surface == .large ? 12 : 5) {
            HStack {
                Text("QuotaDock · remaining").font(.caption).bold()
                Spacer(minLength: 2)
                if snapshot?.demo == true { Text("DEMO").font(.caption2) }
            }
            ForEach([ProviderID.claude, .codex, .gemini, .grok], id: \.rawValue) { id in
                let provider = snapshot?.providers.first { $0.id == id }
                let window = provider?.displayWindows.first
                HStack(spacing: 7) {
                    ProviderIcon(id: id, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(id.displayName).bold().fixedSize()
                            Text(provider?.observedAt == nil ? "Not observed" : provider?.isStale(at: date) == true ? "Stale" : "Cached")
                                .foregroundStyle(.secondary).lineLimit(1)
                        }.font(.caption2)
                        if let remaining = window?.clampedRemaining {
                            ProgressView(value: remaining, total: 100).tint(DockTheme.mint).accessibilityHidden(true)
                        }
                        if surface == .large {
                            Text(provider?.observedAt.map { "Observed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No observation")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(window?.remainingPercentText ?? "Unknown")
                        .font(.caption2).monospacedDigit().fixedSize()
                }.accessibilityElement(children: .combine)
            }
            Text("Cached · first account / window per provider").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            if surface == .large {
                Text("Codex is not total ChatGPT usage. Open QuotaDock for all accounts and windows.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
