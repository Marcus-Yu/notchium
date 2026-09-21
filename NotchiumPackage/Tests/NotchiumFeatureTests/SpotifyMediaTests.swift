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
    func rateLimitHeldPoll() { held?.resume(returning: .init(status: 429, retryAfter: 60)); held = nil }
    func failHeldPoll() { held?.resume(throwing: MediaFailure.invalidResponse); held = nil }
}

private actor HeldNextTransport: MediaHTTPTransport {
    let playback: Data
    private var next: CheckedContinuation<MediaHTTPResponse, any Error>?
    init(playback: Data) { self.playback = playback }
    func send(_ request: URLRequest) async throws -> MediaHTTPResponse {
        if request.url?.path.hasSuffix("/next") == true {
            return try await withCheckedThrowingContinuation { next = $0 }
        }
        return request.httpMethod == "GET" ? .init(data: playback, status: 200) : .init(status: 204)
    }
    func waitForNext() async { while next == nil { await Task.yield() } }
    func finishNext() { next?.resume(returning: .init(status: 204)); next = nil }
}

private actor OverlappingAuthorizationTransport: MediaHTTPTransport {
    private var heldRefresh: CheckedContinuation<MediaHTTPResponse, any Error>?
    private var refreshObserver: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> MediaHTTPResponse {
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        if body.contains("grant_type=refresh_token") {
            return try await withCheckedThrowingContinuation { continuation in
                heldRefresh = continuation
                refreshObserver?.resume()
                refreshObserver = nil
            }
        }
        if body.contains("grant_type=authorization_code") {
            return .init(data: Data(
                #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8
            ), status: 200)
        }
        return .init(status: 204)
    }

    func waitForHeldRefresh() async {
        if heldRefresh != nil { return }
        await withCheckedContinuation { refreshObserver = $0 }
    }

    func finishHeldRefresh() {
        heldRefresh?.resume(returning: .init(data: Data(
            #"{"access_token":"stale-access","expires_in":3600}"#.utf8
        ), status: 200))
        heldRefresh = nil
    }
}

