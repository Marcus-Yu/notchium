import Foundation
import XCTest
import NotchiumCore
@testable import NotchiumServices

private final class MemorySpotifyStore: SpotifyTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    init(data: Data? = nil) { self.data = data }
    func read() -> Data? { lock.withLock { data } }
    func write(_ data: Data) { lock.withLock { self.data = data } }
    func remove() { lock.withLock { data = nil } }
}
private actor ScriptedMediaTransport: MediaHTTPTransport {
    private var responses: [MediaHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [MediaHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> MediaHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw MediaFailure.invalidResponse }
        return responses.removeFirst()
    }
}

private actor RacingMediaTransport: MediaHTTPTransport {
    private let playing: Data
    private let paused: Data
    private var count = 0
    private var held: CheckedContinuation<MediaHTTPResponse, any Error>?
    private var observer: CheckedContinuation<Void, Never>?
    init(playing: Data, paused: Data) { self.playing = playing; self.paused = paused }
    func send(_ request: URLRequest) async throws -> MediaHTTPResponse {
        count += 1
        switch count {
        case 1: return .init(data: playing, status: 200)
        case 2:
            return try await withCheckedThrowingContinuation { continuation in
                held = continuation
                observer?.resume(); observer = nil
            }
        case 3: return .init(status: 204)
        case 4: return .init(data: paused, status: 200)
        default: throw MediaFailure.invalidResponse
        }
    }
    func waitForHeldPoll() async {
        if held != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func failHeldPoll() { held?.resume(throwing: MediaFailure.invalidResponse); held = nil }
}

@MainActor final class SpotifyMediaTests: XCTestCase {
    private func authorizedStore() -> MemorySpotifyStore {
        .init(data: Data(#"{"clientID":"fixture","accessToken":"fixture-access","refreshToken":"fixture-refresh","expiration":9999999999}"#.utf8))
    }
    private func playback(playing: Bool = true, elapsed: Int = 61000, restricted: Bool = false) -> Data {
        Data("""
        {"is_playing":\(playing),"progress_ms":\(elapsed),"device":{"is_restricted":\(restricted)},
        "actions":{"disallows":{"skipping_next":true}},"shuffle_state":false,"repeat_state":"off",
        "item":{"id":"track-1","name":"Midnight City","type":"track","duration_ms":244000,
        "artists":[{"name":"M83"}],"album":{"images":[{"url":"https://i.scdn.co/image/fixture","width":300}]}}}
        """.utf8)
    }
    func testSpotifyMappingCapabilitiesArtworkProgressAndRestrictedDevice() throws {
        let state = try JSONDecoder().decode(SpotifyPlayback.self, from: playback()).mediaState()
        XCTAssertEqual(state.source, .spotify); XCTAssertEqual(state.artist, "M83")
        XCTAssertEqual(state.progress, 0.25); XCTAssertNotNil(state.artwork)
        XCTAssertTrue(state.canPlayPause); XCTAssertFalse(state.canSkipForward)
        XCTAssertTrue(state.canSeek)
        let restricted = try JSONDecoder().decode(SpotifyPlayback.self, from: playback(restricted: true)).mediaState()
        XCTAssertFalse(restricted.canPlayPause); XCTAssertFalse(restricted.canSeek)
    }
    func testPKCEStateValidationAndSingleUseCallback() async throws {
        let store = MemorySpotifyStore()
        let transport = ScriptedMediaTransport([.init(data: Data(#"{"access_token":"fixture","refresh_token":"refresh","expires_in":3600}"#.utf8), status: 200)])
        let auth = SpotifyAuthorization(store: store, transport: transport)
        let url = try await auth.begin(clientID: String(repeating: "a", count: 32))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertEqual(query.first(where: { $0.name == "code_challenge" })?.value?.count, 43)
        let state = query.first(where: { $0.name == "state" })!.value!
        let callback = URL(string: SpotifyAuthorization.redirectURI + "?code=fixture&state=" + state)!
        try await auth.complete(callback: callback)
        let token = try await auth.accessToken(); XCTAssertEqual(token, "fixture")
        XCTAssertNotNil(store.read())
        do { try await auth.complete(callback: callback); XCTFail("Callback replay succeeded") }
        catch { XCTAssertEqual(error as? MediaFailure, .authorization) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let body = String(data: requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("code_verifier=")); XCTAssertFalse(body.contains("client_secret"))
        try await auth.disconnect(); XCTAssertNil(store.read())
    }
    func testWrongOAuthStateDoesNotExchangeTokens() async throws {
        let transport = ScriptedMediaTransport([])
        let auth = SpotifyAuthorization(store: MemorySpotifyStore(), transport: transport)
        _ = try await auth.begin(clientID: String(repeating: "b", count: 32))
        do {
            try await auth.complete(callback: URL(string: SpotifyAuthorization.redirectURI + "?code=x&state=wrong")!)
            XCTFail("Invalid state accepted")
        } catch { XCTAssertEqual(error as? MediaFailure, .authorization) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testRealProviderObservationCommandsConfirmedSeekingAndRateLimit() async throws {
        let transport = ScriptedMediaTransport([
            .init(data: playback(), status: 200),
            .init(status: 204), .init(data: playback(playing: false), status: 200),
            .init(status: 204), .init(data: playback(playing: false, elapsed: 122000), status: 200),
            .init(status: 429, retryAfter: 60)
        ])
        let auth = SpotifyAuthorization(store: authorizedStore(), transport: transport)
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: auth, transport: transport, clock: clock)
        var iterator = await provider.updates().makeAsyncIterator()
        _ = await iterator.next()
        try await provider.connect()
        let playing = await iterator.next(); XCTAssertTrue(playing!.isPlaying)
        await clock.waitForPendingSleeps()
        let intervals = await clock.sleepHistory(); XCTAssertEqual(intervals, [.milliseconds(500)])
        try await provider.perform(.playPause)
        let paused = await iterator.next(); XCTAssertEqual(paused!.playbackState, .paused)
        try await provider.perform(.seek(122))
        let sought = await iterator.next(); XCTAssertEqual(sought!.progress, 0.5)
        do { try await provider.perform(.previous); XCTFail("Rate limit ignored") }
        catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(60)) }
        do { try await provider.perform(.previous); XCTFail("Backoff ignored") }
        catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(30)) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(requests[1].url?.path, "/v1/me/player/pause")
        XCTAssertEqual(requests[3].url?.query, "position_ms=122000")
        XCTAssertEqual(requests[5].httpMethod, "POST")
        try await provider.disconnect()
        let stopped = await iterator.next(); XCTAssertFalse(stopped!.hasMedia)
    }
    func testStalePollFailureCannotOverwriteConfirmedCommand() async throws {
        let transport = RacingMediaTransport(playing: playback(), paused: playback(playing: false))
        let auth = SpotifyAuthorization(store: authorizedStore(), transport: transport)
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: auth, transport: transport, clock: clock)
        var iterator = await provider.updates().makeAsyncIterator()
        _ = await iterator.next()
        try await provider.connect()
        _ = await iterator.next()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(5))
        await transport.waitForHeldPoll()
        try await provider.perform(.playPause)
        let paused = await iterator.next()
        XCTAssertEqual(paused?.playbackState, .paused)
        await transport.failHeldPoll()
        await clock.waitForPendingSleeps()
        let availability = await provider.availability()
        XCTAssertEqual(availability, .available)
        try await provider.disconnect()
    }
    func testPollingWithoutSubscribersAndRetryAfter() async throws {
        let transport = ScriptedMediaTransport([
            .init(data: playback(), status: 200),
            .init(status: 429, retryAfter: 2),
            .init(data: playback(playing: false), status: 200)
        ])
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect() // No UI or subscribers exist.
        try await provider.connect() // Must not create a second poller.
        await clock.waitForPendingSleeps()
        var requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        await clock.advance(by: .milliseconds(499))
        requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        await clock.advance(by: .milliseconds(1))
        await clock.waitForPendingSleeps()
        requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        var iterator = await provider.updates().makeAsyncIterator()
        let preserved = await iterator.next()
        XCTAssertTrue(preserved?.isPlaying == true) // A transient 429 cannot remove the flanks.
        await clock.advance(by: .milliseconds(1999))
        requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        await clock.advance(by: .milliseconds(1))
        let paused = await iterator.next()
        XCTAssertEqual(paused?.playbackState, .paused)
        await clock.waitForPendingSleeps()
        await provider.shutdown()
        await clock.advance(by: .seconds(10))
        requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }
    func testLoopbackReceivesRegisteredRedirectAndCloses() async throws {
        let receiver = SpotifyLoopbackCallback()
        let callback = URL(string: SpotifyAuthorization.redirectURI + "?code=fixture&state=fixture")!
        let received = try await receiver.receive {
            Task {
                do { _ = try await URLSession.shared.data(from: callback) }
                catch { await receiver.cancel() }
            }
        }
        XCTAssertEqual(received, callback)
        await receiver.cancel()
    }
    func testNoDeviceAndErrorsNeverFakePlayback() async throws {
        let transport = ScriptedMediaTransport([.init(status: 204)])
        let api = SpotifyPlaybackAPI(authorization: .init(store: authorizedStore(), transport: transport), transport: transport)
        let state = try await api.state()
        XCTAssertFalse(state.hasMedia); XCTAssertFalse(state.canPlayPause)
    }
    func testQueueIsBoundedAndPreservesDuplicateTracksWithUniqueRows() async throws {
        let item = #"{"id":"same","name":"Awake","artists":[{"name":"Tycho"}]}"#
        let data = Data(("{\"queue\":[" + Array(repeating: item, count: 30).joined(separator: ",") + "]}").utf8)
        let transport = ScriptedMediaTransport([.init(data: data, status: 200)])
        let api = SpotifyPlaybackAPI(authorization: .init(store: authorizedStore(), transport: transport), transport: transport)
        let queue = try await api.queue()
        XCTAssertEqual(queue.count, 20); XCTAssertEqual(Set(queue.map(\.id)).count, 20)
    }
}
