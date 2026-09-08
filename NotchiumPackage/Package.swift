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
        .target(
            name: "NotchiumServices",
            dependencies: ["NotchiumCore"]
        ),
        .target(
            name: "NotchiumPersistence",
            dependencies: ["NotchiumCore"]
        ),
        .target(name: "NotchiumDesignSystem"),
        .target(
            name: "NotchiumDynamicIsland",
            dependencies: ["NotchiumCore", "NotchiumDesignSystem"]
        ),
        .target(
            name: "NotchiumMediaFeature",
            dependencies: ["NotchiumCore", "NotchiumServices", "NotchiumDynamicIsland"]
        ),
        .target(
            name: "NotchiumCalendarFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
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
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumCaffeineFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
        ),
        .target(
            name: "NotchiumKeyboardLockFeature",
            dependencies: ["NotchiumCore", "NotchiumServices"]
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
                "NotchiumDiagnostics",
                "NotchiumDynamicIsland",
                "NotchiumFeature",
                "NotchiumServices",
                "NotchiumTestFixtures",
                "NotchiumMediaFeature",
            ]
        ),
    ]
)
