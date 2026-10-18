import AppKit
import Foundation
import Synchronization
import XCTest
@testable import NotchiumMediaFeature

// URLSession owns instance callback delivery; the only shared mutable test state is Mutex protected.
private final class ArtworkURLProtocol: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable { var png = Data(); var requests: [URL] = [] }
    static let fixture = Mutex(Fixture())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let data = Self.fixture.withLock { fixture in fixture.requests.append(url); return fixture.png }
        let status = url.lastPathComponent == "failure" ? 503 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/png", "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class MediaArtworkTests: XCTestCase {
    func testArtworkLoadsThumbnailAndSharesCacheWhileFailuresUseFallback() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 320,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        ArtworkURLProtocol.fixture.withLock { $0 = .init(png: png) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtworkURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let cache = MediaArtworkCache(session: session)
        let url = URL(string: "https://i.scdn.co/image/success")!
        let first = try await cache.load(url)
        let second = try await cache.load(url)
        XCTAssertNotNil(first?.image); XCTAssertTrue(first === second)
        // NSCGImageSnapshotRep reports backing-scale pixels (640 × 320 on a 2×
        // display). Inspect the decoded CGImage to verify the actual cache limit.
        let thumbnail = try XCTUnwrap(first?.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(thumbnail.width, 320, "Keep enlarged artwork sharp within the decode limit")
        XCTAssertEqual(thumbnail.height, 160, "Thumbnail decoding preserves the source aspect ratio")
        XCTAssertEqual(ArtworkURLProtocol.fixture.withLock { $0.requests.count }, 1)
        let failed = try await cache.load(URL(string: "https://i.scdn.co/image/failure")!)
        XCTAssertNil(failed)
        let rejected = try await cache.load(URL(string: "https://example.com/image/success")!)
        XCTAssertNil(rejected)
        XCTAssertEqual(ArtworkURLProtocol.fixture.withLock { $0.requests.count }, 2)
    }
}
