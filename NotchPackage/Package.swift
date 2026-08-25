// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NotchFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "NotchFeature",
            targets: ["NotchFeature"]
        ),
    ],
    targets: [
        .target(name: "NotchCore"),
        .target(
            name: "NotchDiagnostics",
            dependencies: ["NotchCore"]
        ),
        .target(
            name: "NotchServices",
            dependencies: ["NotchCore"]
        ),
        .target(
            name: "NotchPersistence",
            dependencies: ["NotchCore"]
        ),
        .target(name: "NotchDesignSystem"),
        .target(
            name: "NotchDynamicIsland",
            dependencies: ["NotchCore", "NotchDesignSystem"]
        ),
        .target(
            name: "NotchMediaFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchCalendarFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchShelfFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchCameraFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchAudioFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchCaffeineFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchKeyboardLockFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchClipboardFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchMonitoringFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchActivitiesFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchPagesFeature",
            dependencies: ["NotchCore"]
        ),
        .target(
            name: "NotchFocusFeature",
            dependencies: ["NotchCore", "NotchServices"]
        ),
        .target(
            name: "NotchDebug",
            dependencies: [
                "NotchCore",
                "NotchDesignSystem",
                "NotchDiagnostics",
                "NotchPersistence",
                "NotchServices",
            ]
        ),
        .target(
            name: "NotchFeature",
            dependencies: [
                "NotchActivitiesFeature",
                "NotchAudioFeature",
                "NotchCaffeineFeature",
                "NotchCalendarFeature",
                "NotchCameraFeature",
                "NotchClipboardFeature",
                "NotchCore",
                "NotchDebug",
                "NotchDesignSystem",
                "NotchDiagnostics",
                "NotchDynamicIsland",
                "NotchFocusFeature",
                "NotchKeyboardLockFeature",
                "NotchMediaFeature",
                "NotchMonitoringFeature",
                "NotchPagesFeature",
                "NotchPersistence",
                "NotchServices",
                "NotchShelfFeature",
            ]
        ),
        .target(
            name: "NotchTestFixtures",
            dependencies: [
                "NotchCore",
                "NotchDiagnostics",
                "NotchPersistence",
                "NotchServices",
            ]
        ),
        .testTarget(
            name: "NotchFeatureTests",
            dependencies: [
                "NotchCore",
                "NotchDiagnostics",
                "NotchDynamicIsland",
                "NotchFeature",
                "NotchServices",
                "NotchTestFixtures",
            ]
        ),
    ]
)
