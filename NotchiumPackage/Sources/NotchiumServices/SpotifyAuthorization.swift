import CryptoKit
import Foundation
import Security

public protocol SpotifyTokenStoring: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

public struct SpotifyKeychainStore: SpotifyTokenStoring {
    public init() {}
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Notchium.Spotify", kSecAttrAccount as String: "oauth"]
    }
    public func read() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MediaFailure.keychain }
        return result as? Data
    }
    public func write(_ data: Data) throws {
        let changes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MediaFailure.keychain }
        } else if status != errSecSuccess { throw MediaFailure.keychain }
    }
    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MediaFailure.keychain }
    }
}

public struct MediaHTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let retryAfter: Int?
    public init(data: Data = Data(), status: Int, retryAfter: Int? = nil) {
        self.data = data; self.status = status; self.retryAfter = retryAfter
    }
}
public protocol MediaHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> MediaHTTPResponse
}
public struct URLSessionMediaTransport: MediaHTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        session = URLSession(configuration: config)
    }
    public func send(_ request: URLRequest) async throws -> MediaHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 2_000_000 else {
            throw MediaFailure.invalidResponse
        }
        return .init(data: data, status: response.statusCode,
                     retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
    }
}

/// PKCE secrets live only for an authorization attempt. Persisted tokens live only in Keychain.
public actor SpotifyAuthorization {
    public static let redirectURI = "http://127.0.0.1:8888/callback"
    private struct Credentials: Codable {
        var clientID: String
        var accessToken: String
        var refreshToken: String
        var expiration: Date
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }
    private struct Attempt {
        let clientID: String
        let verifier: String
        let state: String
        let started: Date
    }
    private let store: any SpotifyTokenStoring
    private let transport: any MediaHTTPTransport
    private var attempt: Attempt?
    private var generation = 0
    private var credentials: Credentials?
    private var refreshing: Task<String, any Error>?
    public init(store: any SpotifyTokenStoring = SpotifyKeychainStore(),
                transport: any MediaHTTPTransport = URLSessionMediaTransport()) {
        self.store = store; self.transport = transport
    }
    public func begin(clientID: String) throws -> URL {
        guard clientID.count == 32, clientID.allSatisfy(\.isHexDigit) else { throw MediaFailure.authorization }
        generation &+= 1
        let verifier = try Self.randomString()
        let state = try Self.randomString()
        attempt = Attempt(clientID: clientID, verifier: verifier, state: state, started: Date())
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI), .init(name: "state", value: state),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-currently-playing")
        ]
        return components.url!
    }
    public func complete(callback: URL) async throws {
        let generation = generation
        guard let attempt else { throw MediaFailure.authorization }
        self.attempt = nil
        guard Date().timeIntervalSince(attempt.started) < 300,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.scheme == "http", components.host == "127.0.0.1",
              components.port == 8888, components.path == "/callback",
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw MediaFailure.authorization
        }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == attempt.state,
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
              !items.contains(where: { $0.name == "error" }) else { throw MediaFailure.authorization }
        let token = try await exchange([
            "client_id": attempt.clientID, "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "code_verifier": attempt.verifier
        ])
        try Task.checkCancellation()
        guard self.generation == generation else { throw MediaFailure.authorization }
        guard let refresh = token.refresh_token else { throw MediaFailure.authorization }
        try save(.init(clientID: attempt.clientID, accessToken: token.access_token,
                       refreshToken: refresh, expiration: Date().addingTimeInterval(token.expires_in)))
    }
    public func accessToken() async throws -> String {
        if let refreshing { return try await refreshing.value }
        if credentials == nil, let data = try store.read() {
            credentials = try JSONDecoder().decode(Credentials.self, from: data)
        }
        guard let current = credentials else { throw MediaFailure.disconnected }
        if current.expiration.timeIntervalSinceNow > 60 { return current.accessToken }
        let task = Task { try await self.refresh(current) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }
    public func disconnect() throws {
        generation &+= 1
        refreshing?.cancel(); refreshing = nil; attempt = nil; credentials = nil
        try store.remove()
    }
    private func refresh(_ current: Credentials) async throws -> String {
        let token = try await exchange(["grant_type": "refresh_token", "client_id": current.clientID,
                                        "refresh_token": current.refreshToken])
        try Task.checkCancellation()
        try save(.init(clientID: current.clientID, accessToken: token.access_token,
                       refreshToken: token.refresh_token ?? current.refreshToken,
                       expiration: Date().addingTimeInterval(token.expires_in)))
        return token.access_token
    }
    private func save(_ value: Credentials) throws {
        try store.write(JSONEncoder().encode(value)); credentials = value
    }
    private func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let response = try await transport.send(request)
        if response.status == 429 { throw MediaFailure.rateLimited(max(1, response.retryAfter ?? 30)) }
        guard response.status == 200 else { throw MediaFailure.authorization }
        let token = try JSONDecoder().decode(TokenResponse.self, from: response.data)
        guard !token.access_token.isEmpty, token.expires_in.isFinite, token.expires_in > 0 else {
            throw MediaFailure.authorization
        }
        return token
    }
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(fields.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MediaFailure.authorization
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
