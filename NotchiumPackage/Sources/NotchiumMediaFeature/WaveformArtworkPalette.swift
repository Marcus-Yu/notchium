import CoreGraphics

extension WaveformColor {
    /// Sample once per cached thumbnail, with a 1.5× coverage preference for colourful
    /// families. A much larger neutral area still wins; unrelated hues are never averaged.
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

        var hues = [ArtworkColorCluster](repeating: .init(), count: 24)
        var neutrals = [ArtworkColorCluster](repeating: .init(), count: 16)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha >= 128 else { continue }
            let red = min(255, Int(pixels[offset]) * 255 / alpha)
            let green = min(255, Int(pixels[offset + 1]) * 255 / alpha)
            let blue = min(255, Int(pixels[offset + 2]) * 255 / alpha)
            let peak = max(red, max(green, blue))
            let low = min(red, min(green, blue))
            let chroma = peak - low
            // Saturation alone makes almost-black compression noise look colourful.
            // Require 25% saturation and at least 16 levels of actual channel separation.
            if chroma >= 16, chroma * 4 >= peak {
                var hue: Double
                if peak == red { hue = Double(green - blue) / Double(chroma) }
                else if peak == green { hue = 2 + Double(blue - red) / Double(chroma) }
                else { hue = 4 + Double(red - green) / Double(chroma) }
                if hue < 0 { hue += 6 }
                let index = min(hues.count - 1, Int(hue / 6 * Double(hues.count)))
                hues[index].add(red: red, green: green, blue: blue)
            } else {
                let index = ((peak + low) / 2) >> 4
                neutrals[index].add(red: red, green: green, blue: blue)
            }
        }

        var best = ArtworkColorCluster()
        var bestScore = 0
        func consider(_ cluster: ArtworkColorCluster, weight: Int) {
            guard cluster.count > 0 else { return }
            let score = cluster.count * weight
            if score > bestScore
                || (score == bestScore && cluster.count > best.count)
                || (score == bestScore && cluster.count == best.count && cluster.rgbKey < best.rgbKey) {
                best = cluster
                bestScore = score
            }
        }

        // Overlapping neighbourhoods avoid splitting one family at a bucket boundary.
        // Neutral shades merge locally too, without pooling black, middle gray and white.
        for index in neutrals.indices {
            var family = ArtworkColorCluster()
            for neighbour in max(0, index - 1)...min(neutrals.count - 1, index + 1) {
                family.merge(neutrals[neighbour])
            }
            consider(family, weight: 2)
        }
        for index in hues.indices {
            var family = ArtworkColorCluster()
            for offset in -1...1 {
                family.merge(hues[(index + offset + hues.count) % hues.count])
            }
            consider(family, weight: 3)
        }
        return best.count > 0 ? best.color : nil
    }
}

private struct ArtworkColorCluster {
    var count = 0
    var red = 0
    var green = 0
    var blue = 0

    mutating func add(red: Int, green: Int, blue: Int) {
        count += 1
        self.red += red
        self.green += green
        self.blue += blue
    }

    mutating func merge(_ other: Self) {
        count += other.count
        red += other.red
        green += other.green
        blue += other.blue
    }

    var color: WaveformColor {
        .init(red: UInt8(red / count), green: UInt8(green / count), blue: UInt8(blue / count))
    }

    var rgbKey: Int { (red / count) << 16 | (green / count) << 8 | (blue / count) }
}
