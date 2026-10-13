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

iPhone fetches on foreground activation and manual/pull refresh. The bridge may return cached measurements. **All widgets are cache-only timeline readers**, never background bridge/provider/cloud clients. They have neither network client source nor Keychain entitlements. Timeline requests are hints, not guaranteed refresh intervals. Add the **All AI allowances** overview or individual provider widgets to **Home Screen or Today View**, or rectangular/circular/inline widgets on the Lock Screen. Overview shows up to four providers with their icons, plan and first window; individual widgets show one provider's first window. Open the app for every window and reset time. Watch Smart Stack widgets and complications use only the local cache. Open both paired apps and refresh iPhone to initiate WatchConnectivity transfer; no instantaneous/push update promise.

## Optional cloud (v2, Free only)

Choose **Optional cloud account** and affirm both quota-storage and collector-processing consent before starting real Apple authorization. Default server is `https://usage.mvtp.cloud`; the editable URL is stored locally and must be trusted HTTPS, with no URL credentials/query/fragment. There is no fake identity, provider login, OpenAI login or purchase path. DNS, TLS, Apple capability/configuration and server failures are reported without exposing diagnostics.

The client POSTs `/v2/auth/challenge`, sets the AuthorizationServices request nonce to **exactly `challenge.nonce`**, requests no email/name scopes, and POSTs the returned identity JWT with the challenge ID and affirmative consent to `/v2/auth/apple`. Only the returned one-hour opaque session is persisted, in the iPhone-only device-only Keychain (`WhenUnlockedThisDeviceOnly`). No identity JWT or session is stored in quota caches, UserDefaults, Watch or widgets. Requests use ephemeral sessions, no cookies/cache, no redirects, streamed 256 KiB response bounds and 20-second resource timeouts.

`/v2/me` displays the Free `earlyBatchesUsed` counter; `/v2/accounts` manages server UUID slots (max three enforced server-side); `/v2/snapshot` preserves separate same-provider accounts and every window. Phone rows use account UUIDs, with an eight-character UUID label rather than an invented account name. Full sanitized account cache stays in the iPhone sandbox. **Watch/widgets intentionally receive only the first server-listed account per provider**, not all accounts; current server ordering is ascending account UUID. Do not treat these surfaces as account totals. Both caches preserve the original observation timestamp, not the fetch time. Server `lastError` is presented as fixed safe text; raw errors/names are not exported.

Foreground automatic refresh honors Settings and submits `mode:auto`; manual/pull refresh submits `mode:force` (an early batch may use Free allowance). Requests target slot UUIDs and use a fresh UUID idempotency key per user operation. A pending job means **waiting for a separately implemented local collector**, not updated quota. The phone cannot obtain provider quotas directly without granted APIs, and does not collect/complete jobs. Pending requests poll only `/v2/snapshot`, every five seconds while foreground, with a 60-second polling deadline and bounded request timeout. Cached/completed replies are followed by cache reads; unknown/failure remains unknown and previous source observations remain visible.

Logout POSTs `/v2/auth/logout`; account erasure DELETEs `/v2/me` after destructive confirmation. Local sessions/caches are cleared immediately and old in-flight completions cannot restore them. Failed revocation/erasure is explicitly **not confirmed**; reconnect to retry account erasure (server sessions expire within one hour). Slot deletion uses the real DELETE endpoint and clears local caches before re-reading. Switching cloud/bridge owners clears both caches and sends an empty Watch snapshot; offline Watch and OS-rendered widgets may retain previously rendered content until delivery/reload. Switching to the bridge attempts server logout and never treats its legacy token as a cloud session.

Graphite/mint bars mean **remaining**, clamped to 0–100, never summed. Null is unknown, not exhausted. Plans are displayed as supplied by the sanitized contract; null is “Plan unknown.” Codex refers to the **Codex allowance under a ChatGPT plan**, not overall ChatGPT usage. Gemini window labels are preserved as model tiers. Unavailable/error providers remain visible, diagnostics are replaced with fixed safe text, and readings older than 15 minutes are stale. Reset dates are informational, not a quota promise.

“Explore demo” is explicitly labeled and stays in memory: it never overwrites live cache or transfers fabricated readings. Xcode/WidgetKit previews and placeholders use `Snapshot.preview`, with `demo: true` and `source: demo` everywhere. To see demo widgets on devices, use a bridge explicitly running demo mode.

## Architecture and verification

- `Shared/Snapshot.swift`: contract v1 Codable values, ISO8601 dates including fractions, explicit null re-encoding, 256 KiB bound, safe-message sanitization and demo samples.
- `Shared/Bridge.swift`: HTTPS pairing, Keychain and ephemeral URLSession client; rejects redirects/non-200/schema errors.
- `Shared/SnapshotStore.swift`: atomic sanitized JSON App Group cache.
- `Shared/WatchSync.swift`: latest application-context transfer, no secrets, Watch cache/timeline reload.
- `Shared/QuotaViews.swift`: reusable remaining bars/provider cards.
- `iOS/Cloud.swift`: real nonce-bound Apple/server authorization, independent Keychain session, v2 account-list decoding, sandbox full-slot cache, foreground collector-job requests and bounded snapshot polling.
- `iOS/`, `Watch/`, `Widgets/`: small native surfaces and timeline adapters.
- `Tests/ContractTests.swift`: public model decode/encode, nullable values, clamps, staleness, demo, schema/date/size rejection, URL restrictions, request authorization and response sanitization/status tests using URLProtocol (no real credentials or server).

The [macOS CI run](https://github.com/deploy103/quotadock/actions/runs/38420208680) generated the project with XcodeGen, built the iPhone, Watch and WidgetKit targets using Xcode 16.4, and passed all six native contract XCTests on an iPhone simulator. The app was launched with `--demo`; its [captured screenshot](../docs/assets/native-demo.png) was inspected for icons, plans, remaining bars, demo labeling and explicit unknown readings. The app is scrollable, and the screenshot shows only part of the last provider card; it is not a system-widget or Watch screenshot.

This is not physical-device validation. On a Mac, inspect embedding/signing in Xcode and test Keychain sharing, first-unlock fallback, Home/Today/Lock Screen layout, Watch pairing/transfer, complications and stale/offline readings. Small accessory layouts are deliberately terse; large Dynamic Type, long tier/plan labels and system widget rendering require device visual review. Unit tests do not establish real TLS, Keychain provisioning or WatchConnectivity delivery.

The v2 cloud integration and cache-only widget changes have **not** been Apple-built or visually inspected locally. The historical CI/screenshot above predates these changes. New regression cases cover multiple same-provider slots, multiple windows/nulls, safe cache projections with fractional observation timestamps, duplicate/oversized/insecure input rejection, and mode-switch cache/revision clearing. Gate on a new unsigned macOS build/XCTest run and simulator app/widget/Watch screenshots; real Apple sign-in, logout/erasure and collector completion additionally require signed-device end-to-end validation with the user's Apple Team and configured v2 server.
