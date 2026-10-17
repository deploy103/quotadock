import SwiftUI

struct SubscriptionOption: Identifiable {
    let id: String
    let name: String
    let price: String
    let tier: String
}

// Presentation only: prices and purchase eligibility are supplied by StoreKit.
// The isolated preview can use this view without creating a purchase client.
struct SubscriptionPanel: View {
    @Environment(\.locale) private var locale
    let available: Bool
    let busy: Bool
    let status: String
    let options: [SubscriptionOption]
    var currentTier: String? = nil
    let load: () -> Void
    let purchase: (String) -> Void
    let restore: () -> Void

    var body: some View {
        let _ = locale
        if available {
            Text(DockL10n.text(status)).font(.callout)
                .accessibilityLabel(DockL10n.format("Subscription status: %@", DockL10n.text(status)))
        }
        Section {
            ForEach(["free", "plus", "pro"], id: \.self) { tier in
                let option = options.first { $0.tier == tier }
                let current = currentTier == tier
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(option?.name ?? tier.capitalized).font(.title3.bold())
                        Spacer()
                        if current {
                            Text(DockL10n.text("Current plan"))
                                .font(.caption.weight(.semibold)).foregroundStyle(DockTheme.mint)
                        }
                    }
                    Text(tier == "free" ? DockL10n.text("Free") : option.map {
                        DockL10n.format("%@ / month", $0.price)
                    } ?? DockL10n.text("Price unavailable"))
                        .font(.title2.weight(.semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DockL10n.text(tier == "free" ? "3 accounts · every 2 hours" :
                            tier == "plus" ? "10 accounts · every hour" : "Unlimited accounts · every 20–120 minutes"))
                        Text(DockL10n.text(tier == "free" ? "10 early refreshes / KST day" :
                            tier == "plus" ? "5 Live sessions / subscription period" : "5 Live sessions / KST day"))
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if available, tier != "free", let option {
                        Button {
                            purchase(option.id)
                        } label: {
                            Text(DockL10n.text(current ? "Current plan" : "Subscribe"))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(current || busy || !available)
                        .accessibilityIdentifier("subscribe-\(tier)")
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan-\(tier)")
            }
        } header: {
            Text(DockL10n.text("Optional cloud"))
        } footer: {
            Text(DockL10n.text("Fresh readings require an online local collector. AI provider subscriptions are separate."))
        }
        if available && options.isEmpty {
            Button(DockL10n.text("Reload products"), action: load).disabled(busy)
        }
        if busy { ProgressView(DockL10n.text("Processing…")) }
        Section {
            DisclosureGroup(DockL10n.text("Purchase details and terms")) {
                if !available {
                    Text(DockL10n.text(status)).font(.callout)
                        .accessibilityLabel(DockL10n.format("Subscription status: %@", DockL10n.text(status)))
                }
                Text(DockL10n.text("Subscriptions renew monthly and are charged to your Apple account. Cancel in Apple subscription settings before the next renewal. This does not sell additional AI provider usage. Deleting your cloud account does not cancel your Apple subscription."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(DockL10n.text("Up to 50 accounts per refresh batch. Live lasts up to 30 minutes. Collection timing is not guaranteed."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(DockL10n.text("Reload products"), action: load).disabled(!available || busy)
                Link(DockL10n.text("Manage Apple subscriptions"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Link(DockL10n.text("Privacy and data"), destination: URL(string: "https://usage.mvtp.cloud/#privacy")!)
                Link(DockL10n.text("Standard terms (Apple EULA)"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            Button(DockL10n.text("Restore purchases"), action: restore).disabled(!available || busy)
        }
    }
}
