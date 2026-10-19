import CryptoKit
import Foundation

/// MangaBaka's OAuth 2.0 authorization code flow with PKCE, for public clients.
///
/// Register the app on mangabaka.org as a public application with your redirect URI, then:
/// 1. Open ``authorizationRequest(scopes:)``'s `url` in a browser session (for example
///    `ASWebAuthenticationSession`) and keep the returned request.
/// 2. Pass the callback URL to ``authorizationCode(from:matching:)``.
/// 3. Exchange the code with ``exchangeCode(_:for:)`` and store the ``MangaBakaToken``.
/// 4. Send ``MangaBakaToken/accessToken`` as ``MangaBakaCredential/oauthAccessToken(_:)``.
///    Before ``MangaBakaToken/expiresAt``, or after a 401, call ``refresh(_:)`` and store the result.
/// 5. On sign-out, call ``revoke(_:)``.
public struct MangaBakaOAuth: Sendable {
    /// The scopes a tracker needs: reading and writing the library, and refresh tokens.
    public static let libraryScopes = ["library.read", "library.write", "offline_access"]

    private static let authorizeURL = endpoint("https://mangabaka.org/auth/oauth2/authorize")
    private static let tokenURL = endpoint("https://mangabaka.org/auth/oauth2/token")
    private static let revokeURL = endpoint("https://mangabaka.org/auth/oauth2/revoke")

    private let clientID: String
    private let redirectURI: String
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - clientID: The client ID of a public MangaBaka application.
    ///   - redirectURI: A redirect URI registered for the application.
    ///   - session: The `URLSession` for token requests.
    public init(clientID: String, redirectURI: String, session: URLSession = .shared) {
        self.init(clientID: clientID, redirectURI: redirectURI, now: { Date() }, send: { request in
            try await session.data(for: request)
        })
    }

    internal init(
        clientID: String,
        redirectURI: String,
        now: @escaping @Sendable () -> Date,
        send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.now = now
        self.send = send
    }

    /// Creates the URL to sign in with, with a fresh code verifier and state.
    public func authorizationRequest(scopes: [String] = MangaBakaOAuth.libraryScopes) -> MangaBakaAuthorizationRequest {
        let codeVerifier = Self.randomString(length: 64)
        let state = Self.randomString(length: 32)
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return MangaBakaAuthorizationRequest(
            url: components?.url ?? Self.authorizeURL,
            codeVerifier: codeVerifier,
            state: state
        )
    }

    /// Reads the authorization code from the redirect MangaBaka sent the browser to.
    /// - Throws: ``MangaBakaOAuthError`` when access was denied, the state does not match, or no code is present.
    public func authorizationCode(from callbackURL: URL, matching request: MangaBakaAuthorizationRequest) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw MangaBakaOAuthError.authorizationFailed(error: error, description: value("error_description"))
        }
        guard value("state") == request.state else {
            throw MangaBakaOAuthError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw MangaBakaOAuthError.missingCode
        }
        return code
    }

    /// Exchanges an authorization code for tokens.
    public func exchangeCode(_ code: String, for request: MangaBakaAuthorizationRequest) async throws -> MangaBakaToken {
        try await requestToken([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: request.codeVerifier)
        ], previousRefreshToken: nil)
    }

    /// Exchanges the refresh token for new tokens. Store the result in place of the old token: the
    /// refresh token may be replaced. When MangaBaka does not return a new refresh token, the old
    /// one is kept.
    /// - Throws: ``MangaBakaOAuthError/noRefreshToken`` when the token has none, and
    ///   ``MangaBakaOAuthError/tokenRequestFailed(statusCode:error:description:)`` with
    ///   ``MangaBakaOAuthError/isInvalidGrant`` set when the session has ended.
    public func refresh(_ token: MangaBakaToken) async throws -> MangaBakaToken {
        guard let refreshToken = token.refreshToken else {
            throw MangaBakaOAuthError.noRefreshToken
        }
        return try await requestToken([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ], previousRefreshToken: refreshToken)
    }

    /// Revokes the token's refresh token, or its access token when it has none, ending the session
    /// on MangaBaka.
    public func revoke(_ token: MangaBakaToken) async throws {
        let (value, hint) = token.refreshToken.map { ($0, "refresh_token") } ?? (token.accessToken, "access_token")
        let (data, response) = try await post(Self.revokeURL, [
            URLQueryItem(name: "token", value: value),
            URLQueryItem(name: "token_type_hint", value: hint)
        ])
        try Self.checkStatus(data: data, response: response)
    }

    private func requestToken(_ grantItems: [URLQueryItem], previousRefreshToken: String?) async throws -> MangaBakaToken {
        let (data, response) = try await post(Self.tokenURL, grantItems)
        try Self.checkStatus(data: data, response: response)
        guard let body = try? JSONDecoder().decode(TokenResponse.self, from: data), !body.accessToken.isEmpty else {
            throw MangaBakaOAuthError.invalidTokenResponse
        }
        return MangaBakaToken(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken ?? previousRefreshToken,
            expiresAt: body.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) },
            scope: body.scope
        )
    }

    private func post(_ url: URL, _ items: [URLQueryItem]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncoded([URLQueryItem(name: "client_id", value: clientID)] + items).utf8)
        return try await send(request)
    }

    private static func checkStatus(data: Data, response: URLResponse) throws {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(statusCode) else { return }
        let body = try? JSONDecoder().decode(ErrorResponse.self, from: data)
        throw MangaBakaOAuthError.tokenRequestFailed(statusCode: statusCode, error: body?.error, description: body?.errorDescription)
    }

    /// `application/x-www-form-urlencoded`, escaping everything but RFC 3986 unreserved characters.
    internal static func formEncoded(_ items: [URLQueryItem]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return items.compactMap { item in
            guard let value = item.value,
                  let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed),
                  let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return nil
            }
            return "\(name)=\(encoded)"
        }
        .joined(separator: "&")
    }

    /// The S256 code challenge: base64url(SHA-256(verifier)) without padding.
    internal static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A random string of RFC 7636 code verifier characters, from the system's secure generator.
    internal static func randomString(length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    private static func endpoint(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("\(string) is not a valid URL.")
        }
        return url
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case scope
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }
}

