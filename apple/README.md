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

Before physical-device builds, set `DEVELOPMENT_TEAM`, `BUNDLE_PREFIX`, and `APP_GROUP` in `project.yml` and regenerate. Defaults are `com.quotadock.app` and `group.com.quotadock.app`. Register the four bundle IDs (base, `.widgets`, `.watch`, `.watch.widgets`) and App Group with your team. Enable the group for all four targets. iPhone app and iPhone widgets additionally share `$(AppIdentifierPrefix)$(BUNDLE_PREFIX).bridge` Keychain access. The Watch has **no token or Keychain entitlement**. App Groups are local to each device; WatchConnectivity bridges sanitized snapshots between devices.

XcodeGen embeds the iOS widget and modern single-target Watch app into the iPhone app; the Watch app embeds its WidgetKit extension. Generated plists, entitlements and project are ignored. No ATS exceptions, background modes, push capability, or insecure certificate bypass are supplied. Release/App Store distribution additionally needs artwork/app icons, team provisioning and device/OS review.

## Pair and use

Run the bridge behind a trusted, device-reachable HTTPS endpoint (valid TLS certificate), then enter its **base URL** and pairing bearer token in Pair. `/v1/snapshot` is appended. Never enter Claude/OpenAI/other provider credentials. URL and token are held together in device-only, after-first-unlock Keychain; no token goes to UserDefaults, snapshot cache, logs or Watch. Redirects are refused to prevent bearer forwarding. Plain HTTP, URL credentials, queries and fragments are rejected. Forget pairing removes the local token/cache; Watch can retain its old snapshot until a new transfer, and offline widgets can retain OS-rendered content.

iPhone fetches on foreground activation and manual/pull refresh. The bridge may return cached measurements. iOS WidgetKit fetches independently over HTTPS and falls back to the App Group snapshot; before first unlock it may only have cache. Timeline requests are hints, not guaranteed refresh intervals. Add the **All AI allowances** overview or individual provider widgets to **Home Screen or Today View**, or rectangular/circular/inline widgets on the Lock Screen. Overview shows all four providers with their icons, plan and first window; individual widgets show one provider's first window. Open the app for every window and reset time. Watch Smart Stack widgets and complications use only the local cache. Open both paired apps and refresh iPhone to initiate WatchConnectivity transfer; no instantaneous/push update promise.

Graphite/mint bars mean **remaining**, clamped to 0–100, never summed. Null is unknown, not exhausted. Plans are displayed as supplied by the sanitized contract; null is “Plan unknown.” Codex refers to the **Codex allowance under a ChatGPT plan**, not overall ChatGPT usage. Gemini window labels are preserved as model tiers. Unavailable/error providers remain visible, diagnostics are replaced with fixed safe text, and readings older than 15 minutes are stale. Reset dates are informational, not a quota promise.

“Explore demo” is explicitly labeled and stays in memory: it never overwrites live cache or transfers fabricated readings. Xcode/WidgetKit previews and placeholders use `Snapshot.preview`, with `demo: true` and `source: demo` everywhere. To see demo widgets on devices, use a bridge explicitly running demo mode.

## Architecture and verification

- `Shared/Snapshot.swift`: contract v1 Codable values, ISO8601 dates including fractions, explicit null re-encoding, 256 KiB bound, safe-message sanitization and demo samples.
- `Shared/Bridge.swift`: HTTPS pairing, Keychain and ephemeral URLSession client; rejects redirects/non-200/schema errors.
- `Shared/SnapshotStore.swift`: atomic sanitized JSON App Group cache.
- `Shared/WatchSync.swift`: latest application-context transfer, no secrets, Watch cache/timeline reload.
- `Shared/QuotaViews.swift`: reusable remaining bars/provider cards.
- `iOS/`, `Watch/`, `Widgets/`: small native surfaces and timeline adapters.
- `Tests/ContractTests.swift`: public model decode/encode, nullable values, clamps, staleness, demo, schema/date/size rejection, URL restrictions, request authorization and response sanitization/status tests using URLProtocol (no real credentials or server).

This source was authored/inspected on Linux: **no Apple SDK build, XCTest run, generated-project inspection or simulator/device test has been claimed**. On a Mac, run the commands above, inspect embedding/signing in Xcode, and test Keychain sharing, first-unlock fallback, Home/Today/Lock Screen layout, Watch pairing/transfer, complications and stale/offline readings. Small accessory layouts are deliberately terse; large Dynamic Type, long tier/plan labels and system widget rendering require device visual review. Unit tests do not establish real TLS, Keychain provisioning or WatchConnectivity delivery.
