import Foundation
import Combine
import StoreKit
import SwiftUI

// Small contract values shared by the coordinator and its boundary tests.
enum PurchasePolicy {
    static let productIDs = ["com.quotadock.app.plus.monthly", "com.quotadock.app.pro.monthly"]
    static func eligible(productID: String, autoRenewable: Bool, verified: Bool,
                         owner: UUID?, account: UUID) -> Bool {
        verified && autoRenewable && productIDs.contains(productID) && owner == account
    }
    static func receiptBody(_ jws: String) throws -> [String: Any] {
        guard !jws.isEmpty, jws.utf8.count <= 24_000 else { throw SnapshotError.invalid }
        let body: [String: Any] = ["signedTransactionInfo": jws]
        guard try JSONSerialization.data(withJSONObject: body).count <= 24_000 else {
            throw SnapshotError.invalid
        }
        return body
    }
    static func acceptedTier(_ data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["tier", "periodId", "expiresAt"]),
              let tier = root["tier"] as? String, ["free", "plus", "pro"].contains(tier) else {
            throw SnapshotError.invalid
        }
        let period = root["periodId"] as? String
        guard root["periodId"] is NSNull || (period != nil && !period!.isEmpty) else {
            throw SnapshotError.invalid
        }
        var expiry: Date?
        if let text = root["expiresAt"] as? String {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiry = parser.date(from: text)
            if expiry == nil { parser.formatOptions = [.withInternetDateTime]; expiry = parser.date(from: text) }
            guard expiry != nil else { throw SnapshotError.invalid }
        } else if !(root["expiresAt"] is NSNull) { throw SnapshotError.invalid }
        guard tier == "free" ? (period == nil && expiry == nil) : (period != nil && expiry != nil) else {
            throw SnapshotError.invalid
        }
        return tier
    }
}

struct PurchaseContextIdentity: Equatable {
    let baseURL: URL
    let bearer: String
    let accountToken: UUID
}

