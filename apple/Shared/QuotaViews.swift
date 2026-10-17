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
    static let graphite = Color(red: 16/255, green: 19/255, blue: 24/255)
    #if os(iOS)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 16/255, green: 19/255, blue: 24/255, alpha: 1) : UIColor(red: 244/255, green: 246/255, blue: 249/255, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 27/255, green: 32/255, blue: 40/255, alpha: 1) : .white
    })
    static let border = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 44/255, green: 53/255, blue: 67/255, alpha: 1) : UIColor(red: 225/255, green: 230/255, blue: 238/255, alpha: 1)
    })
    static let mint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 161/255, green: 181/255, blue: 255/255, alpha: 1) : UIColor(red: 52/255, green: 92/255, blue: 219/255, alpha: 1)
    })
    #else
    static let background = graphite
    static let surface = Color(red: 27/255, green: 32/255, blue: 40/255)
    static let border = Color(red: 44/255, green: 53/255, blue: 67/255)
    static let mint = Color(red: 161/255, green: 181/255, blue: 255/255)
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
        VStack(alignment: .leading, spacing: 8) {
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
                }.frame(height: 10).accessibilityHidden(true)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                #if os(iOS)
                ProviderIcon(id: provider.id, size: 28)
                    .padding(8)
                    .background(DockTheme.background, in: RoundedRectangle(cornerRadius: 12))
                #else
                ProviderIcon(id: provider.id, size: 18)
                #endif
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.id.displayName).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let accountLabel {
                        Text(accountLabel).font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .privacySensitive()
                    }
                    Text(provider.plan.map { DockL10n.format("Plan: %@", $0) } ?? DockL10n.text("Plan unknown"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                #if os(iOS)
                if demo || provider.source == .demo {
                    Text(DockL10n.text("DEMO")).font(.caption2.weight(.semibold)).foregroundStyle(DockTheme.mint)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(DockTheme.mint.opacity(0.08), in: Capsule())
                        .accessibilityLabel(DockL10n.text("Demo sample data"))
                }
                #endif
            }
            if provider.state != .available { Text(DockL10n.text("Usage unavailable")).foregroundStyle(.secondary) }
            if provider.isStale() {
                Text(DockL10n.text(provider.observedAt == nil ? "Not observed" : "Stale · over 15 minutes old"))
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
            }
            ForEach(provider.displayWindows) { RemainingBar(window: $0) }
            if provider.windows.isEmpty { Text(DockL10n.text("Remaining unknown")).font(.caption) }
            if let observed = provider.observedAt {
                Text(DockL10n.format("Observed %@", DockL10n.date(observed))).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if provider.id == .codex {
                Text(DockL10n.text("Codex allowance · not total ChatGPT usage")).font(.caption).foregroundStyle(.secondary)
            }
        }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            #if os(iOS)
            .padding(18)
            #else
            .padding(10)
            #endif
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DockTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(DockTheme.border, lineWidth: 1) }
    }
}
