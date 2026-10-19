import Foundation

/// Settings for ``MangaBakaClient``.
public struct MangaBakaConfiguration: Sendable {
    /// The production API, `https://api.mangabaka.org`.
    public static let defaultBaseURL: URL = {
        guard let url = URL(string: "https://api.mangabaka.org") else {
            preconditionFailure("The default MangaBaka base URL is invalid.")
        }
        return url
    }()

    /// The API base URL.
    public var baseURL: URL
    /// The `User-Agent` sent with every request. Identify your app and a contact.
    public var userAgent: String
    /// Supplies the credential for library and profile requests. `nil` allows catalog requests only.
    public var credentialProvider: (any MangaBakaCredentialProvider)?
    /// When to retry failed reads.
    public var retryPolicy: MangaBakaRetryPolicy
    /// Receives one redacted event per HTTP attempt.
    public var logger: (any MangaBakaLogger)?

    /// Creates a configuration.
    /// - Parameters:
    ///   - userAgent: Identifies your app, for example `MyApp/1.0 (https://example.com)`.
    ///   - baseURL: The API base URL.
    ///   - credentialProvider: Supplies the credential for library and profile requests.
    ///   - retryPolicy: When to retry failed reads.
    ///   - logger: Receives one redacted event per HTTP attempt.
    public init(
        userAgent: String,
        baseURL: URL = defaultBaseURL,
        credentialProvider: (any MangaBakaCredentialProvider)? = nil,
        retryPolicy: MangaBakaRetryPolicy = .default,
        logger: (any MangaBakaLogger)? = nil
    ) {
        self.userAgent = userAgent
        self.baseURL = baseURL
        self.credentialProvider = credentialProvider
        self.retryPolicy = retryPolicy
        self.logger = logger
    }
}

/// A credential for library and profile requests.
///
/// Its descriptions and mirror never include the token.
public enum MangaBakaCredential: Sendable, Hashable, MangaBakaCredentialProvider, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// A Personal Access Token (`mb-…`), sent in the `x-api-key` header.
    case personalAccessToken(String)
    /// An OAuth 2 access token, sent as `Authorization: Bearer`.
    case oauthAccessToken(String)

    /// Returns this credential.
    public func credential() async throws -> MangaBakaCredential { self }

    /// The kind of credential, without the token.
    public var description: String {
        switch self {
        case .personalAccessToken:
            return "personalAccessToken(<redacted>)"

        case .oauthAccessToken:
            return "oauthAccessToken(<redacted>)"
        }
    }

    /// The kind of credential, without the token.
    public var debugDescription: String { description }

    /// A mirror without the token.
    public var customMirror: Mirror {
        Mirror(self, children: ["kind": description], displayStyle: .enum)
    }
}

/// Supplies the credential for each library or profile request.
///
/// The client asks for a credential before every attempt, so a provider can refresh an expired
/// OAuth token. Throw to fail the request without sending it; the client then throws
/// ``MangaBakaError/credentialUnavailable(_:)``.
public protocol MangaBakaCredentialProvider: Sendable {
    /// Returns the credential to send.
    func credential() async throws -> MangaBakaCredential
}

/// When the client retries a failed request.
///
/// Only `GET` requests are retried: library writes are never repeated automatically. A request is
/// retried after a 429, 502, 503 or 504 response, or after a timeout or dropped connection. The
/// wait is the server's `Retry-After` when present, otherwise exponential backoff. A request is
/// not retried when the wait would exceed ``maximumDelay``; the last error is thrown instead.
public struct MangaBakaRetryPolicy: Sendable, Hashable {
    /// The number of retries after the first attempt.
    public var maximumRetries: Int
    /// The first backoff wait in seconds, doubled for each further retry.
    public var initialDelay: TimeInterval
    /// The longest wait in seconds the client accepts before a retry.
    public var maximumDelay: TimeInterval

    /// Creates a retry policy.
    public init(maximumRetries: Int, initialDelay: TimeInterval, maximumDelay: TimeInterval) {
        self.maximumRetries = maximumRetries
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
    }

    /// Two retries, starting at one second, waiting at most 30 seconds.
    public static let `default` = Self(maximumRetries: 2, initialDelay: 1, maximumDelay: 30)
    /// No retries.
    public static let none = Self(maximumRetries: 0, initialDelay: 0, maximumDelay: 0)
}

/// Receives request events.
public protocol MangaBakaLogger: Sendable {
    /// Called once per HTTP attempt, after it completes or fails.
    func log(_ event: MangaBakaRequestEvent)
}

/// A redacted record of one HTTP attempt.
///
/// Events never contain query strings, headers, credentials or bodies.
public struct MangaBakaRequestEvent: Sendable, Hashable {
    /// The OpenAPI operation ID, for example `get_series_search_v2`.
    public let operationID: String
    /// The HTTP method.
    public let method: String
    /// The request path without its query string. In library paths, series IDs are replaced
    /// with `{id}`.
    public let path: String
    /// The response status, or `nil` when no response arrived.
    public let statusCode: Int?
    /// The attempt duration in seconds.
    public let duration: TimeInterval
}
