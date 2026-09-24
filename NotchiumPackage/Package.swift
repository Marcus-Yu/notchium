// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NotchiumFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "NotchiumFeature",
            targets: ["NotchiumFeature"]
        ),
    ],
    targets: [
        .target(name: "NotchiumCore"),
        .target(
            name: "NotchiumDiagnostics",
            dependencies: ["NotchiumCore"]
        ),
        .target(name: "NotchiumRealtimeAudio", publicHeadersPath: "include"),
        .target(
            name: "NotchiumServices",
            dependencies: ["NotchiumCore", "NotchiumRealtimeAudio"]
        ),
        .target(
            name: "NotchiumPersistence",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(name: "NotchiumDesignSystem"),
        .target(
            name: "NotchiumDynamicIsland",
            dependencies: ["NotchiumCore", "NotchiumDesignSystem"]
        ),
        .target(
            name: "NotchiumMediaFeature",
            dependencies: ["NotchiumCore", "NotchiumServices", "NotchiumDynamicIsland", "NotchiumDesignSystem"]
        ),
        .target(
            name: "NotchiumCalendarFeature",
            dependencies: ["NotchiumCore", "NotchiumServices", "NotchiumDynamicIsland"]
        ),
        .target(
            name: "NotchiumShelfFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumCameraFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumAudioFeature",
            dependencies: ["NotchiumCore", "NotchiumServices", "NotchiumDynamicIsland", "NotchiumDesignSystem"]
        ),
        .target(
            name: "NotchiumCaffeineFeature",
            dependencies: ["NotchiumCore", "NotchiumServices", "NotchiumDynamicIsland"]
        ),
        .target(
            name: "NotchiumKeyboardLockFeature",
            dependencies: ["NotchiumCore", "NotchiumServices", "NotchiumDynamicIsland"]
        ),
        .target(
            name: "NotchiumClipboardFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumMonitoringFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumActivitiesFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumPagesFeature",
            dependencies: ["NotchiumCore"]
        ),
        .target(
            name: "NotchiumFocusFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumDebug",
            dependencies: [
                "NotchiumCore",
                "NotchiumDesignSystem",
                "NotchiumDiagnostics",
                "NotchiumPersistence",
                "NotchiumServices",
            ]
        ),
        .target(
            name: "NotchiumFeature",
            dependencies: [
                "NotchiumActivitiesFeature",
                "NotchiumAudioFeature",
                "NotchiumCaffeineFeature",
                "NotchiumCalendarFeature",
                "NotchiumCameraFeature",
                "NotchiumClipboardFeature",
                "NotchiumCore",
                "NotchiumDebug",
                "NotchiumDesignSystem",
                "NotchiumDiagnostics",
                "NotchiumDynamicIsland",
                "NotchiumFocusFeature",
                "NotchiumKeyboardLockFeature",
                "NotchiumMediaFeature",
                "NotchiumMonitoringFeature",
                "NotchiumPagesFeature",
                "NotchiumPersistence",
                "NotchiumServices",
                "NotchiumShelfFeature",
            ]
        ),
        .target(
            name: "NotchiumTestFixtures",
            dependencies: [
                "NotchiumCore",
                "NotchiumDiagnostics",
                "NotchiumPersistence",
                "NotchiumServices",
            ]
        ),
        .testTarget(
            name: "NotchiumFeatureTests",
            dependencies: [
                "NotchiumCore",
                "NotchiumAudioFeature",
                "NotchiumCaffeineFeature",
                "NotchiumCalendarFeature",
                "NotchiumDiagnostics",
                "NotchiumDynamicIsland",
                "NotchiumFeature",
                "NotchiumKeyboardLockFeature",
                "NotchiumServices",
                "NotchiumTestFixtures",
                "NotchiumMediaFeature",
                "NotchiumRealtimeAudio",
            ]
        ),
    ]
)
