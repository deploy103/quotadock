# QuotaDock native Apple apps

Small SwiftUI source tree targeting **iOS 17 / watchOS 10, Xcode 16+**. No runtime dependencies. XcodeGen 2.42+ is the only project-generation tool.

## Generate, build and test on a Mac

```sh
brew install xcodegen
cd apple
xcodegen generate
open QuotaDock.xcodeproj
# Pick an installed iPhone simulator (list with xcrun simctl list devices available).
xcodebuild -project QuotaDock.xcodeproj -scheme QuotaDock \
  -destination 'platform=iOS Simulator,name=iPhone 16' test CODE_SIGNING_ALLOWED=NO
xcodebuild -project QuotaDock.xcodeproj -target QuotaDockWatch \
  -sdk watchsimulator build CODE_SIGNING_ALLOWED=NO
xcodebuild -project QuotaDock.xcodeproj -target QuotaDockWatchWidgets \
  -sdk watchsimulator build CODE_SIGNING_ALLOWED=NO
```

Before physical-device builds, set `DEVELOPMENT_TEAM`, `BUNDLE_PREFIX`, and `APP_GROUP` in `project.yml` and regenerate. Defaults are `com.quotadock.app` and `group.com.quotadock.app`. Register the four bundle IDs (base, `.widgets`, `.watch`, `.watch.widgets`) and App Group with your team. Enable the group for all four targets. Enable **Sign In with Apple only for the main iOS App ID**, and configure the server's Apple audience to that exact bundle ID. Real sign-in requires the user's Apple Team/provisioning and reachable configured server; unsigned simulator CI only validates compilation, not authentication. The iPhone alone has separate `.bridge` and `.cloud` Keychain groups. Watch/widgets have **no token or Keychain entitlement**. App Groups are local to each device; WatchConnectivity bridges sanitized snapshots between devices.

XcodeGen embeds the iOS widget and modern single-target Watch app into the iPhone app; the Watch app embeds its WidgetKit extension. Generated plists, entitlements and project are ignored. No ATS exceptions, background modes, push capability, or insecure certificate bypass are supplied. The shared iOS/watchOS app icon is an opaque 1024px rendering of `web/favicon.svg`. Release/App Store distribution additionally needs listing artwork, team provisioning and device/OS review.

## Pair and use

Run the bridge behind a trusted, device-reachable HTTPS endpoint (valid TLS certificate), then enter its **base URL** and pairing bearer token in Pair. `/v1/snapshot` is appended. Never enter Claude/OpenAI/other provider credentials. URL and token are held together in device-only, after-first-unlock Keychain; no token goes to UserDefaults, snapshot cache, logs or Watch. Redirects are refused to prevent bearer forwarding. Plain HTTP, URL credentials, queries and fragments are rejected. Forget pairing removes the local token/cache; Watch can retain its old snapshot until a new transfer, and offline widgets can retain OS-rendered content.

iPhone fetches on foreground activation and manual/pull refresh. The bridge may return cached measurements. **All widgets are cache-only timeline readers**, never background bridge/provider/cloud clients. They have neither network client source nor Keychain entitlements. Timeline requests are hints, not guaranteed refresh intervals. Add the **All AI allowances** overview or individual provider widgets to **Home Screen or Today View**, or rectangular/circular/inline widgets on the Lock Screen. Overview shows four providers with icons, freshness and the first window; individual medium widgets show up to two windows plus the plan, while smaller surfaces show the first window. Open the app for every window and reset time. Watch Smart Stack widgets and complications use only the local cache. Open both paired apps and refresh iPhone to initiate WatchConnectivity transfer; no instantaneous/push update promise.

## Optional cloud (v2, server-verified tiers; pilot purchases closed)

Choose **Optional cloud account** and separately affirm quota-storage/account-metadata and local collector-processing consent before starting real Apple authorization. Both toggles default off and reset when the server URL or session changes; a missing consent prevents challenge requests as well as Apple authorization. Default server is `https://usage.mvtp.cloud`; the editable URL is stored locally and must be trusted HTTPS, with no URL credentials/query/fragment. There is no fake identity, provider login or OpenAI login. DNS, TLS, Apple capability/configuration and server failures are reported without exposing diagnostics.

The client POSTs `/v2/auth/challenge`, sets the AuthorizationServices request nonce to **exactly `challenge.nonce`**, requests no email/name scopes, and POSTs the returned identity JWT with the challenge ID and affirmative consent to `/v2/auth/apple`. Only the returned one-hour opaque session is persisted, in the iPhone-only device-only Keychain (`WhenUnlockedThisDeviceOnly`). No identity JWT or session is stored in quota caches, UserDefaults, Watch or widgets. Requests use ephemeral sessions, no cookies/cache, no redirects, streamed 256 KiB response bounds and 20-second resource timeouts.

