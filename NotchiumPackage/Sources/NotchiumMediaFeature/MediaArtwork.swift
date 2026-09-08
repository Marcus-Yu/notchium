import AppKit
import ImageIO
import SwiftUI

/// At most eight 160px thumbnails (~800KB decoded). Requests cancel with their view identity.
@MainActor private final class MediaArtworkCache {
    static let shared = MediaArtworkCache()
    let images = NSCache<NSURL, NSImage>()
    private let session: URLSession
    init() {
        images.countLimit = 8
        images.totalCostLimit = 1_000_000
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }
    func load(_ url: URL) async throws -> NSImage? {
        if let image = images.object(forKey: url as NSURL) { return image }
        guard url.scheme == "https", url.host == "i.scdn.co" else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 15
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == "i.scdn.co", response.expectedContentLength <= 2_000_000 else { return nil }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { return nil }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: .zero)
        images.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}

public struct MediaArtwork: View {
    let url: URL?
    let size: CGFloat
    @State private var image: NSImage?
    public init(url: URL?, size: CGFloat) { self.url = url; self.size = size }
    public var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else if url?.scheme == "notchium-fixture" {
                // Local, deterministic fixture artwork; no external requests in mocks.
                Color(red: 0.15, green: 0.25, blue: 0.32)
                Circle().fill(.orange.opacity(0.8)).frame(width: size * 0.45)
                    .offset(x: size * 0.12, y: -size * 0.12)
                Rectangle().fill(.black.opacity(0.6)).frame(height: size * 0.35).offset(y: size * 0.35)
            } else {
                Color(white: 0.12)
                Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size > 24 ? 8 : 4))
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url, url.scheme == "https" else { return }
            let loaded = try? await MediaArtworkCache.shared.load(url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