@MainActor
final class PurchasesModel: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Purchases unavailable. Connect to a verified cloud account."
    @Published private(set) var available = false
    private var client: CloudClient?
    private var identity: PurchaseContextIdentity?
    private var revision = 0
    private var operations = 0
    private var inFlight: [UInt64: Date] = [:]
    private var newerUpdates: [UInt64: VerificationResult<StoreKit.Transaction>] = [:]
    private var onVerified: (() async -> Void)?
    private var onUnauthorized: (() -> Void)?
    private var listener: Task<Void, Never>?
    private var recovery: Task<Void, Never>?

    init() {
        // Do not bind strong self across the endless iterator's next suspension.
        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.accept(result)
            }
        }
    }
    deinit { listener?.cancel(); recovery?.cancel() }

    func configure(client: CloudClient?, accountToken: UUID?, available: Bool,
                   onUnauthorized: @escaping () -> Void = {},
                   onVerified: @escaping () async -> Void) {
        let next: PurchaseContextIdentity?
        if available, let client, let bearer = client.token, !bearer.isEmpty, let accountToken {
            next = PurchaseContextIdentity(baseURL: client.baseURL, bearer: bearer, accountToken: accountToken)
        } else { next = nil }
        let changed = next != identity
        if changed {
            revision += 1
            recovery?.cancel(); recovery = nil
            inFlight.removeAll(); newerUpdates.removeAll(); products = []; operations = 0; busy = false
            status = next == nil ? "Purchases unavailable. Connect to a verified cloud account." : "Load subscription products to purchase."
        }
        identity = next; self.client = next == nil ? nil : client
        self.available = next != nil; self.onVerified = onVerified; self.onUnauthorized = onUnauthorized
        // A normal quota read must not replay every current entitlement again.
        // Reconnect (new session) and explicit Restore retry unconfirmed receipts.
        guard changed, next != nil, recovery == nil else { return }
        let current = revision
        recovery = Task { [weak self] in
            await self?.recover(current: current)
            if self?.revision == current { self?.recovery = nil }
        }
    }

    private func current(_ value: Int) -> Bool { value == revision && available && !Task.isCancelled }
    private func begin() { operations += 1; busy = true }
    private func end(_ value: Int) {
        guard value == revision else { return }
        operations -= 1; busy = operations > 0
    }

    func loadProducts() async {
        guard available, !busy else { return }
        let value = revision
        begin(); defer { end(value) }
        do {
            let fetched = try await Product.products(for: PurchasePolicy.productIDs)
            guard current(value) else { return }
            products = fetched.filter { PurchasePolicy.productIDs.contains($0.id) && $0.type == .autoRenewable
                && $0.subscription?.subscriptionPeriod.unit == .month && $0.subscription?.subscriptionPeriod.value == 1 }
                .sorted { $0.id < $1.id }
            status = products.count == PurchasePolicy.productIDs.count ? "Subscription products available." : "Some subscription products are unavailable. Try again later."
        } catch {
            if current(value) { status = "Subscription products could not be loaded. Try again later." }
        }
    }

    func purchase(_ product: Product) async {
        guard let identity, available, !busy else { return }
        guard PurchasePolicy.productIDs.contains(product.id), product.type == .autoRenewable,
              products.contains(where: { $0.id == product.id }) else {
            status = "This subscription product is unavailable."; return
        }
        let value = revision
        begin(); defer { end(value) }
        do {
            let result = try await product.purchase(options: [.appAccountToken(identity.accountToken)])
            guard current(value) else { return }
            switch result {
            case .success(let verification): await accept(verification)
            case .pending: status = "Purchase pending Apple approval. No entitlement has been confirmed."
            case .userCancelled: status = "Purchase cancelled."
            @unknown default: status = "Purchase outcome unavailable. Restore later to check."
            }
        } catch {
            if current(value) { status = "Purchase could not be completed. Restore later to check." }
        }
    }

    func restore() async {
        guard available, !busy else { return }
        let value = revision
        begin(); defer { end(value) }
        status = "Checking purchases. No entitlement has been confirmed."
        do {
            // Only an explicit Restore action may prompt for App Store synchronization.
            try await AppStore.sync()
            guard current(value) else { return }
            await recover(current: value)
        } catch {
            if current(value) { status = "Restore could not complete. Check your Apple account and connection, then try again." }
        }
    }

    private func recover(current value: Int) async {
        var seen: [UInt64: Date] = [:]
        var found = false
        for await result in StoreKit.Transaction.unfinished {
            guard current(value) else { return }
            found = true
            if case .verified(let transaction) = result { seen[transaction.id] = transaction.signedDate }
            await accept(result)
        }
        for await result in StoreKit.Transaction.currentEntitlements {
            guard current(value) else { return }
            found = true
            if case .verified(let transaction) = result,
               let prior = seen[transaction.id], prior >= transaction.signedDate { continue }
            await accept(result)
        }
        if !found, current(value) {
            status = "No unfinished or current subscriptions were found. Server account status remains authoritative."
        }
    }

    private func accept(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard let identity, let client, available else { return }
        let value = revision
        guard case .verified(let transaction) = result else {
            status = "Apple transaction signature could not be verified. No entitlement was confirmed."; return
        }
        guard PurchasePolicy.eligible(productID: transaction.productID,
            autoRenewable: transaction.productType == .autoRenewable, verified: true,
            owner: transaction.appAccountToken, account: identity.accountToken) else {
            status = "This transaction is not a supported subscription for this cloud account. No entitlement was confirmed."; return
        }
        if let processing = inFlight[transaction.id] {
            // A refund/revocation can update the same transaction during delivery.
            // Deduplicate replays, but retain the newest signed update for another pass.
            if transaction.signedDate > processing {
                if case .verified(let queued)? = newerUpdates[transaction.id], queued.signedDate >= transaction.signedDate { return }
                newerUpdates[transaction.id] = result
            }
            return
        }
        inFlight[transaction.id] = transaction.signedDate
        begin()
        defer {
            if revision == value {
                inFlight.removeValue(forKey: transaction.id)
                if let next = newerUpdates.removeValue(forKey: transaction.id) {
                    Task { [weak self] in
                        guard let self, self.current(value) else { return }
                        await self.accept(next)
                    }
                }
            }
            end(value)
        }
        do {
            let body = try PurchasePolicy.receiptBody(result.jwsRepresentation)
            let data = try await client.request("v2/subscriptions/verify", method: "POST", body: body)
            let tier = try PurchasePolicy.acceptedTier(data)
            guard current(value) else { return }
            // Deliver a queued newer refund/revocation before acknowledging this ID.
            guard newerUpdates[transaction.id] == nil else { return }
            // Server acceptance, including free (expired/refunded), is required before finish.
            await transaction.finish()
            guard current(value) else { return }
            status = tier == "free" ? "Server accepted the transaction; no paid entitlement was confirmed." : "Server accepted the transaction. Refreshing authoritative account status."
            await onVerified?()
        } catch {
            if current(value) {
                if case CloudHTTPError.unauthorized = error {
                    let rejected = onUnauthorized
                    configure(client: nil, accountToken: nil, available: false, onVerified: {})
                    rejected?()
                    status = "Sign in again before retrying transaction delivery. The Apple transaction remains unfinished."
                    return
                }
                status = "Server verification could not be confirmed. No new paid status applied; reconnect or restore to retry delivery."
            }
        }
    }
}