/// An in-progress sign-in: the URL to open and the values needed to finish it.
public struct MangaBakaAuthorizationRequest: Hashable, Sendable {
    /// The MangaBaka sign-in URL.
    public let url: URL
    /// The PKCE code verifier, sent again when exchanging the code.
    public let codeVerifier: String
    /// The state the callback must echo.
    public let state: String
}

/// OAuth tokens for a signed-in user. `Codable` so apps can store it, for example in the Keychain.
///
/// Its descriptions and mirror never include the tokens.
public struct MangaBakaToken: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// The access token, sent as `Authorization: Bearer`.
    public let accessToken: String
    /// The refresh token, present when the `offline_access` scope was granted.
    public let refreshToken: String?
    /// When the access token stops working, if MangaBaka said.
    public let expiresAt: Date?
    /// The granted scopes, space separated.
    public let scope: String?

    /// Creates a token.
    public init(accessToken: String, refreshToken: String?, expiresAt: Date?, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// Whether the access token expires within `leeway` seconds of `date`. Tokens without an
    /// expiry never count as expired.
    public func isExpired(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return date.addingTimeInterval(leeway) >= expiresAt
    }

    /// A description without the tokens.
    public var description: String {
        "MangaBakaToken(expiresAt: \(expiresAt.map { "\($0)" } ?? "nil"), refreshable: \(refreshToken != nil))"
    }

    /// A description without the tokens.
    public var debugDescription: String { description }

    /// A mirror without the tokens.
    public var customMirror: Mirror {
        Mirror(self, children: ["expiresAt": expiresAt as Any, "refreshable": refreshToken != nil])
    }
}

/// A failure in the OAuth flow.
public enum MangaBakaOAuthError: Error, Sendable, Hashable {
    /// MangaBaka sent the browser back with an error, for example `access_denied`.
    case authorizationFailed(error: String, description: String?)
    /// The callback's state does not match the request.
    case stateMismatch
    /// The callback has no authorization code.
    case missingCode
    /// The token or revocation endpoint answered with an error.
    case tokenRequestFailed(statusCode: Int, error: String?, description: String?)
    /// The token endpoint's answer has no access token.
    case invalidTokenResponse
    /// The token cannot be refreshed because it has no refresh token.
    case noRefreshToken

    /// Whether MangaBaka rejected the code or refresh token, which means signing in again.
    public var isInvalidGrant: Bool {
        if case .tokenRequestFailed(_, "invalid_grant", _) = self {
            return true
        }
        return self == .noRefreshToken
    }
}
