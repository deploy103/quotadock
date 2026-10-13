import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    var cached = false
}

struct QuotaTimeline: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), snapshot: context.isPreview ? .preview : SnapshotStore.load(), cached: !context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let entry = QuotaEntry(date: Date(), snapshot: SnapshotStore.load(), cached: true)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    let providerID: ProviderID
    @Environment(\.widgetFamily) private var family
    private var provider: Provider? { entry.snapshot?.providers.first { $0.id == providerID } }
    private var isDemo: Bool { entry.snapshot?.demo == true || provider?.source == .demo }
    private var visibleWindows: [QuotaWindow] {
        let windows = provider?.displayWindows ?? []
        #if os(iOS)
        if family == .systemMedium { return windows }
        #endif
        return Array(windows.prefix(1))
    }
    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack(spacing: 2) {
                    if isDemo { Text("DEMO").font(.caption2) }
                    else { ProviderIcon(id: providerID, size: 14) }
                    Text(provider?.displayWindows.first?.clampedRemaining.map { "\(Int($0))%" } ?? "?").font(.headline)
                    Text(provider?.displayWindows.first?.clampedRemaining == nil ? "Unknown" : (provider?.isStale(at: entry.date) == true ? "Stale" : "left")).font(.caption2)
                    if let observed = provider?.observedAt {
                        Text(observed.formatted(date: .omitted, time: .shortened)).font(.system(size: 9))
                    }
                }
            } else if family == .accessoryInline {
                Text("\(isDemo ? "DEMO " : "")\(providerID.displayName): \(provider?.displayWindows.first?.clampedRemaining.map { "\(Int($0))% left" } ?? "unknown")\(provider?.isStale(at: entry.date) == true ? " · stale" : "")\(provider?.observedAt.map { " · \($0.formatted(date: .omitted, time: .shortened))" } ?? "")")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        ProviderIcon(id: providerID, size: 16)
                        Text(providerID.displayName).font(family == .accessoryRectangular ? .caption : .headline)
                        Spacer(minLength: 2)
                        if isDemo { Text("DEMO").font(.caption2) }
                    }
                    Text(provider?.plan ?? "Plan unknown").font(.caption2).foregroundStyle(.secondary)
                    if let provider {
                        if provider.state != .available { Text("Unavailable").font(.caption2) }
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(visibleWindows) { window in
                                RemainingBar(window: QuotaWindow(id: window.id, label: window.label,
                                    remainingPercent: window.remainingPercent,
                                    resetsAt: family == .accessoryRectangular ? nil : window.resetsAt))
                            }
                        }
                        if provider.windows.isEmpty { Text("Remaining unknown").font(.caption) }
                        if provider.isStale(at: entry.date) { Text("Stale / not observed").font(.caption2) }
                        if let observed = provider.observedAt {
                            Text("Observed \(observed.formatted(date: .omitted, time: .shortened))").font(.caption2)
                        }
                    } else { Text("Open iPhone to pair").font(.caption) }
                    if family != .accessoryRectangular {
                        Text("Cached · first account").font(.caption2).foregroundStyle(.secondary)
                        if providerID == .codex { Text("Not total ChatGPT usage").font(.caption2) }
                    }
                }
            }
        }.containerBackground(DockTheme.background, for: .widget)
            .accessibilityHint("\(providerID.displayName), first cached account. Observed \(provider?.observedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never").")
    }
}

struct ProviderWidget: Widget {
    let providerID: ProviderID

    init() { self.init(providerID: .claude) }
    init(providerID: ProviderID) { self.providerID = providerID }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuotaDock.\(providerID.rawValue)", provider: QuotaTimeline()) { entry in
            QuotaWidgetView(entry: entry, providerID: providerID)
        }
        .configurationDisplayName("\(providerID.displayName) remaining")
        .description("Cached first account per provider. Open QuotaDock for all accounts and windows.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        #else
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
        #endif
    }
}

#if os(iOS)
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuotaDock.overview", provider: QuotaTimeline()) { entry in
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("QuotaDock · remaining").font(.caption).bold()
                    Spacer()
                    Text(entry.snapshot?.demo == true ? "DEMO" : "First accounts").font(.caption2)
                }
                ForEach([ProviderID.claude, .codex, .gemini, .grok], id: \.rawValue) { id in
                    let provider = entry.snapshot?.providers.first { $0.id == id }
                    let remaining = provider?.state == .available ? provider?.windows.first?.clampedRemaining : nil
                    HStack(spacing: 8) {
                        ProviderIcon(id: id, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(id.displayName).bold()
                                Text(provider?.plan ?? "Plan unknown").foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                                if provider?.isStale(at: entry.date) == true { Text("stale").foregroundStyle(.orange) }
                            }.font(.caption2)
                            if let observed = provider?.observedAt {
                                Text("Observed \(observed.formatted(date: .omitted, time: .shortened))").font(.caption2)
                            }
                            if let remaining {
                                ProgressView(value: remaining, total: 100).tint(DockTheme.mint)
                            } else { Text("Quota unknown").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Text(remaining.map { "\(Int($0))%" } ?? "—").font(.caption).monospacedDigit().frame(width: 38, alignment: .trailing)
                    }
                }
            }.containerBackground(DockTheme.background, for: .widget)
        }
        .configurationDisplayName("All AI allowances")
        .description("First quota window per provider. Codex is not total ChatGPT usage. Open the app for all windows and reset times.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
#endif

@main
struct QuotaWidgets: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        OverviewWidget()
        #endif
        ProviderWidget(providerID: .claude)
        ProviderWidget(providerID: .codex)
        ProviderWidget(providerID: .gemini)
        ProviderWidget(providerID: .grok)
    }
}
