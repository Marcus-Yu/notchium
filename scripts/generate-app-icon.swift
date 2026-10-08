#!/usr/bin/env swift
// Run from the repository root with: swift scripts/generate-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconImage: Encodable {
    let filename: String
    let idiom = "mac"
    let scale: String
    let size: String
}

struct IconManifest: Encodable {
    struct Info: Encodable {
        let author = "xcode"
        let version = 1
    }

    let images: [IconImage]
    let info = Info()
}

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let masterURL = root.appendingPathComponent("artwork/AppIcon-master.png")
let iconSetURL = root.appendingPathComponent("Notchium/Assets.xcassets/AppIcon.appiconset")
guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil),
      master.width == master.height else {
    fatalError("AppIcon master must be a readable square image: \(masterURL.path)")
}
try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

var images: [IconImage] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: master.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Could not create \(pixels)px image context")
        }
        // Every output comes directly from the supplied master. Preserve the
        // pixel-art edges when enlarging, and filter reductions for legibility.
        context.interpolationQuality = pixels > master.width ? .none : .high
        context.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                iconSetURL.appendingPathComponent(filename) as CFURL,
                UTType.png.identifier as CFString, 1, nil
              ) else {
            fatalError("Could not create \(filename)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Could not write \(filename)")
        }
        images.append(IconImage(filename: filename, scale: "\(scale)x", size: "\(points)x\(points)"))
        print("Generated \(filename): \(pixels)×\(pixels)")
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
var manifest = try encoder.encode(IconManifest(images: images))
manifest.append(0x0A)
try manifest.write(to: iconSetURL.appendingPathComponent("Contents.json"), options: .atomic)
