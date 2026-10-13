import SwiftUI
#if os(iOS)
import UIKit
#endif

enum DockTheme {
    static let graphite = Color(red: 0.08, green: 0.10, blue: 0.11)
    #if os(iOS)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.10, blue: 0.11, alpha: 1) : UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)
    })
    static let mint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.43, green: 0.94, blue: 0.74, alpha: 1) : UIColor(red: 36/255, green: 107/255, blue: 75/255, alpha: 1)
    })
    #else
    static let background = graphite
    static let mint = Color(red: 0.43, green: 0.94, blue: 0.74)
    #endif
}

struct RemainingBar: View {
    let window: QuotaWindow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var remainingText: String {
        window.remainingPercentText.map { "\($0) remaining" } ?? "Remaining unknown"
    }

    private var stackedLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(window.label)
            Text(remainingText).monospacedDigit().fontWeight(.semibold)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stackedLabel
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(window.label).fixedSize()
                            Spacer(minLength: 12)
                            Text(remainingText).monospacedDigit().fontWeight(.semibold).fixedSize()
                        }
                        stackedLabel
                    }
                }
            }.font(.caption)
            if let remaining = window.clampedRemaining {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.10))
                        Capsule().fill(DockTheme.mint).frame(width: geometry.size.width * remaining / 100)
                    }
                }.frame(height: 12).accessibilityHidden(true)
            }
            if let reset = window.resetsAt {
                Text("Reset: \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.label)
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let remaining = remainingText.replacingOccurrences(of: "<0.01%", with: "Less than 0.01 percent")
        guard let reset = window.resetsAt else { return remaining }
        return "\(remaining). Reset: \(reset.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct ProviderCard: View {
    let provider: Provider
    let demo: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ProviderIcon(id: provider.id)
                Text(provider.id.displayName).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if demo || provider.source == .demo {
                    Text("DEMO").font(.caption).foregroundStyle(DockTheme.mint)
                        .accessibilityLabel("Demo sample data")
                }
            }
            Text(provider.plan.map { "Plan: \($0)" } ?? "Plan unknown")
                .font(.subheadline).foregroundStyle(.secondary)
            if provider.id == .codex {
                Text("Codex allowance · not total ChatGPT usage").font(.caption2).foregroundStyle(.secondary)
            }
            if provider.state != .available { Text("Usage unavailable").foregroundStyle(.secondary) }
            if provider.isStale() {
                Text(provider.observedAt == nil ? "Not observed" : "Stale · over 15 minutes old")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
            }
            ForEach(provider.displayWindows) { RemainingBar(window: $0) }
            if provider.windows.isEmpty { Text("Remaining unknown").font(.caption) }
            if let observed = provider.observedAt {
                Text("Observed \(observed.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
            }
        }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }
    }
}
