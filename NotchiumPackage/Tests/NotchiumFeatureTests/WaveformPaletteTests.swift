import AppKit
import XCTest
@testable import NotchiumMediaFeature

final class WaveformPaletteTests: XCTestCase {
    private let blue = WaveformColor(red: 24, green: 96, blue: 224)
    private let neutralColours: [WaveformColor] = [
        .black, .init(red: 128, green: 128, blue: 128), .white,
    ]

    func testColourfulFamilyWinsOverModestlyLargerBlackGrayOrWhiteArea() throws {
        for neutral in neutralColours {
            let image = try artwork([(neutral, 300), (blue, 240)])
            XCTAssertEqual(WaveformColor.primaryColor(in: image), blue,
                           "30% \(neutral.hex) must yield to a 24% colourful family")
        }
    }

    func testMuchLargerBlackGrayOrWhiteAreaKeepsItsDominance() throws {
        for neutral in neutralColours {
            for neutralCount in [450, 500] {
                let image = try artwork([(neutral, neutralCount), (blue, 250)])
                XCTAssertEqual(WaveformColor.primaryColor(in: image), neutral,
                               "\(neutralCount / 10)% \(neutral.hex) must beat 25% blue")
            }
        }
    }

    func testEqualWeightedCoveragePrefersTheLargerActualArea() throws {
        let image = try artwork([(.black, 360), (blue, 240)])
        XCTAssertEqual(WaveformColor.primaryColor(in: image), .black)
    }

    func testNearBlackNoiseAndMutedGrayReceiveNoColourBonus() throws {
        for neutral in [WaveformColor(red: 2, green: 4, blue: 10),
                        WaveformColor(red: 132, green: 128, blue: 124)] {
            let modestArea = try artwork([(neutral, 300), (blue, 240)])
            XCTAssertEqual(WaveformColor.primaryColor(in: modestArea), blue)
            let dominantArea = try artwork([(neutral, 450), (blue, 250)])
            XCTAssertEqual(WaveformColor.primaryColor(in: dominantArea), neutral)
        }
    }

    func testDarkAndBrightBluesCountAsOneColourFamily() throws {
        let darkBlue = WaveformColor(red: 8, green: 28, blue: 80)
        let brightBlue = WaveformColor(red: 40, green: 100, blue: 236)
        let image = try artwork([(.black, 350), (darkBlue, 180), (brightBlue, 120)])

        try assertBlue(WaveformColor.primaryColor(in: image),
                       message: "18% dark blue and 12% bright blue must together beat 35% black")
    }

    func testBlueGradientKeepsItsCombinedDominanceAcrossManyShades() throws {
        let shades: [(WaveformColor, Int)] = (0..<12).map { index in
            let red = UInt8(8 + index * 2)
            let green = UInt8(28 + index * 5)
            let blue = UInt8(80 + index * 14)
            return (WaveformColor(red: red, green: green, blue: blue), 25)
        }
        let image = try artwork([(.black, 350)] + shades)

        try assertBlue(WaveformColor.primaryColor(in: image),
                       message: "A 30% blue gradient must not be split into twelve negligible colours")
    }

    func testNearbyNeutralShadesKeepTheirCombinedDominance() throws {
        for (first, second) in [
            (WaveformColor(red: 8, green: 8, blue: 8), WaveformColor(red: 24, green: 24, blue: 24)),
            (WaveformColor(red: 120, green: 120, blue: 120), WaveformColor(red: 136, green: 136, blue: 136)),
            (WaveformColor(red: 232, green: 232, blue: 232), WaveformColor.white),
        ] {
            let image = try artwork([(first, 225), (second, 225), (blue, 250)])
            let selected = try XCTUnwrap(WaveformColor.primaryColor(in: image))
            XCTAssertEqual(selected.red, selected.green)
            XCTAssertEqual(selected.green, selected.blue,
                           "45% nearby neutral shades must together beat 25% blue")
            XCTAssertGreaterThanOrEqual(selected.red, first.red)
            XCTAssertLessThanOrEqual(selected.red, second.red)
        }
    }

    func testSaturatedDarkNavyAndDeepRedReceiveTheColourPreference() throws {
        let navy = WaveformColor(red: 2, green: 12, blue: 54)
        let deepRed = WaveformColor(red: 54, green: 2, blue: 9)
        for colour in [navy, deepRed] {
            let image = try artwork([(.black, 300), (colour, 240)],
                                    fillers: [.init(red: 240, green: 240, blue: 0),
                                              .init(red: 0, green: 240, blue: 0),
                                              .init(red: 0, green: 240, blue: 240),
                                              .init(red: 240, green: 0, blue: 240)])
            let selected = try XCTUnwrap(WaveformColor.primaryColor(in: image))
            XCTAssertEqual(selected, colour, "A dark colourful hue must qualify before display brightening")
            XCTAssertGreaterThanOrEqual(selected.visibleOnBlack.contrastAgainstBlack, 4.5)
        }
    }

