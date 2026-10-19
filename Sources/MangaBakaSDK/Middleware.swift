import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Turns unsuccessful responses into ``MangaBakaError``.
internal struct ErrorMiddleware: ClientMiddleware {
    /// Error bodies are short JSON objects; anything larger is not read.
    private static let maximumBodySize = 64 * 1024

    internal func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard response.status.kind != .successful else {
            return (response, responseBody)
        }
        var data = Data()
        if let responseBody {
            data = (try? await Data(collecting: responseBody, upTo: Self.maximumBodySize)) ?? Data()
        }
        throw MangaBakaError(
            response: MangaBakaErrorResponse(statusCode: response.status.code, body: data),
            retryAfter: RetryAfter.seconds(from: response.headerFields, now: Date())
        )
    }
}

/// Retries failed `GET` requests according to a ``MangaBakaRetryPolicy``.
internal struct RetryMiddleware: ClientMiddleware {
    internal let policy: MangaBakaRetryPolicy
    internal let sleep: @Sendable (TimeInterval) async throws -> Void

    private static let retriedStatuses: Set<Int> = [429, 502, 503, 504]
    private static let retriedNetworkErrors: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost]

    internal func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard request.method == .get else {
            return try await next(request, body, baseURL)
        }
        var retry = 0
        while true {
            try Task.checkCancellation()
            let delay: TimeInterval
            do {
                let (response, responseBody) = try await next(request, body, baseURL)
                guard Self.retriedStatuses.contains(response.status.code), retry < policy.maximumRetries else {
                    return (response, responseBody)
                }
                let wait = RetryAfter.seconds(from: response.headerFields, now: Date()) ?? backoff(retry)
                guard wait <= policy.maximumDelay else {
                    return (response, responseBody)
                }
                delay = wait
            } catch {
                // The runtime wraps transport errors in `ClientError` before they reach middleware.
                let underlying = (error as? ClientError)?.underlyingError ?? error
                let wait = backoff(retry)
                guard let urlError = underlying as? URLError,
                      Self.retriedNetworkErrors.contains(urlError.code),
                      retry < policy.maximumRetries,
                      wait <= policy.maximumDelay else {
                    throw error
                }
                delay = wait
            }
            retry += 1
            try await sleep(delay)
        }
    }

    private func backoff(_ retry: Int) -> TimeInterval {
        policy.initialDelay * pow(2, Double(retry))
    }
}

/// Parses the `Retry-After` header.
internal enum RetryAfter {
    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    /// The wait in seconds, from either delta-seconds or an HTTP date. Past dates give zero.
    internal static func seconds(from fields: HTTPFields, now: Date) -> TimeInterval? {
        guard let value = fields[.retryAfter]?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if let seconds = Int(value), seconds >= 0 {
            return TimeInterval(seconds)
        }
        guard let date = httpDate.date(from: value) else {
            return nil
        }
        return max(0, date.timeIntervalSince(now))
    }
}

/// Adds the user agent to every request and the credential to library and profile requests.
///
/// Catalog requests never carry a credential, so they stay cacheable and tokens are not sent
/// where they are not needed.
internal struct RequestHeadersMiddleware: ClientMiddleware {
    internal let userAgent: String
    internal let credentialProvider: (any MangaBakaCredentialProvider)?

    private static let apiKey = HTTPField.Name("x-api-key")

    /// Whether a request reads or writes the signed-in user's data: its path is `/v{n}/my/…`.
    internal static func requiresCredential(path: String?) -> Bool {
        let components = (path ?? "").split(separator: "/", maxSplits: 2)
        return components.count >= 2 && components[1] == "my"
    }

    internal func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.userAgent] = userAgent
        if Self.requiresCredential(path: request.path) {
            guard let credentialProvider else {
                throw MangaBakaError.missingCredentials
            }
            switch try await credentialProvider.credential() {
            case let .personalAccessToken(token):
                guard let apiKey = Self.apiKey else {
                    preconditionFailure("x-api-key is a valid header name.")
                }
                request.headerFields[apiKey] = token

            case let .oauthAccessToken(token):
                request.headerFields[.authorization] = "Bearer \(token)"
            }
        }
        return try await next(request, body, baseURL)
    }
}

/// Reports one ``MangaBakaRequestEvent`` per attempt.
internal struct LoggingMiddleware: ClientMiddleware {
    internal let logger: any MangaBakaLogger

    internal func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let start = DispatchTime.now().uptimeNanoseconds
        var statusCode: Int?
        defer {
            let path = request.path.map { String($0.prefix { $0 != "?" }) } ?? ""
            logger.log(MangaBakaRequestEvent(
                operationID: operationID,
                method: request.method.rawValue,
                path: path,
                statusCode: statusCode,
                duration: TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            ))
        }
        let (response, responseBody) = try await next(request, body, baseURL)
        statusCode = response.status.code
        return (response, responseBody)
    }
}

/// Decodes the ISO 8601 forms MangaBaka returns, with or without fractional seconds.
internal struct MangaBakaDateTranscoder: DateTranscoder {
    private let plain = ISO8601DateTranscoder()
    private let fractional = ISO8601DateTranscoder(options: [.withInternetDateTime, .withFractionalSeconds])
    private let day = ISO8601DateTranscoder(options: [.withFullDate])

    internal func encode(_ date: Date) throws -> String {
        try plain.encode(date)
    }

    internal func decode(_ string: String) throws -> Date {
        if let date = try? fractional.decode(string) {
            return date
        }
        if let date = try? plain.decode(string) {
            return date
        }
        return try day.decode(string)
    }
}
