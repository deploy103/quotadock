import SwiftUI
#if os(iOS)
import UIKit
#endif

// Translate only at the presentation boundary. Model values and diagnostics stay canonical.
enum QuotaPresentation {
    static func window(_ window: QuotaWindow) -> String {
        switch window.label {
        case "Session", "Weekly", "Monthly", "Daily", "Credits", "Pro", "Flash", "Flash Lite",
             "5-hour", "7-day", "Pro tier", "Flash tier", "Flash Lite tier", "Additional", "Secondary":
            return DockL10n.text(window.label)
        default: return DockL10n.text("Quota window")
        }
    }

    static func percent(_ window: QuotaWindow) -> String? {
        guard let value = window.clampedRemaining else { return nil }
        if value > 0 && value < 0.01 { return "<0.01%" }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(DockL10n.locale)) + "%"
    }
}

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
    @Environment(\.locale) private var locale
    let window: QuotaWindow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var remainingText: String {
        QuotaPresentation.percent(window).map { DockL10n.format("%@ remaining", $0) } ?? DockL10n.text("Remaining unknown")
    }

    private var stackedLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(QuotaPresentation.window(window))
            Text(remainingText).monospacedDigit().fontWeight(.semibold)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stackedLabel
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(QuotaPresentation.window(window)).fixedSize()
                            Spacer(minLength: 12)
                            Text(remainingText).monospacedDigit().fontWeight(.semibold).fixedSize()
                        }
                        stackedLabel
                    }
                }
            }
            #if os(iOS)
            .font(.subheadline)
            #else
            .font(.caption)
            #endif
            if let remaining = window.clampedRemaining {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.10))
                        Capsule().fill(DockTheme.mint).frame(width: geometry.size.width * remaining / 100)
                    }
                }.frame(height: 12).accessibilityHidden(true)
            }
            if let reset = window.resetsAt {
                Text(reset <= Date() ? DockL10n.text("Reset passed · awaiting observation") :
                    DockL10n.format("Reset: %@", DockL10n.date(reset)))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(QuotaPresentation.window(window))
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let remaining = remainingText.replacingOccurrences(of: "<0.01%", with: DockL10n.text("Less than 0.01 percent"))
        guard let reset = window.resetsAt else { return remaining }
        return DockL10n.format("%@. Reset: %@", remaining, DockL10n.date(reset))
    }
}

struct ProviderCard: View {
    @Environment(\.locale) private var locale
    let provider: Provider
    let demo: Bool
    var accountLabel: String? = nil
    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ProviderIcon(id: provider.id)
                Text(provider.id.displayName).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if demo || provider.source == .demo {
                    Text(DockL10n.text("DEMO")).font(.caption).foregroundStyle(DockTheme.mint)
                        .accessibilityLabel(DockL10n.text("Demo sample data"))
                }
            }
            if let accountLabel {
                Text(accountLabel).font(.subheadline)
            }
            Text(provider.plan.map { DockL10n.format("Plan: %@", $0) } ?? DockL10n.text("Plan unknown"))
                .font(.subheadline).foregroundStyle(.secondary)
            if provider.id == .codex {
                Text(DockL10n.text("Codex allowance · not total ChatGPT usage")).font(.caption).foregroundStyle(.secondary)
            }
            if provider.state != .available { Text(DockL10n.text("Usage unavailable")).foregroundStyle(.secondary) }
            if provider.isStale() {
                Text(DockL10n.text(provider.observedAt == nil ? "Not observed" : "Stale · over 15 minutes old"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
            }
            ForEach(provider.displayWindows) { RemainingBar(window: $0) }
            if provider.windows.isEmpty { Text(DockL10n.text("Remaining unknown")).font(.caption) }
            if let observed = provider.observedAt {
                Text(DockL10n.format("Observed %@", DockL10n.date(observed))).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }
    }
}
