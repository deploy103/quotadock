import Foundation

/// StoreKit-independent decisions; no local entitlement or trial clock.
enum BillingPolicy {
    static let productIDs = ["com.quotadock.app.plus.monthly", "com.quotadock.app.pro.monthly",
                             "com.quotadock.app.plus.annual", "com.quotadock.app.pro.annual"]

    static func tier(_ id: String) -> String? {
        guard productIDs.contains(id) else { return nil }
        return id.contains(".plus.") ? "plus" : "pro"
    }

    static func annual(_ id: String) -> Bool { productIDs.contains(id) && id.hasSuffix(".annual") }

    static func officialOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "usage.mvtp.cloud"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && (url.path.isEmpty || url.path == "/") && url.query == nil && url.fragment == nil
    }

    static func offersTrial(productID: String, freeTrial: Bool, monthUnit: Bool,
                            periodValue: Int, periodCount: Int, eligible: Bool) -> Bool {
        tier(productID) == "plus" && freeTrial && monthUnit && periodValue == 1
            && periodCount == 1 && eligible
    }

    /// If a free month was promised, changed eligibility must stop, not start a paid purchase.
    static func mayPurchase(promisedTrial: Bool, currentTrial: Bool) -> Bool {
        !promisedTrial || currentTrial
    }
}