`/v2/me` displays verified tier, limits, early-refresh and Live counters; `/v2/accounts` manages UUID slots (Free three, Plus ten, Pro uncapped registration, enforced server-side); `/v2/snapshot` preserves separate same-provider accounts and every window. Unconfigured pilot entitlements are Free only; purchase controls remain unavailable. Phone rows use account UUIDs, with an eight-character UUID label rather than an invented account name. Full sanitized account cache stays in the iPhone sandbox. **Watch/widgets intentionally receive only the first server-listed account per provider**, not all accounts; current server ordering is ascending account UUID. Do not treat these surfaces as account totals. Both caches preserve the original observation timestamp, not the fetch time. Server `lastError` is presented as fixed safe text; raw errors/names are not exported.

StoreKit 2 purchase/restore source requires `purchasesAvailable` and the UUID
`appAccountToken` from authenticated `/v2/me`. It loads only the known monthly
auto-renewable products and shows Apple's localized price. Apple signature and
account checks precede transient signed-transaction submission to the server;
only a valid accepted response permits `finish()`. Failed new deliveries remain
unfinished; expired/refunded acceptance does not grant paid access. A server read,
not the product ID, applies the tier. The app-lifetime update listener retains
newer signed changes to an in-flight transaction. New sessions recover unfinished
transactions/current entitlements; only explicit Restore calls `AppStore.sync`.
Context revisions reject stale completions on logout/server/session/account
switch. No receipt is logged, persisted, cached or transferred to Watch/widgets.
Account erasure does not cancel Apple's subscription. Purchase/restore, Ask to Buy,
renewal/refund and account-switch behavior still require actual StoreKit sandbox
and signed-device validation; see [release plan](../docs/release-plan.md).

Foreground automatic refresh honors Settings and submits `mode:auto`; manual/pull refresh submits `mode:force` (an early batch may use Free allowance). Requests use a fresh UUID idempotency key per user operation. Select 1–50 owned slots in **Refresh batch**, initially the first 50. That in-memory selection survives account-list reads, removes deleted slots, and resets on owner/logout changes. Registration above 50 does not block smaller batches. Live restores its authoritative server slot set and 30-minute wall deadline; stop it before changing targets. Hidden/locked apps pause requests, not the deadline.

Account and snapshot reads prefer tenant-scoped `/page` endpoints and traverse
ascending UUID cursors. Only a first-page 404 falls back to legacy endpoints;
malformed, duplicate, foreign, incomplete or changing lists retain the last
usable reading. A full read is bounded to 60 seconds, 8 MiB and 100 pages per
endpoint (5,000 slots), independent of the server's uncapped Pro registration.
If a full local snapshot exceeds 256 KiB, the offline cache explicitly retains
only the first 50 accounts without changing original observation timestamps.

A pending job means **waiting for the scoped local collector**, not updated quota. Pair/approve/revoke it using [collector setup](../bridge/cloud.md); provider credentials remain on the computer. Independent Claude/Codex/Grok accounts need explicit local durable-key mappings; Gemini remains one local account. The phone cannot obtain provider quotas directly without granted APIs, and does not collect/complete jobs. Pending requests poll their exact `/v2/jobs/:id`, every five seconds while foreground, with a 60-second polling deadline and bounded request timeout. Job ID, mode, targets and lease must remain consistent. Terminal replies are followed by one bounded account/snapshot read (separate 60-second limit); `completed` can mean failed collection, not fresh quota. Unknown/failure remains unknown and previous source observations remain visible. An old backend without status lookup fails waiting closed rather than guessing completion from observation timestamps.

Logout POSTs `/v2/auth/logout`; account erasure DELETEs `/v2/me` after destructive confirmation. Local sessions/caches are cleared immediately and old in-flight completions cannot restore them. Failed revocation/erasure is explicitly **not confirmed**; reconnect to retry account erasure (server sessions expire within one hour). Slot deletion uses the real DELETE endpoint and clears local caches before re-reading. Switching cloud/bridge owners clears both caches and sends an empty Watch snapshot; offline Watch and OS-rendered widgets may retain previously rendered content until delivery/reload. Switching to the bridge attempts server logout and never treats its legacy token as a cloud session.

Graphite/mint bars mean **remaining**, clamped to 0–100, never summed. Null is unknown, not exhausted. Plans are displayed as supplied by the sanitized contract; null is “Plan unknown.” Codex refers to the **Codex allowance under a ChatGPT plan**, not overall ChatGPT usage. Gemini window labels are preserved as model tiers. Unavailable/error providers remain visible, diagnostics are replaced with fixed safe text, and readings older than 15 minutes are stale. Reset dates are informational, not a quota promise.

