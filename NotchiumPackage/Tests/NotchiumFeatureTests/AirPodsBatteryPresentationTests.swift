import AppKit
import NotchiumDesignSystem
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class AirPodsBatteryPresentationTests: XCTestCase {
    private func connection(_ style: NotchDeviceStyle, level: Double? = nil) -> NotchCompactActivity {
        NotchCompactActivity(.init(kind: .outputChanged, deviceName: "AirPods", volume: nil,
            isMuted: false, deviceStyle: style, battery: level.map { .init(level: $0, isCharging: false) }))
    }

    func testCompactReadoutOnlyAppliesToReportedAirPodsBattery() {
        for style in [NotchDeviceStyle.airPods, .airPodsPro, .airPodsMax] {
            for level in [0.0, 0.05, 0.2, 1.0] {
                let activity = connection(style, level: level)
                XCTAssertTrue(activity.usesAirPodsBatteryReadout)
                XCTAssertEqual(activity.sideWidth, 72)
                XCTAssertEqual(activity.trailing, .battery(level: level, charging: false))
            }
            let unknown = connection(style)
            XCTAssertFalse(unknown.usesAirPodsBatteryReadout)
            XCTAssertEqual(unknown.trailing, .text("Connected"))
            XCTAssertEqual(unknown.sideWidth, 86)

            let disconnected = NotchCompactActivity(.init(kind: .deviceDisconnected, deviceName: "AirPods",
                volume: nil, isMuted: false, deviceStyle: style))
            XCTAssertFalse(disconnected.usesAirPodsBatteryReadout)
            XCTAssertEqual(disconnected.sideWidth, NotchCompactGeometry.sideWidth,
                           "Disconnected must remain legible without shrinking the status")
        }
        XCTAssertFalse(connection(.headphones, level: 0.8).usesAirPodsBatteryReadout)
        XCTAssertEqual(connection(.headphones, level: 0.8).sideWidth, 86)
        XCTAssertFalse(NotchCompactActivity.charging(level: 0.8).usesAirPodsBatteryReadout)
        XCTAssertFalse(NotchCompactActivity.lowBattery(level: 0.1).usesAirPodsBatteryReadout)
    }

    func testLowBatteryToneFollowsDisplayedPercentageAndChargingOverridesWarning() {
        typealias Tone = NotchAirPodsBatteryReadout.Tone
        for level in [0.0, 0.05, 0.2, 0.204] {
            XCTAssertEqual(Tone(level: level, charging: false), .low)
            XCTAssertEqual(Tone(level: level, charging: true), .normal)
        }
        for level in [0.21, 0.82, 1.0] {
            XCTAssertEqual(Tone(level: level, charging: false), .normal)
        }
    }

    func testReadoutFitsNarrowSideAtBatteryExtremesWithIncreasedContrast() throws {
        for increaseContrast in [false, true] {
            for level in [0.0, 0.05, 0.2, 1.0] {
                for charging in [false, true] {
                    let content = NotchAirPodsBatteryReadout(level: level, charging: charging,
                                                            reveal: 1, reduceMotion: true)
                        .environment(\.colorScheme, .dark)
                        .environment(\.notchIncreaseContrastOverride, increaseContrast)
                    let image = try XCTUnwrap(ImageRenderer(content: content).cgImage)
                    // A 72pt side reserves 13pt outer padding and 6pt beside the notch.
                    XCTAssertLessThanOrEqual(image.width, 53,
                                             "Even 100% plus the ring must fit without squeezing the number")
                    XCTAssertLessThanOrEqual(image.height, 18)
                    if let directory = ProcessInfo.processInfo.environment["NOTCHIUM_AIRPODS_CAPTURE_DIR"] {
                        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        let filename = "battery-\(Int(level * 100))-\(charging)-contrast-\(increaseContrast).png"
                        try bitmap.representation(using: .png, properties: [:])?.write(
                            to: URL(fileURLWithPath: directory).appendingPathComponent(filename))
                    }
                }
            }
        }
    }

    func testIncreasedContrastBrightensTheRingTrack() throws {
        func ringBrightness(increased: Bool) throws -> Double {
            let content = NotchAirPodsBatteryReadout(level: 0, charging: false, reveal: 1, reduceMotion: true)
                .environment(\.colorScheme, .dark)
                .environment(\.notchIncreaseContrastOverride, increased)
                .background(.black)
            let image = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: content).cgImage))
            var brightness = 0.0
            // Zero charge exposes the unfilled track, isolated in the trailing 14pt square.
            for y in 0..<image.pixelsHigh {
                for x in (image.pixelsWide - 14)..<image.pixelsWide {
                    let color = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    brightness += Double((color.redComponent + color.greenComponent + color.blueComponent) / 3)
                }
            }
            return brightness / Double(14 * image.pixelsHigh)
        }
        let standard = try ringBrightness(increased: false)
        let increased = try ringBrightness(increased: true)
        XCTAssertGreaterThan(increased, standard * 1.5,
                             "The shell's Increase Contrast override must strengthen the actual rendered track")
    }
}
