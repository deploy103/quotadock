// swift-tools-version: 5.9
import PackageDescription

// Executes the same Foundation storage/bridge code on Linux/macOS without emulating
// Keychain, UIKit, WidgetKit or WatchConnectivity.
let package = Package(
    name: "QuotaDockStorage",
    products: [.library(name: "QuotaDockStorage", targets: ["QuotaDockStorage"])],
    targets: [
        .target(name: "QuotaDockStorage", path: ".", exclude: [
            "Assets.xcassets", "Resources", "Tests", "UITests", "Watch", "Widgets",
            "PortableTests", "README.md", "project.yml", "verify-persistence.py",
            "iOS/ConnectionStore.swift",
            "iOS/Cloud.swift", "iOS/FirstRun.swift", "iOS/Purchases.swift",
            "iOS/QuotaAccessibilityPreview.swift", "iOS/QuotaDockApp.swift",
            "iOS/WatchSurfacePreview.swift", "iOS/WidgetSurfacePreview.swift",
            "Shared/Localization.swift", "Shared/ProviderIcon.swift",
            "Shared/QuotaViews.swift", "Shared/SnapshotStore.swift", "Shared/WatchContent.swift",
            "Shared/WatchSync.swift", "Shared/WidgetContent.swift"
        ], sources: ["Shared/Snapshot.swift", "Shared/CacheFiles.swift", "Shared/Bridge.swift", "iOS/ConnectionState.swift"]),
        .testTarget(name: "QuotaDockStorageTests", dependencies: ["QuotaDockStorage"], path: "PortableTests")
    ]
)