“Explore demo” is explicitly labeled and stays in memory: it never overwrites live cache or transfers fabricated readings. Xcode/WidgetKit previews and placeholders use `Snapshot.preview`, with `demo: true` and `source: demo` everywhere. To see demo widgets on devices, use a bridge explicitly running demo mode.

## Architecture and verification

- `Shared/Snapshot.swift`: contract v1 Codable values, ISO8601 dates including fractions, explicit null re-encoding, 256 KiB bound, safe-message sanitization and demo samples.
- `Shared/Bridge.swift`: HTTPS pairing, Keychain and ephemeral URLSession client; rejects redirects/non-200/schema errors.
- `Shared/SnapshotStore.swift`: atomic sanitized JSON App Group cache.
- `Shared/WatchSync.swift`: latest application-context transfer, no secrets, Watch cache/timeline reload.
- `Shared/QuotaViews.swift`: reusable remaining bars/provider cards.
- `iOS/Cloud.swift`: real nonce-bound Apple/server authorization, independent Keychain session, v2 account-list decoding, sandbox full-slot cache, foreground collector-job requests and bounded job-ID polling.
- `iOS/Purchases.swift`: StoreKit product loading, UUID-bound purchase/restore, update recovery and server-accepted delivery. No client-side entitlement assignment.
- `iOS/`, `Watch/`, `Widgets/`: small native surfaces and timeline adapters.
- `Tests/ContractTests.swift`: public model decode/encode, nullable values, clamps, staleness, demo, schema/date/size rejection, URL restrictions, request authorization and response sanitization/status tests using URLProtocol (no real credentials or server).

The [prior CI run](https://github.com/quotadock-dev/quotadock/actions/runs/38460764173) generated the project with XcodeGen, built iPhone/Watch/WidgetKit, and passed 29 native XCTests on an iPhone simulator, plus 18 bridge/web and 10 imported skill tests on Node 22. Twelve captures were inspected: default, dark, unknown, settings, separate cloud consents, distinct-slot batch selection, individual/overview/accessory widget hosts, empty/stale Watch hosts and large Dynamic Type. Visual inspection caught and resolved preview-routing and truncated widget-footer defects after an earlier passing test run. The large-text capture verifies visible long labels, 0% and 0.75%; its lower content remains offscreen. The [native demo](../docs/assets/native-demo.png) is from this run. Screenshots show scrollable app content and shared-component hosts, not system widgets or a physical Watch.

The [purchase/job-status integration CI](https://github.com/quotadock-dev/quotadock/actions/runs/38469463457)
passed 34 native tests, iPhone/Watch/WidgetKit builds, 18 bridge/web tests and
10 imported skill tests. Sixteen captures were generated; five affected captures
were inspected: cloud consents and subscription unavailable/catalogue/verifying/
failure. An earlier passing run exposed globally disabled preview links and
ambiguous billing text; these were fixed and recaptured. This validates compilation,
contract guards and presentation, **not real StoreKit purchases or event delivery**.
Purchase samples use inert callbacks and display-only prices, never real products
or credentials. `--purchases-preview`, `--purchases-unavailable-preview`,
`--purchases-pending-preview` and `--purchases-error-preview` render those samples.

This is not physical-device validation. On a Mac, inspect embedding/signing in Xcode and test Keychain sharing, first-unlock fallback, Home/Today/Lock Screen layout, Watch pairing/transfer, complications and stale/offline readings. Small accessory layouts are deliberately terse; large Dynamic Type, long tier/plan labels and system widget rendering require device visual review. Unit tests do not establish real TLS, Keychain provisioning or WatchConnectivity delivery.

Regression cases cover same-provider slots, multiple windows/nulls, safe cache projections with fractional observation timestamps, duplicate/oversized/insecure input rejection, selected batches/ownership boundaries, fixed Live selections, missing consent and mode-switch cache/revision clearing. Debug-only `--unknown-preview`, `--settings-preview`, `--cloud-preview`, `--batch-preview`, `--widgets-preview`, `--widgets-overview-preview`, `--widgets-accessories-preview`, `--watch-preview`, `--watch-stale-preview` and `--accessibility-preview` enable deterministic UI captures. These isolated samples do not provide identity, session, entitlement or authentication bypass. Widget and Watch host galleries render the shared content inside iPhone-sized frames; they are not system WidgetKit layout or physical Watch evidence.

Real Apple sign-in, logout/erasure, collector completion, purchases and Watch delivery remain signed-device end-to-end gates with the user's Apple Team and trusted configured server. No provider account or Free Codex account was used in simulator tests.
