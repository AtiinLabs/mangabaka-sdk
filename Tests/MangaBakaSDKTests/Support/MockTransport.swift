import Foundation
import HTTPTypes
@testable import MangaBakaSDK
import OpenAPIRuntime

/// A request the mock transport received.
internal struct RecordedRequest: Sendable {
    internal let operationID: String
    internal let method: HTTPRequest.Method
    internal let path: String
    internal let headers: HTTPFields
    internal let body: Data?

    internal var pathWithoutQuery: String {
        String(path.prefix { $0 != "?" })
    }

    /// Every value sent for a query parameter, in order.
    internal func query(_ name: String) -> [String] {
        let items = URLComponents(string: "https://example.invalid\(path)")?.queryItems ?? []
        return items.filter { $0.name == name }.compactMap(\.value)
    }

    internal func header(_ name: String) -> String? {
        HTTPField.Name(name).flatMap { headers[$0] }
    }

    internal func jsonBody() throws -> Any {
        try JSONSerialization.jsonObject(with: body ?? Data())
    }
}

/// A canned transport result.
internal enum Stub: Sendable {
    case response(status: Int, headers: [String: String] = [:], body: String)
    case failure(URLError)

    internal static func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> Self {
        .response(status: status, headers: headers, body: Fixture.encode(object))
    }
}

/// A transport that records requests and returns stubs in order.
internal final class MockTransport: ClientTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [Stub]
    private var recorded: [RecordedRequest] = []

    internal init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    internal var requests: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    internal func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var data: Data?
        if let body {
            data = try await Data(collecting: body, upTo: 1 << 20)
        }
        let stub = next(RecordedRequest(
            operationID: operationID,
            method: request.method,
            path: request.path ?? "",
            headers: request.headerFields,
            body: data
        ))
        switch stub {
        case let .response(status, headers, body):
            var fields = HTTPFields()
            fields[.contentType] = "application/json"
            for (name, value) in headers {
                if let name = HTTPField.Name(name) {
                    fields[name] = value
                }
            }
            return (HTTPResponse(status: .init(code: status), headerFields: fields), HTTPBody(body))

        case let .failure(error):
            throw error
        }
    }

    private func next(_ request: RecordedRequest) -> Stub {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard !stubs.isEmpty else {
            return .response(status: 599, body: #"{"message":"No stub left"}"#)
        }
        return stubs.removeFirst()
    }
}

/// Records the waits the retry middleware asks for, without waiting.
internal actor SleepRecorder {
    internal private(set) var delays: [TimeInterval] = []

    internal func record(_ delay: TimeInterval) {
        delays.append(delay)
    }
}

/// Collects log events.
internal final class LogRecorder: MangaBakaLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [MangaBakaRequestEvent] = []

    internal var events: [MangaBakaRequestEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    internal func log(_ event: MangaBakaRequestEvent) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(event)
    }
}

internal func makeClient(
    _ transport: MockTransport,
    credential: (any MangaBakaCredentialProvider)? = nil,
    retryPolicy: MangaBakaRetryPolicy = .default,
    logger: (any MangaBakaLogger)? = nil,
    sleeps: SleepRecorder = SleepRecorder()
) -> MangaBakaClient {
    MangaBakaClient(
        configuration: MangaBakaConfiguration(
            userAgent: "MangaBakaSDKTests/1.0",
            credentialProvider: credential,
            retryPolicy: retryPolicy,
            logger: logger
        ),
        transport: transport
    ) { delay in
        await sleeps.record(delay)
    }
}

/// Runs `body` and returns the error it throws, or `nil`.
internal func error<T>(from body: () async throws -> T) async -> (any Error)? {
    do {
        _ = try await body()
        return nil
    } catch {
        return error
    }
}
