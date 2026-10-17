# Native billing contract

Free supports 3 accounts/1 collector, QuotaDock Plus 10/3, and QuotaDock Pro 25/5. Target Korean
storefront prices are Plus KRW 2,990/month or 29,900/year and Pro KRW 5,990/month
or 59,900/year. These are configuration targets, never purchase-UI price fallbacks.
Every purchase price displayed by the native coordinator comes from StoreKit
`Product.displayPrice`; annual totals are shown directly, not divided by twelve.

Use exactly `com.quotadock.app.{plus,pro}.{monthly,annual}` in one Apple
subscription group. Only Plus monthly and annual may have a one-calendar-month
introductory free trial. Configure free-trial payment mode, month/value 1, and
periodCount 1. Never configure a Pro introductory offer. StoreKit eligibility
alone is insufficient: it can be true without a configured introductory offer.
Apple allows one introductory offer per person per subscription group, not one
per product, QuotaDock login, or billing cadence.

Existing backend Live/due policies remain unchanged. Plus's five Live sessions
refill monthly even on annual billing, not just once per annual renewal.

Products from different subscription groups are rejected. A promised trial is
checked again against freshly fetched offer metadata and asynchronous Apple
eligibility immediately before purchase; loss of that offer stops purchase and
asks for reload, rather than silently initiating ordinary paid billing. Price or
subscription-period changes also stop purchase. Apple controls the final purchase
sheet and eligibility; no app-local trial clock or paid entitlement is created.

Purchases, recovery and receipt delivery are available only when the authenticated
cloud client's base URL is the official HTTPS `usage.mvtp.cloud` origin (default
443 only, no credentials, custom path, query or fragment). The existing cloud
transport refuses redirects. Apple verification, exact appAccountToken ownership,
server acceptance before finish, duplicate coalescing, newer-update recovery and
revision-based logout invalidation remain authoritative.

## Integration

`iOS/BillingPolicy.swift` contains Foundation-only catalog, origin and trial
guards. `PortableTests/BillingContractTests.swift` contains the billing contract
matrix and runs in both the portable package and hosted native test target.
`Tests/PurchaseTests.swift` covers signed transaction ownership and server
acceptance independently of the new catalog decisions.
Portable policy tests do not validate the StoreKit coordinator or Apple services.

## Validation limits

On 2026-10-17, Xcode 27.1 compiled the final four-target iPhone/Watch/widget source.
All 110 hosted native units and four production onboarding UI tests passed;
the unchanged entitlement-read ownership/coalescing test remains included.
Six isolated presentation tests exercised monthly/annual Plus eligible/ineligible
display values, a Pro adversarial trial flag, EN/KO and accessibility3 text,
alongside UUID-aware shared widget/Watch content. These hosts use inert purchase
callbacks: they are not real eligibility queries, purchases, installed system
widgets or WatchConnectivity execution. Large cards scroll across viewports.

Nonroot Swift 6.1.3 Linux and macOS Foundation runs each passed 31 contracts,
including 160 trial combinations plus catalog/origin/stale-promise assertions.
Disposable PostgreSQL tests separately cover signed trial metadata and annual
monthly benefit boundaries. None establishes App Store Connect configuration.

Actual Apple sandbox follow-up must cover configured offers and eligibility,
changed eligibility/price, pending/cancelled purchase, restore/refund, logout
during delivery, original transaction ownership and deleted-account recovery.
Local or synthetic metadata must never be accepted by the production server.

## Apple references reviewed

- https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/
- https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer

The product review PDF's account-oriented cards and clear annual billing are
adopted. Explicit user policy supersedes its deferred-Pro proposal. No history,
notifications, slower Free readings, or Live allowances are sold by these cards.