struct SubscriptionOption: Identifiable {
    let id: String
    let name: String
    let price: String
}

// Prices come from StoreKit. This panel only displays offers; it never grants a tier.
struct SubscriptionPanel: View {
    let available: Bool
    let busy: Bool
    let status: String
    let options: [SubscriptionOption]
    let load: () -> Void
    let purchase: (String) -> Void
    let restore: () -> Void
    var body: some View {
        Section("QuotaDock 구독") {
            Text(status).font(.callout).accessibilityLabel("구독 상태: \(status)")
            if available {
                ForEach(options) { option in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(option.name).font(.headline)
                        Text(option.id == PurchasePolicy.productIDs[0] ?
                            "계정 10개 · 1시간 간격 · Live 구독 기간당 5회" :
                            "계정 등록 무제한 · 20–120분 간격 · Live 하루 5회")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("\(option.price) / 월 · \(option.name) 구독") { purchase(option.id) }
                            .disabled(busy)
                    }.padding(.vertical, 4)
                }
                if options.isEmpty { Text("Apple에서 상품을 불러온 뒤 가격을 확인하세요.").font(.caption) }
            } else {
                Text("Apple 로그인, 서버 검증 설정, App Store 상품 준비가 필요합니다. 현재 구매할 수 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("상품 다시 불러오기", action: load).disabled(!available || busy)
            Button("구매 복원", action: restore).disabled(!available || busy)
            if busy { ProgressView("처리 중 · 서버 확인 전에는 권한을 적용하지 않습니다.") }
            Text("구독을 구매하면 매월 자동 갱신되며 Apple 계정에 요금이 청구됩니다. 다음 갱신 전까지 Apple 구독 설정에서 취소할 수 있습니다. AI 제공업체의 추가 사용량을 판매하는 것이 아닙니다. 클라우드 계정 삭제는 Apple 구독을 취소하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Apple 구독 관리", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            Link("개인정보·데이터 안내", destination: URL(string: "https://usage.mvtp.cloud/#privacy")!)
            Link("표준 이용약관 (Apple EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }
    }
}

struct SubscriptionsView: View {
    @ObservedObject var store: PurchasesModel
    var body: some View {
        SubscriptionPanel(available: store.available, busy: store.busy, status: store.status,
            options: store.products.map { SubscriptionOption(id: $0.id, name: $0.displayName, price: $0.displayPrice) },
            load: { Task { await store.loadProducts() } },
            purchase: { id in
                guard let product = store.products.first(where: { $0.id == id }) else { return }
                Task { await store.purchase(product) }
            }, restore: { Task { await store.restore() } })
    }
}

#if DEBUG
// Presentation-only samples: no StoreKit product, login, receipt or entitlement.
struct SubscriptionsPreview: View {
    let state: String
    var body: some View {
        NavigationStack {
            Form {
                Text("DEMO · UI sample only. No purchase is possible.").font(.caption)
                SubscriptionPanel(available: state != "purchases-unavailable", busy: state == "purchases-pending",
                    status: state == "purchases-pending" ? "구매 검증 중입니다. 서버 확인 전까지 유료 권한을 적용하지 않습니다." :
                        state == "purchases-error" ? "서버 검증을 확인하지 못했습니다. 구매 복원으로 다시 시도하세요. 마지막 사용량은 유지됩니다." :
                        state == "purchases-unavailable" ? "현재 구매할 수 없습니다." : "상품·가격은 화면 예시입니다. 실제 결제 기능은 연결되어 있지 않습니다.",
                    options: [SubscriptionOption(id: PurchasePolicy.productIDs[0], name: "Plus", price: "₩3,990 예시"),
                              SubscriptionOption(id: PurchasePolicy.productIDs[1], name: "Pro", price: "가격 미정")],
                    load: {}, purchase: { _ in }, restore: {})
            }.navigationTitle("구독")
        }
    }
}
#endif