    func testNearbyRedsAcrossHueWrapCountAsOneFamily() throws {
        let coolRed = WaveformColor(red: 240, green: 16, blue: 40)
        let warmRed = WaveformColor(red: 240, green: 40, blue: 16)
        let image = try artwork([(.black, 350), (coolRed, 180), (warmRed, 120)],
                                fillers: [.init(red: 240, green: 240, blue: 0),
                                          .init(red: 0, green: 240, blue: 0),
                                          .init(red: 0, green: 240, blue: 240),
                                          .init(red: 0, green: 0, blue: 240)])
        let selected = try XCTUnwrap(WaveformColor.primaryColor(in: image))
        let hsb = components(of: selected)
        XCTAssertLessThan(min(hsb.hue, 1 - hsb.hue), 0.05)
        XCTAssertGreaterThan(hsb.saturation, 0.5)
        XCTAssertGreaterThan(selected.red, selected.green)
        XCTAssertGreaterThan(selected.red, selected.blue)
    }

    func testTinyBrightAccentDoesNotReplaceDominantDarkColourFamily() throws {
        let navy = WaveformColor(red: 8, green: 24, blue: 72)
        let yellow = WaveformColor(red: 255, green: 240, blue: 0)
        let image = try artwork([(navy, 450), (.black, 350), (yellow, 20)])

        XCTAssertEqual(WaveformColor.primaryColor(in: image), navy,
                       "A bright 2% accent must not replace the dominant 45% colourful family")
    }

    func testEntirelyNeutralArtworkPreservesItsNeutralColour() throws {
        for channel in [UInt8(0), 20, 80, 128, 220, 255] {
            let grey = WaveformColor(red: channel, green: channel, blue: channel)
            XCTAssertEqual(WaveformColor.primaryColor(in: try artwork([(grey, 1_000)])), grey)
        }
    }

    func testEntirelyTransparentArtworkHasNoPrimaryColour() throws {
        XCTAssertNil(WaveformColor.primaryColor(in: try artwork([], fillers: [])))
    }

    func testEqualFamiliesSelectTheSameColourRegardlessOfPixelOrder() throws {
        let red = WaveformColor(red: 224, green: 24, blue: 24)
        let first = try artwork([(red, 500), (blue, 500)])
        let reversed = try artwork([(blue, 500), (red, 500)])
        let selected = try XCTUnwrap(WaveformColor.primaryColor(in: first))

        XCTAssertTrue([red, blue].contains(selected))
        XCTAssertEqual(WaveformColor.primaryColor(in: reversed), selected)
        XCTAssertEqual(WaveformColor.primaryColor(in: first), selected)
    }

    /// Exactly 1,000 opaque samples make the coverage percentages explicit. The
    /// remaining 24 pixels are transparent, and drawing remains 32 by 32 pixels.
    private func artwork(
        _ populations: [(WaveformColor, Int)],
        fillers: [WaveformColor] = [
            .init(red: 240, green: 0, blue: 0),
            .init(red: 240, green: 240, blue: 0),
            .init(red: 0, green: 240, blue: 0),
            .init(red: 240, green: 0, blue: 240),
        ]
    ) throws -> CGImage {
        var samples = populations.flatMap { colour, count in
            Array(repeating: colour, count: count)
        }
        XCTAssertLessThanOrEqual(samples.count, 1_000)
        if !fillers.isEmpty {
            let remaining = 1_000 - samples.count
            for index in 0..<remaining {
                samples.append(fillers[index % fillers.count])
            }
        }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        for (index, colour) in samples.enumerated() {
            let offset = index * 4
            pixels[offset] = colour.red
            pixels[offset + 1] = colour.green
            pixels[offset + 2] = colour.blue
            pixels[offset + 3] = 255
        }
        let data = Data(pixels) as CFData
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        return try XCTUnwrap(CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: 32 * 4,
                                    space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                                        | CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent))
    }

    private func assertBlue(_ colour: WaveformColor?, message: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let selected = try XCTUnwrap(colour, message, file: file, line: line)
        let hsb = components(of: selected)
        XCTAssertTrue((0.55...0.73).contains(hsb.hue), message, file: file, line: line)
        XCTAssertGreaterThan(hsb.saturation, 0.5, message, file: file, line: line)
        XCTAssertGreaterThan(selected.blue, selected.green, message, file: file, line: line)
        XCTAssertGreaterThan(selected.green, selected.red, message, file: file, line: line)
    }

    private func components(of colour: WaveformColor) -> (hue: CGFloat, saturation: CGFloat) {
        let colour = NSColor(srgbRed: CGFloat(colour.red) / 255,
                             green: CGFloat(colour.green) / 255,
                             blue: CGFloat(colour.blue) / 255, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        colour.getHue(&hue, saturation: &saturation, brightness: nil, alpha: nil)
        return (hue, saturation)
    }
}
