import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// A client for the MangaBaka API.
///
/// Catalog requests need no credential. Library and profile requests use the configuration's
/// ``MangaBakaConfiguration/credentialProvider``; the credential is never sent with catalog requests.
/// Cancelling the calling task cancels the request and any pending retry with `CancellationError`.
public struct MangaBakaClient: Sendable {
    /// The configuration the client was created with.
    public let configuration: MangaBakaConfiguration
    internal let api: Client

    /// Creates a client that sends requests through `URLSession`.
    ///
    /// The session's `URLCache` keeps catalog responses for as long as MangaBaka's `Cache-Control`
    /// header allows. MangaBaka marks library and profile responses `no-store`.
    public init(configuration: MangaBakaConfiguration, session: URLSession = .shared) {
        self.init(configuration: configuration, transport: URLSessionTransport(configuration: .init(session: session)))
    }

    /// Creates a client that sends requests through `transport`, for tests or another HTTP stack.
    public init(configuration: MangaBakaConfiguration, transport: any ClientTransport) {
        self.init(configuration: configuration, transport: transport) { seconds in
            // The retry middleware only passes finite, non-negative waits up to `maximumDelay`.
            try await Task.sleep(nanoseconds: UInt64(min(seconds, 86_400) * 1_000_000_000))
        }
    }

    internal init(
        configuration: MangaBakaConfiguration,
        transport: any ClientTransport,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.configuration = configuration
        var middlewares: [any ClientMiddleware] = [
            ErrorMiddleware(),
            RetryMiddleware(policy: configuration.retryPolicy, sleep: sleep),
            RequestHeadersMiddleware(userAgent: configuration.userAgent, credentialProvider: configuration.credentialProvider)
        ]
        if let logger = configuration.logger {
            middlewares.append(LoggingMiddleware(logger: logger))
        }
        api = Client(
            serverURL: configuration.baseURL,
            configuration: .init(dateTranscoder: MangaBakaDateTranscoder()),
            transport: transport,
            middlewares: middlewares
        )
    }

    // MARK: - Helpers

    internal func validate(page: Int, limit: Int, maximumLimit: Int) throws {
        guard page >= 1 else {
            throw MangaBakaError.invalidRequest("page must be at least 1.")
        }
        guard (1...maximumLimit).contains(limit) else {
            throw MangaBakaError.invalidRequest("limit must be between 1 and \(maximumLimit).")
        }
    }

    /// Runs a generated-client call and reports its errors as ``MangaBakaError`` or `CancellationError`.
    internal func call<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw Self.publicError(error)
        }
    }

    internal static func publicError(_ error: any Error) -> any Error {
        let clientError = error as? ClientError
        let underlying = clientError?.underlyingError ?? error
        switch underlying {
        case let error as MangaBakaError:
            return error

        case is CancellationError:
            return CancellationError()

        case let error as URLError where error.code == .cancelled:
            return CancellationError()

        default:
            // A `ClientError` without a response failed before the server answered. Anything else
            // is a response the generated client could not decode.
            if let clientError, clientError.response == nil {
                return MangaBakaError.transport(underlying)
            }
            return MangaBakaError.invalidResponse(underlying)
        }
    }
}

internal extension Array where Element: MangaBakaOpenValue {
    var rawValues: [String]? {
        isEmpty ? nil : map(\.rawValue)
    }
}

internal extension Array where Element == String {
    var nonEmpty: [String]? {
        isEmpty ? nil : self
    }
}

internal extension SeriesDetail {
    var schema: String? {
        switch self {
        case .standard:
            return nil

        case .full:
            return "full"
        }
    }
}
