import Foundation

/// An error from ``MangaBakaClient``.
///
/// Task cancellation is reported as `CancellationError`, not as a `MangaBakaError`.
public enum MangaBakaError: Error, Sendable {
    /// 400: MangaBaka rejected the request. Inspect ``MangaBakaErrorResponse/code``.
    case badRequest(MangaBakaErrorResponse)
    /// 401: the credential is missing, invalid or expired.
    case unauthorized(MangaBakaErrorResponse)
    /// 403: the credential lacks a required scope or permission.
    case forbidden(MangaBakaErrorResponse)
    /// 404: the resource does not exist.
    case notFound(MangaBakaErrorResponse)
    /// 422: a field failed validation. Inspect ``MangaBakaErrorResponse/issues``.
    case unprocessableContent(MangaBakaErrorResponse)
    /// 429: too many requests. `retryAfter` is the server's requested wait in seconds.
    case rateLimited(MangaBakaErrorResponse, retryAfter: TimeInterval?)
    /// 5xx: MangaBaka failed to handle the request.
    case serverError(MangaBakaErrorResponse)
    /// Any other unsuccessful status.
    case unexpectedStatus(MangaBakaErrorResponse)
    /// A library or profile request was made without a credential provider.
    case missingCredentials
    /// The request was not sent because a parameter is out of range.
    case invalidRequest(String)
    /// The response could not be decoded.
    case invalidResponse(any Error)
    /// The request failed before a response arrived.
    case transport(any Error)

    /// The error response, for errors that carry one.
    public var response: MangaBakaErrorResponse? {
        switch self {
        case let .badRequest(response), let .unauthorized(response), let .forbidden(response),
             let .notFound(response), let .unprocessableContent(response), let .rateLimited(response, _),
             let .serverError(response), let .unexpectedStatus(response):
            return response

        case .missingCredentials, .invalidRequest, .invalidResponse, .transport:
            return nil
        }
    }

    internal init(response: MangaBakaErrorResponse, retryAfter: TimeInterval?) {
        switch response.statusCode {
        case 400: self = .badRequest(response)
        case 401: self = .unauthorized(response)
        case 403: self = .forbidden(response)
        case 404: self = .notFound(response)
        case 422: self = .unprocessableContent(response)
        case 429: self = .rateLimited(response, retryAfter: retryAfter)
        case 500...599: self = .serverError(response)
        default: self = .unexpectedStatus(response)
        }
    }
}

/// The body of an unsuccessful MangaBaka response.
public struct MangaBakaErrorResponse: Sendable, Hashable {
    /// The HTTP status code.
    public let statusCode: Int
    /// The server's message, if any.
    public let message: String?
    /// The rule that refused the request, if any.
    public let code: MangaBakaErrorCode?
    /// Field validation failures.
    public let issues: [Issue]

    /// A field validation failure.
    public struct Issue: Sendable, Hashable {
        /// The validation rule that failed.
        public let code: String
        /// A description of the failure.
        public let message: String
        /// The path to the failing field.
        public let path: [String]
    }

    /// Creates a response.
    public init(statusCode: Int, message: String? = nil, code: MangaBakaErrorCode? = nil, issues: [Issue] = []) {
        self.statusCode = statusCode
        self.message = message
        self.code = code
        self.issues = issues
    }

    /// Decodes a response body, keeping only the status when the body is not MangaBaka's error shape.
    internal init(statusCode: Int, body: Data) {
        let decoded = try? JSONDecoder().decode(Body.self, from: body)
        self.init(
            statusCode: statusCode,
            message: decoded?.message,
            code: decoded?.code.map(MangaBakaErrorCode.init(rawValue:)),
            issues: decoded?.issues?.map { issue in
                Issue(code: issue.code ?? "", message: issue.message ?? "", path: issue.path?.map(\.value) ?? [])
            } ?? []
        )
    }

    private struct Body: Decodable {
        let message: String?
        let code: String?
        let issues: [RawIssue]?
    }

    private struct RawIssue: Decodable {
        let code: String?
        let message: String?
        let path: [PathComponent]?
    }

    /// A path component, which is a key or an array index.
    private struct PathComponent: Decodable {
        let value: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let key = try? container.decode(String.self) {
                value = key
            } else {
                value = String(try container.decode(Int.self))
            }
        }
    }
}
