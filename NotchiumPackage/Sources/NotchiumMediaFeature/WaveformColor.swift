import AppKit
import SwiftUI

/// An opaque sRGB colour, shared by hex input, persistence and artwork analysis.
struct WaveformColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let white = WaveformColor(red: 255, green: 255, blue: 255)
    static let blue = WaveformColor(red: 0, green: 122, blue: 255)
    static let green = WaveformColor(red: 52, green: 199, blue: 89)
    static let black = WaveformColor(red: 0, green: 0, blue: 0)

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }

    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard [3, 6].contains(digits.count),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let rgb = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8((rgb >> 16) & 255), green: UInt8((rgb >> 8) & 255), blue: UInt8(rgb & 255))
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: UInt8((min(1, max(0, rgb.redComponent)) * 255).rounded()),
                  green: UInt8((min(1, max(0, rgb.greenComponent)) * 255).rounded()),
                  blue: UInt8((min(1, max(0, rgb.blueComponent)) * 255).rounded()))
    }

    var hex: String { String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue)) }
    var color: Color { Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }

    var contrastAgainstBlack: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (luminance + 0.05) / 0.05
    }

    /// Lift dark colours toward white just enough for the thin bars to stand out.
    /// A 4.5:1 contrast floor leaves extra room for antialiasing on the black notch.
    var visibleOnBlack: WaveformColor {
        guard contrastAgainstBlack < 4.5 else { return self }
        func lifted(by amount: Int) -> WaveformColor {
            func lift(_ channel: UInt8) -> UInt8 {
                UInt8(Int(channel) + (255 - Int(channel)) * amount / 255)
            }
            return .init(red: lift(red), green: lift(green), blue: lift(blue))
        }
        var lower = 0, upper = 255
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if lifted(by: midpoint).contrastAgainstBlack >= 4.5 { upper = midpoint }
            else { lower = midpoint + 1 }
        }
        return lifted(by: lower)
    }

    /// Find the largest colour cluster rather than averaging unrelated artwork colours.
    /// Sampling is bounded to 1,024 pixels and happens once per cached thumbnail.
    static func primaryColor(in image: CGImage) -> WaveformColor? {
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        struct Cluster { var count = 0; var red = 0; var green = 0; var blue = 0 }
        var clusters: [Int: Cluster] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha >= 128 else { continue }
            let red = min(255, Int(pixels[offset]) * 255 / alpha)
            let green = min(255, Int(pixels[offset + 1]) * 255 / alpha)
            let blue = min(255, Int(pixels[offset + 2]) * 255 / alpha)
            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            var cluster = clusters[key, default: Cluster()]
            cluster.count += 1; cluster.red += red; cluster.green += green; cluster.blue += blue
            clusters[key] = cluster
        }
        guard let primary = clusters.max(by: {
            $0.value.count == $1.value.count ? $0.key > $1.key : $0.value.count < $1.value.count
        })?.value else { return nil }
        return .init(red: UInt8(primary.red / primary.count),
                     green: UInt8(primary.green / primary.count), blue: UInt8(primary.blue / primary.count))
    }
}