private actor HeldQueueTransport: MediaHTTPTransport {
    let playback: Data
    private var held: CheckedContinuation<MediaHTTPResponse, Never>?
    private(set) var queueRequests = 0
    private var changed = false
    init(playback: Data) { self.playback = playback }
    func send(_ request: URLRequest) async -> MediaHTTPResponse {
        if request.url?.path.hasSuffix("/next") == true {
            changed = true
            return .init(status: 204)
        }
        if request.url?.path.hasSuffix("/queue") == true {
            queueRequests += 1
            if queueRequests == 1 { return await withCheckedContinuation { held = $0 } }
            return .init(data: Data(#"{"queue":[{"id":"new","uri":"spotify:track:new","name":"New queue"}]}"#.utf8), status: 200)
        }
        let data = changed ? Data(String(decoding: playback, as: UTF8.self)
            .replacingOccurrences(of: "track-1", with: "track-2").utf8) : playback
        return .init(data: data, status: 200)
    }
    func waitForQueue() async { while held == nil { await Task.yield() } }
    func finishQueue() {
        held?.resume(returning: .init(data: Data(#"{"queue":[]}"#.utf8), status: 200))
        held = nil
    }
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
    func testFreshAuthorizationInstanceRestoresPersistedSession() async throws {
        let store = authorizedStore()
        let transport = ScriptedMediaTransport([])
        let authorization = SpotifyAuthorization(store: store, transport: transport)

        let token = try await authorization.accessToken()
        let requests = await transport.requests
        XCTAssertEqual(token, "fixture-access")
        XCTAssertTrue(requests.isEmpty)
    }
    func testFreshAuthorizationInstanceRefreshesExpiredPersistedSession() async throws {
        let store = MemorySpotifyStore(data: Data(
            #"{"clientID":"fixture","accessToken":"expired","refreshToken":"fixture-refresh","expiration":0}"#.utf8
        ))
        let transport = ScriptedMediaTransport([
            .init(data: Data(#"{"access_token":"restored","expires_in":3600}"#.utf8), status: 200),
        ])
        let authorization = SpotifyAuthorization(store: store, transport: transport)

        let token = try await authorization.accessToken()
        let requests = await transport.requests
        XCTAssertEqual(token, "restored")
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody).formattedForTest
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=fixture-refresh"))

        let relaunched = SpotifyAuthorization(store: store, transport: ScriptedMediaTransport([]))
        let relaunchedToken = try await relaunched.accessToken()
        XCTAssertEqual(relaunchedToken, "restored")
    }
    func testExpiredSessionRefreshPublishesAuthenticatedInactiveState() async throws {
        let store = MemorySpotifyStore(data: Data(
            #"{"clientID":"fixture","accessToken":"expired","refreshToken":"fixture-refresh","expiration":0}"#.utf8
        ))
        let transport = ScriptedMediaTransport([
            .init(data: Data(#"{"access_token":"restored","expires_in":3600}"#.utf8), status: 200),
            .init(status: 204),
        ])
        let provider = RealMediaProvider(
            authorization: SpotifyAuthorization(store: store, transport: transport),
            transport: transport
        )
        var iterator = await provider.updates().makeAsyncIterator()
        _ = await iterator.next()

        try await provider.connect()
        let authenticated = await iterator.next()
        XCTAssertEqual(authenticated?.connectionState, .authenticated)
        XCTAssertEqual(authenticated?.experienceState, .inactive)
        await provider.shutdown()
    }
    func testFailedSessionRefreshPublishesErrorInsteadOfRemainingInitializing() async throws {
        let store = MemorySpotifyStore(data: Data(
            #"{"clientID":"fixture","accessToken":"expired","refreshToken":"fixture-refresh","expiration":0}"#.utf8
        ))
        let transport = ScriptedMediaTransport([.init(status: 400)])
        let provider = RealMediaProvider(
            authorization: SpotifyAuthorization(store: store, transport: transport),
            transport: transport
        )
        var iterator = await provider.updates().makeAsyncIterator()
        _ = await iterator.next()

        do {
            try await provider.connect()
            XCTFail("Failed refresh restored the session")
        } catch {
            XCTAssertEqual(error as? MediaFailure, .authorization)
        }
        let failed = await iterator.next()
        XCTAssertEqual(failed?.connectionState, .error)
        XCTAssertEqual(failed?.experienceState, .error)
    }
    func testInteractiveOAuthPreservesRateLimitAndPublishesAuthenticated() async throws {
        let store = authorizedStore()
        let transport = ScriptedMediaTransport([
            .init(status: 429, retryAfter: 36_000),
            .init(data: Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8),
                  status: 200),
            .init(status: 204),
        ])
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(
            authorization: SpotifyAuthorization(store: store, transport: transport),
            transport: transport,
            clock: clock
        )
        try await provider.connect()
        await clock.waitForPendingSleeps()
        var current = await provider.updates().makeAsyncIterator()
        let rateLimited = await current.next()
        XCTAssertEqual(rateLimited?.connectionState, .authenticated)
        XCTAssertEqual(rateLimited?.rateLimitedUntil, Date(timeIntervalSince1970: 36_000))

        try await provider.disconnect()
        let clientID = String(repeating: "c", count: 32)
        let authorizationURL = try await provider.beginAuthorization(clientID: clientID)
        var authorizing = await provider.updates().makeAsyncIterator()
        let authorizingState = await authorizing.next()
        XCTAssertEqual(authorizingState?.experienceState, .authorizing)
        let state = try XCTUnwrap(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value)
        let callback = try XCTUnwrap(URL(string: SpotifyAuthorization.redirectURI + "?code=fixture&state=" + state))
        try await provider.completeAuthorization(callback: callback)

        await clock.waitForPendingSleeps()
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2, "OAuth must not bypass the existing playback cooldown")
        var reconnected = await provider.updates().makeAsyncIterator()
        let stateAfterReconnect = await reconnected.next()
        XCTAssertEqual(stateAfterReconnect?.connectionState, .authenticated)
        XCTAssertEqual(stateAfterReconnect?.experienceState, .inactive)
        XCTAssertEqual(stateAfterReconnect?.rateLimitedUntil, Date(timeIntervalSince1970: 36_000))
        await clock.advance(by: .seconds(36_000))
        await clock.waitForPendingSleeps()
        let resumedRequests = await transport.requests
        XCTAssertEqual(resumedRequests.count, 3)
        await provider.shutdown()
    }
    func testFreshInteractiveLoginLeavesAuthorizingAndHandlesNoPlayback() async throws {
        let store = MemorySpotifyStore()
        let transport = ScriptedMediaTransport([
            .init(data: Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8),
                  status: 200),
            .init(status: 204),
        ])
        let provider = RealMediaProvider(
            authorization: SpotifyAuthorization(store: store, transport: transport),
            transport: transport
        )
        do { try await provider.connect(); XCTFail("Missing credentials restored") }
        catch { XCTAssertEqual(error as? MediaFailure, .disconnected) }

        let authorizationURL = try await provider.beginAuthorization(clientID: String(repeating: "d", count: 32))
        var current = await provider.updates().makeAsyncIterator()
        let authorizing = await current.next()
        XCTAssertEqual(authorizing?.experienceState, .authorizing)
        let state = try XCTUnwrap(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value)
        let callback = try XCTUnwrap(URL(string: SpotifyAuthorization.redirectURI + "?code=fixture&state=" + state))
        try await provider.completeAuthorization(callback: callback)

        for _ in 0..<100 where await transport.requests.count < 2 { await Task.yield() }
        var authenticated = await provider.updates().makeAsyncIterator()
        let inactive = await authenticated.next()
        XCTAssertEqual(inactive?.connectionState, .authenticated)
        XCTAssertEqual(inactive?.experienceState, .inactive)
        XCTAssertNotNil(store.read())
        await provider.shutdown()
    }
    func testInteractiveAuthorizationCancellationAndFailureLeaveTransientState() async throws {
        let provider = RealMediaProvider(
            authorization: SpotifyAuthorization(store: MemorySpotifyStore(), transport: ScriptedMediaTransport([])),
            transport: ScriptedMediaTransport([])
        )
        _ = try await provider.beginAuthorization(clientID: String(repeating: "f", count: 32))
        await provider.cancelAuthorization()
        var cancelled = await provider.updates().makeAsyncIterator()
        let cancelledState = await cancelled.next()
        XCTAssertEqual(cancelledState?.connectionState, .unauthenticated)

        _ = try await provider.beginAuthorization(clientID: String(repeating: "f", count: 32))
        await provider.failAuthorization()
        var failed = await provider.updates().makeAsyncIterator()
        let failedState = await failed.next()
        XCTAssertEqual(failedState?.connectionState, .error)
    }
    func testInteractiveOAuthSupersedesInFlightColdLaunchRefresh() async throws {
        let store = MemorySpotifyStore(data: Data(
            #"{"clientID":"old-client","accessToken":"expired","refreshToken":"old-refresh","expiration":0}"#.utf8
        ))
        let transport = OverlappingAuthorizationTransport()
        let authorization = SpotifyAuthorization(store: store, transport: transport)
        let provider = RealMediaProvider(authorization: authorization, transport: transport)
        let restoration = Task { try await provider.connect() }
        await transport.waitForHeldRefresh()

        let authorizationURL = try await provider.beginAuthorization(clientID: String(repeating: "e", count: 32))
        let state = try XCTUnwrap(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value)
        let callback = try XCTUnwrap(URL(string: SpotifyAuthorization.redirectURI + "?code=fixture&state=" + state))
        try await provider.completeAuthorization(callback: callback)
        await transport.finishHeldRefresh()
        do { try await restoration.value; XCTFail("Obsolete restoration completed") }
        catch { XCTAssertTrue(error is CancellationError) }

        let relaunched = SpotifyAuthorization(store: store, transport: ScriptedMediaTransport([]))
        let relaunchedToken = try await relaunched.accessToken()
        XCTAssertEqual(relaunchedToken, "new-access")
        var current = await provider.updates().makeAsyncIterator()
        let connected = await current.next()
        XCTAssertEqual(connected?.connectionState, .authenticated)
        XCTAssertNotEqual(connected?.experienceState, .initializing)
        await provider.shutdown()
    }
    func testColdLaunchWithoutCredentialsPublishesUnauthenticatedState() async throws {
        let transport = ScriptedMediaTransport([])
        let provider = RealMediaProvider(
            authorization: SpotifyAuthorization(store: MemorySpotifyStore(), transport: transport),
            transport: transport
        )
        var iterator = await provider.updates().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.connectionState, .initializing)

        do {
            try await provider.connect()
            XCTFail("Missing Spotify credentials restored")
        } catch {
            XCTAssertEqual(error as? MediaFailure, .disconnected)
        }
        let disconnected = await iterator.next()
        XCTAssertEqual(disconnected?.connectionState, .unauthenticated)
        XCTAssertEqual(disconnected?.experienceState, .unauthenticated)
    }
    func testColdLaunchWithoutSpotifyPlaybackStaysAuthenticatedAndDetectsPlaybackLater() async throws {
        let transport = ScriptedMediaTransport([
            .init(status: 204),
            .init(data: playback(), status: 200),
        ])
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(
            authorization: SpotifyAuthorization(store: authorizedStore(), transport: transport),
            transport: transport,
            clock: clock
        )
        var iterator = await provider.updates().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.experienceState, .initializing)

        try await provider.connect()
        let inactive = await iterator.next()
        XCTAssertEqual(inactive?.connectionState, .authenticated)
        XCTAssertEqual(inactive?.experienceState, .inactive)

        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(15))
        var playing = await iterator.next()
        if playing?.isPlaying != true { playing = await iterator.next() }
        XCTAssertEqual(playing?.experienceState, .playing)
        await provider.shutdown()
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
        var playing = await iterator.next()
        if playing?.hasMedia != true { playing = await iterator.next() }
        XCTAssertTrue(playing!.isPlaying)
        await clock.waitForPendingSleeps()
        let intervals = await clock.sleepHistory(); XCTAssertEqual(intervals, [.seconds(5)])
        try await provider.perform(.playPause)
        let paused = await iterator.next(); XCTAssertEqual(paused!.playbackState, .paused)
        try await provider.perform(.seek(122))
        let sought = await iterator.next(); XCTAssertEqual(sought!.progress, 0.5)
        do { try await provider.perform(.previous); XCTFail("Rate limit ignored") }
        catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(60)) }
        do { try await provider.perform(.previous); XCTFail("Backoff ignored") }
        catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(60)) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(requests[1].url?.path, "/v1/me/player/pause")
        XCTAssertEqual(requests[3].url?.query, "position_ms=122000")
        XCTAssertEqual(requests[5].httpMethod, "POST")
        try await provider.disconnect()
        var disconnected = await provider.updates().makeAsyncIterator()
        let stopped = await disconnected.next(); XCTAssertFalse(stopped!.hasMedia)
    }
    func testStalePollFailureCannotOverwriteConfirmedCommand() async throws {
        let transport = RacingMediaTransport(playing: playback(), paused: playback(playing: false))
        let auth = SpotifyAuthorization(store: authorizedStore(), transport: transport)
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: auth, transport: transport, clock: clock)
        var iterator = await provider.updates().makeAsyncIterator()
        _ = await iterator.next()
        try await provider.connect()
        var connected = await iterator.next()
        if connected?.hasMedia != true { connected = await iterator.next() }
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
        await clock.advance(by: .milliseconds(4_999))
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
        await clock.advance(by: .seconds(20))
        requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testInitialAndRepeated429SuspendAllEndpointsWithoutLosingCredentials() async throws {
        let store = authorizedStore()
        let transport = ScriptedMediaTransport([
            .init(status: 429, retryAfter: 60),
            .init(status: 429, retryAfter: 60),
            .init(data: playback(), status: 200),
        ])
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: store, transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        for cycle in 0..<2 {
            var iterator = await provider.updates().makeAsyncIterator()
            let state = await iterator.next()
            XCTAssertEqual(state?.connectionState, .authenticated)
            XCTAssertEqual(state?.rateLimitedUntil, Date(timeIntervalSince1970: Double((cycle + 1) * 60)))
            XCTAssertNotNil(store.read())
            for _ in 0..<10 {
                try await provider.connect()
                _ = await provider.updates()
                await provider.refresh()
                try? await provider.loadQueue()
                try? await provider.addToQueue(uri: "spotify:track:fixture")
                try? await provider.pause()
            }
            await clock.advance(by: .seconds(59))
            let before = await transport.requests.count
            XCTAssertEqual(before, cycle + 1)
            let sleepers = await clock.pendingSleepCount()
            XCTAssertEqual(sleepers, 1)
            await clock.advance(by: .seconds(1))
            await clock.waitForPendingSleeps()
            let after = await transport.requests.count
            XCTAssertEqual(after, cycle + 2)
        }
        var iterator = await provider.updates().makeAsyncIterator()
        let recovered = await iterator.next()
        XCTAssertTrue(recovered?.isPlaying == true)
        XCTAssertNil(recovered?.rateLimitedUntil)
        XCTAssertNil(recovered?.issue)
        await provider.shutdown()
    }

    func testFiveMinutesOfPollingWithRepeatedSubscriptionsHasOneLoop() async throws {
        for playing in [true, false] {
            let interval = playing ? 5 : 15
            let cycles = 300 / interval
            let response = playing ? MediaHTTPResponse(data: playback(), status: 200) : .init(status: 204)
            let transport = ScriptedMediaTransport(Array(repeating: response, count: cycles + 1))
            let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
            let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                             transport: transport, clock: clock)
            async let first: Void = provider.connect()
            async let second: Void = provider.connect()
            _ = try await (first, second)
            await clock.waitForPendingSleeps()
            for _ in 0..<cycles {
                // View lifetime changes only create/remove subscribers, never permanent pollers.
                _ = await provider.updates()
                try await provider.connect()
                await clock.advance(by: .seconds(interval))
                await clock.waitForPendingSleeps()
                let sleepers = await clock.pendingSleepCount()
                XCTAssertEqual(sleepers, 1)
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, cycles + 1)
            XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/v1/me/player" })
            await provider.shutdown()
        }
    }

    func testOrdinaryQueueReadsAreCachedButExplicitRefreshBypassesCache() async throws {
        let queue = MediaHTTPResponse(data: Data(#"{"queue":[]}"#.utf8), status: 200)
        let transport = ScriptedMediaTransport([.init(data: playback(), status: 200), queue, queue])
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        for _ in 0..<20 { try await provider.loadQueue() }
        var requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/v1/me/player/queue" }.count, 1)
        try await provider.refreshQueue()
        requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/v1/me/player/queue" }.count, 2)
        await provider.shutdown()
    }

    func testQueue429BlocksPlaybackAndControlsAtSharedBoundary() async throws {
        let transport = ScriptedMediaTransport([.init(status: 429, retryAfter: 60), .init(status: 204)])
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let api = SpotifyPlaybackAPI(authorization: .init(store: authorizedStore(), transport: transport),
                                     transport: transport, clock: clock)
        do { _ = try await api.queue(); XCTFail("Expected 429") }
        catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(60)) }
        await clock.advance(by: .seconds(59))
        for path in ["", "/queue", "/seek", "/pause"] {
            do { _ = try await api.request(path: path); XCTFail("Cooldown bypassed") }
            catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(1)) }
        }
        let before = await transport.requests.count
        XCTAssertEqual(before, 1)
        await clock.advance(by: .seconds(1))
        _ = try await api.state()
        let after = await transport.requests.count
        XCTAssertEqual(after, 2)
    }

    func testStalePoll429StillBlocksRequestsAfterConfirmedCommand() async throws {
        let transport = RacingMediaTransport(playing: playback(), paused: playback(playing: false))
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(5))
        await transport.waitForHeldPoll()
        try await provider.pause()
        await transport.rateLimitHeldPoll()
        await clock.waitForPendingSleeps()
        var iterator = await provider.updates().makeAsyncIterator()
        let state = await iterator.next()
        XCTAssertEqual(state?.playbackState, .paused)
        XCTAssertEqual(state?.connectionState, .authenticated)
        XCTAssertEqual(state?.rateLimitedUntil, Date(timeIntervalSince1970: 65))
        await provider.refresh()
        do { try await provider.play(); XCTFail("Stale 429 was discarded") }
        catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(60)) }
        let sleeps = await clock.sleepHistory()
        XCTAssertEqual(sleeps, [.seconds(5), .seconds(60)])
        await provider.shutdown()
    }

    func testQueue429PublishesAuthenticatedCooldownAndSuspendsExistingPoller() async throws {
        let store = authorizedStore()
        let transport = ScriptedMediaTransport([
            .init(data: playback(), status: 200), .init(status: 429, retryAfter: 60),
            .init(data: playback(), status: 200),
        ])
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: store, transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        do { try await provider.loadQueue(); XCTFail("Expected 429") }
        catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(60)) }
        var iterator = await provider.updates().makeAsyncIterator()
        let state = await iterator.next()
        XCTAssertEqual(state?.connectionState, .authenticated)
        XCTAssertTrue(state?.hasMedia == true)
        XCTAssertEqual(state?.rateLimitedUntil, Date(timeIntervalSince1970: 60))
        await clock.advance(by: .seconds(5))
        await clock.waitForPendingSleeps()
        await provider.refresh()
        try? await provider.pause()
        try? await provider.loadQueue()
        await clock.advance(by: .seconds(54))
        let before = await transport.requests.count
        XCTAssertEqual(before, 2)
        XCTAssertNotNil(store.read())
        await clock.advance(by: .seconds(1))
        await clock.waitForPendingSleeps()
        let after = await transport.requests.count
        XCTAssertEqual(after, 3)
        await provider.shutdown()
    }

    func testTokenRefresh429IsNotRetriedByPlaybackOrQueueDuringCooldown() async throws {
        let store = MemorySpotifyStore(data: Data(
            #"{"clientID":"fixture","accessToken":"expired","refreshToken":"fixture-refresh","expiration":0}"#.utf8))
        let transport = ScriptedMediaTransport([.init(status: 429, retryAfter: 60)])
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let api = SpotifyPlaybackAPI(authorization: .init(store: store, transport: transport),
                                     transport: transport, clock: clock)
        for path in ["", "/queue", ""] {
            do { _ = try await api.request(path: path); XCTFail("Expected 429") }
            catch { XCTAssertEqual(error as? MediaFailure, .rateLimited(60)) }
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/api/token")
        XCTAssertNotNil(store.read())
    }
    func testTrackChangeDuringQueueFetchCoalescesAndFetchesLatestQueue() async throws {
        let data = Data(String(decoding: playback(), as: UTF8.self)
            .replacingOccurrences(of: "\"skipping_next\":true", with: "\"skipping_next\":false").utf8)
        let transport = HeldQueueTransport(playback: data)
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        let queue = Task { try await provider.loadQueue() }
        await transport.waitForQueue()
        try await provider.nextTrack()
        try await provider.loadQueue()
        let pendingCount = await transport.queueRequests
        XCTAssertEqual(pendingCount, 1)
        await transport.finishQueue()
        try await queue.value
        let finalCount = await transport.queueRequests
        XCTAssertEqual(finalCount, 2)
        var iterator = await provider.updates().makeAsyncIterator()
        let state = await iterator.next()
        XCTAssertEqual(state?.trackID, "track-2")
        XCTAssertEqual(state?.queue.first?.title, "New queue")
        await provider.shutdown()
    }

    func testColdLaunchToken429RetainsSessionAndRetriesOnlyAfterDeadline() async throws {
        let store = MemorySpotifyStore(data: Data(
            #"{"clientID":"fixture","accessToken":"expired","refreshToken":"fixture-refresh","expiration":0}"#.utf8))
        let transport = ScriptedMediaTransport([
            .init(status: 429, retryAfter: 60),
            .init(data: Data(#"{"access_token":"renewed","expires_in":3600}"#.utf8), status: 200),
            .init(status: 204),
        ])
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: store, transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        var iterator = await provider.updates().makeAsyncIterator()
        let state = await iterator.next()
        XCTAssertEqual(state?.connectionState, .authenticated)
        XCTAssertEqual(state?.rateLimitedUntil, Date(timeIntervalSince1970: 60))
        try await provider.connect()
        await provider.refresh()
        await clock.advance(by: .seconds(59))
        let before = await transport.requests.count
        XCTAssertEqual(before, 1)
        await clock.advance(by: .seconds(1))
        await clock.waitForPendingSleeps()
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url?.path), ["/api/token", "/api/token", "/v1/me/player"])
        XCTAssertNotNil(store.read())
        await provider.shutdown()
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
        let item = #"{"id":"same","uri":"spotify:track:same","name":"Awake","type":"track","duration_ms":216000,"artists":[{"name":"Tycho"}]}"#
        let data = Data(("{\"queue\":[" + Array(repeating: item, count: 30).joined(separator: ",") + "]}").utf8)
        let transport = ScriptedMediaTransport([.init(data: data, status: 200)])
        let api = SpotifyPlaybackAPI(authorization: .init(store: authorizedStore(), transport: transport), transport: transport)
        let queue = try await api.queue()
        XCTAssertEqual(queue.count, 20); XCTAssertEqual(Set(queue.map(\.id)).count, 20)
    }

    func testQueueResponseMapsRequiredTrackFields() async throws {
        let data = Data(#"{"currently_playing":null,"queue":[{"id":"awake","uri":"spotify:track:awake","name":"Awake","type":"track","duration_ms":216000,"artists":[{"name":"Tycho"}],"album":{"images":[{"url":"https://i.scdn.co/image/awake","width":300}]}}]}"#.utf8)
        let transport = ScriptedMediaTransport([.init(data: data, status: 200)])
        let api = SpotifyPlaybackAPI(authorization: .init(store: authorizedStore(), transport: transport),
                                     transport: transport)
        let queue = try await api.queue()
        XCTAssertEqual(queue, [.init(id: "awake:0", uri: "spotify:track:awake", title: "Awake",
                                     artist: "Tycho", artworkURL: URL(string: "https://i.scdn.co/image/awake"),
                                     duration: 216)])
    }

    func testSeekConvertsSixtySecondsToMilliseconds() async throws {
        let state = try JSONDecoder().decode(SpotifyPlayback.self, from: playback()).mediaState()
        let transport = ScriptedMediaTransport([.init(status: 204)])
        let api = SpotifyPlaybackAPI(authorization: .init(store: authorizedStore(), transport: transport),
                                     transport: transport)
        try await api.perform(.seek(60), state: state)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/v1/me/player/seek")
        XCTAssertEqual(request.url?.query, "position_ms=60000")
    }

    func testAddToQueueSendsEncodedSpotifyURI() async throws {
        let transport = ScriptedMediaTransport([.init(status: 204)])
        let api = SpotifyPlaybackAPI(authorization: .init(store: authorizedStore(), transport: transport),
                                     transport: transport)
        try await api.addToQueue(uri: "spotify:track:awake")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/me/player/queue")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
                       [.init(name: "uri", value: "spotify:track:awake")])
    }

    func testRealProviderAddToQueueImmediatelyRefreshesQueue() async throws {
        let queueData = Data(#"{"currently_playing":null,"queue":[{"id":"awake","uri":"spotify:track:awake","name":"Awake","type":"track","duration_ms":216000,"artists":[{"name":"Tycho"}]}]}"#.utf8)
        let transport = ScriptedMediaTransport([
            .init(data: playback(), status: 200),
            .init(status: 204),
            .init(data: queueData, status: 200),
        ])
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        var iterator = await provider.updates().makeAsyncIterator()
        _ = await iterator.next()
        try await provider.connect()
        var connected = await iterator.next()
        if connected?.hasMedia != true { connected = await iterator.next() }
        try await provider.addToQueue(uri: "spotify:track:awake")
        let queued = await iterator.next()
        XCTAssertEqual(queued?.queue.first?.uri, "spotify:track:awake")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url?.path), [
            "/v1/me/player", "/v1/me/player/queue", "/v1/me/player/queue",
        ])
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertEqual(requests[2].httpMethod, "GET")
        await provider.shutdown()
    }

    func testEverySpotifyCommandImmediatelyRefreshesWithoutPolling() async throws {
        let data = Data(String(decoding: playback(), as: UTF8.self)
            .replacingOccurrences(of: "\"skipping_next\":true", with: "\"skipping_next\":false").utf8)
        let commands: [MediaCommand] = [.pause, .play, .next, .previous, .seek(122),
                                       .setShuffle(true), .setShuffle(false),
                                       .setRepeatMode(.context), .setRepeatMode(.track), .setRepeatMode(.off)]
        var responses: [MediaHTTPResponse] = [.init(data: data, status: 200)]
        for _ in commands { responses += [.init(status: 204), .init(data: data, status: 200)] }
        let transport = ScriptedMediaTransport(responses)
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        for command in commands { try await provider.perform(command) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 21)
        let paths = ["pause", "play", "next", "previous", "seek", "shuffle", "shuffle", "repeat", "repeat", "repeat"]
        let queries: [String?] = [nil, nil, nil, nil, "position_ms=122000", "state=true", "state=false",
                                 "state=context", "state=track", "state=off"]
        for index in commands.indices {
            XCTAssertEqual(requests[1 + index * 2].url?.path, "/v1/me/player/" + paths[index])
            XCTAssertEqual(requests[1 + index * 2].httpMethod, (index == 2 || index == 3) ? "POST" : "PUT")
            XCTAssertEqual(requests[1 + index * 2].url?.query, queries[index])
            XCTAssertEqual(requests[2 + index * 2].httpMethod, "GET")
            XCTAssertEqual(requests[2 + index * 2].url?.path, "/v1/me/player")
        }
        await provider.shutdown()
    }
    func testNextKeepsLastTrackThroughEmptyConfirmationAndFindsReplacementPromptly() async throws {
        let initial = Data(String(decoding: playback(), as: UTF8.self)
            .replacingOccurrences(of: "\"skipping_next\":true", with: "\"skipping_next\":false").utf8)
        let replacement = Data(String(decoding: playback(elapsed: 0), as: UTF8.self)
            .replacingOccurrences(of: "\"skipping_next\":true", with: "\"skipping_next\":false")
            .replacingOccurrences(of: "track-1", with: "track-2")
            .replacingOccurrences(of: "Midnight City", with: "Next Track").utf8)
        let transport = ScriptedMediaTransport([
            .init(data: initial, status: 200),
            .init(status: 204),
            .init(status: 204),
            .init(data: replacement, status: 200),
        ])
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        try await provider.nextTrack()

        var current = await provider.updates().makeAsyncIterator()
        let held = await current.next()
        XCTAssertEqual(held?.trackID, "track-1")
        XCTAssertTrue(held?.hasMedia == true)

        await clock.waitForPendingSleeps(2)
        await clock.advance(by: .milliseconds(250))
        for _ in 0..<50 where await transport.requests.count < 4 { await Task.yield() }
        var replaced = await provider.updates().makeAsyncIterator()
        let next = await replaced.next()
        XCTAssertEqual(next?.trackID, "track-2")
        XCTAssertEqual(next?.title, "Next Track")
        await provider.shutdown()
    }
    func testNoActiveDeviceFailureRecoversWithDisabledCapabilities() async throws {
        let transport = ScriptedMediaTransport([.init(data: playback(), status: 200),
                                                 .init(status: 404), .init(status: 404)])
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        do { try await provider.pause(); XCTFail("Missing device accepted") }
        catch { XCTAssertEqual(error as? MediaFailure, .disconnected) }
        await provider.refresh()
        var iterator = await provider.updates().makeAsyncIterator()
        let state = await iterator.next()
        XCTAssertEqual(state?.title, "Midnight City")
        XCTAssertFalse(state?.canPlayPause ?? true)
        XCTAssertFalse(state?.canSeek ?? true)
        await provider.shutdown()
    }
    func testRealProviderAllowsPauseWhileNextIsPendingAndRejectsDuplicateNext() async throws {
        let data = Data(String(decoding: playback(), as: UTF8.self)
            .replacingOccurrences(of: "\"skipping_next\":true", with: "\"skipping_next\":false").utf8)
        let transport = HeldNextTransport(playback: data)
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let provider = RealMediaProvider(authorization: .init(store: authorizedStore(), transport: transport),
                                         transport: transport, clock: clock)
        try await provider.connect()
        await clock.waitForPendingSleeps()
        let next = Task { try await provider.nextTrack() }
        await transport.waitForNext()
        do { try await provider.nextTrack(); XCTFail("Duplicate next accepted") }
        catch { XCTAssertEqual(error as? MediaFailure, .busy) }
        try await provider.pause() // Must finish while Next is still held.
        await transport.finishNext()
        try await next.value
        await provider.shutdown()
    }
}

private extension Data {
    var formattedForTest: String { String(decoding: self, as: UTF8.self) }
}
