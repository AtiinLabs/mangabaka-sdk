import Foundation
@testable import MangaBakaSDK
import Testing

internal struct ErrorTests {
    @Test(arguments: [400, 401, 403, 404, 422, 429, 500, 503, 418])
    internal func statusesMapToTypedErrors(status: Int) async {
        let body = Fixture.error(status: status, message: "Refused", code: "duplicate_entry")
        let client = makeClient(MockTransport([.json(body, status: status)]), retryPolicy: .none)

        let thrown = await error { try await client.series(id: 1) } as? MangaBakaError

        let response: MangaBakaErrorResponse?
        switch (status, thrown) {
        case let (400, .badRequest(value)?), let (401, .unauthorized(value)?), let (403, .forbidden(value)?),
             let (404, .notFound(value)?), let (422, .unprocessableContent(value)?), let (429, .rateLimited(value)?),
             let (500, .serverError(value)?), let (503, .serverError(value)?), let (418, .unexpectedStatus(value)?):
            response = value

        default:
            response = nil
        }
        #expect(response == MangaBakaErrorResponse(statusCode: status, message: "Refused", code: .duplicateEntry))
    }

    @Test
    internal func validationIssuesAreDecoded() async {
        let body: [String: Any] = [
            "status": 422,
            "message": "Invalid body",
            "issues": [["code": "too_big", "keys": [], "path": ["entries", 3, "rating"], "message": "Must be at most 100"]]
        ]
        let client = makeClient(MockTransport([.json(body, status: 422)]), credential: MangaBakaCredential.personalAccessToken("mb-x"))

        let thrown = await error { try await client.updateLibraryEntry(seriesID: 1, LibraryEntryChanges(rating: 101)) }

        guard case let .unprocessableContent(response)? = thrown as? MangaBakaError else {
            Issue.record("Expected unprocessableContent, got \(String(describing: thrown))")
            return
        }
        #expect(response.issues == [.init(code: "too_big", message: "Must be at most 100", path: ["entries", "3", "rating"])])
    }

    @Test
    internal func nonJSONErrorBodyKeepsTheStatus() async {
        let client = makeClient(MockTransport([.response(status: 502, body: "<html>Bad gateway</html>")]), retryPolicy: .none)

        let thrown = await error { try await client.series(id: 1) }

        guard case let .serverError(response)? = thrown as? MangaBakaError else {
            Issue.record("Expected serverError, got \(String(describing: thrown))")
            return
        }
        #expect(response == MangaBakaErrorResponse(statusCode: 502))
    }

    @Test
    internal func serverErrorsKeepRetryAfter() async {
        // 120 seconds is beyond the default 30-second limit, so the client returns the 503 at once.
        let transport = MockTransport([.response(status: 503, headers: ["Retry-After": "120"], body: "{}")])
        let client = makeClient(transport)

        let thrown = await error { try await client.series(id: 1) }

        #expect((thrown as? MangaBakaError)?.response?.retryAfter == 120)
        #expect(transport.requests.count == 1)
    }

    @Test
    internal func failingCredentialProviderIsReportedAndNothingIsSent() async {
        let transport = MockTransport([])
        let client = makeClient(transport, credential: FailingProvider())

        let thrown = await error { try await client.libraryEntry(seriesID: 1) }

        guard case let .credentialUnavailable(underlying)? = thrown as? MangaBakaError else {
            Issue.record("Expected credentialUnavailable, got \(String(describing: thrown))")
            return
        }
        #expect(underlying is SignedOut)
        #expect(transport.requests.isEmpty)
    }

    @Test
    internal func failuresWithoutAResponseAreTransportErrors() async {
        let client = makeClient(MockTransport([.failure(SignedOut())]), credential: MangaBakaCredential.personalAccessToken("mb-x"))

        let thrown = await error { try await client.deleteLibraryEntry(seriesID: 1) }

        guard case let .transport(underlying)? = thrown as? MangaBakaError else {
            Issue.record("Expected transport, got \(String(describing: thrown))")
            return
        }
        #expect(underlying is SignedOut)
    }

    @Test
    internal func credentialDescriptionsHideTheToken() {
        let credentials = [MangaBakaCredential.personalAccessToken("mb-secret"), .oauthAccessToken("mb-secret")]
        for credential in credentials {
            var dumped = ""
            dump(credential, to: &dumped)
            let configuration = MangaBakaConfiguration(userAgent: "x", credentialProvider: credential)
            for text in ["\(credential)", String(reflecting: credential), dumped, "\(configuration)"] {
                #expect(!text.contains("mb-secret"), "\(text)")
            }
        }
    }
}

internal struct SignedOut: Error {}

internal struct FailingProvider: MangaBakaCredentialProvider {
    internal func credential() throws -> MangaBakaCredential {
        throw SignedOut()
    }
}

internal struct RetryTests {
    @Test
    internal func readsRetryWithBackoffUntilSuccess() async throws {
        let transport = MockTransport([
            .response(status: 503, body: "{}"),
            .failure(URLError(.timedOut)),
            .json(["status": 200, "data": Fixture.series(id: 1)])
        ])
        let sleeps = SleepRecorder()
        let client = makeClient(transport, sleeps: sleeps)

        let series = try await client.series(id: 1)

        #expect(series.id == 1)
        #expect(transport.requests.count == 3)
        #expect(await sleeps.delays == [1, 2])
    }

    @Test
    internal func retryAfterSecondsAndDatesAreHonored() async throws {
        let date = Date().addingTimeInterval(3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let transport = MockTransport([
            .json(Fixture.error(status: 429, message: "Slow down"), status: 429, headers: ["Retry-After": "7"]),
            .json(Fixture.error(status: 429, message: "Slow down"), status: 429, headers: ["Retry-After": formatter.string(from: date)])
        ])
        let sleeps = SleepRecorder()
        let client = makeClient(transport, sleeps: sleeps)

        let thrown = await error { try await client.series(id: 1) }

        // The second wait is about an hour, beyond the 30-second limit, so the 429 is returned.
        guard case let .rateLimited(response)? = thrown as? MangaBakaError else {
            Issue.record("Expected rateLimited, got \(String(describing: thrown))")
            return
        }
        #expect(transport.requests.count == 2)
        #expect(await sleeps.delays == [7])
        #expect((3500...3600).contains(response.retryAfter ?? 0))
    }

    @Test
    internal func unusablePolicyValuesDisableRetriesInsteadOfCrashing() async {
        let transport = MockTransport([.response(status: 503, body: "{}"), .response(status: 503, body: "{}")])
        let sleeps = SleepRecorder()
        let policy = MangaBakaRetryPolicy(maximumRetries: 3, initialDelay: -.infinity, maximumDelay: .nan)
        let client = makeClient(transport, retryPolicy: policy, sleeps: sleeps)

        _ = await error { try await client.series(id: 1) }

        #expect(transport.requests.count == 1)
        #expect(await sleeps.delays.isEmpty)
    }

    @Test
    internal func retriesStopAtTheLimit() async {
        let transport = MockTransport(Array(repeating: .response(status: 504, body: "{}"), count: 5))
        let sleeps = SleepRecorder()
        let client = makeClient(transport, retryPolicy: MangaBakaRetryPolicy(maximumRetries: 2, initialDelay: 0.5, maximumDelay: 10), sleeps: sleeps)

        let thrown = await error { try await client.series(id: 1) }

        guard case .serverError? = thrown as? MangaBakaError else {
            Issue.record("Expected serverError, got \(String(describing: thrown))")
            return
        }
        #expect(transport.requests.count == 3)
        #expect(await sleeps.delays == [0.5, 1])
    }

    @Test
    internal func writesAreNeverRetried() async {
        let transport = MockTransport([
            .response(status: 503, body: "{}"),
            .failure(URLError(.timedOut)),
            .response(status: 429, headers: ["Retry-After": "1"], body: "{}")
        ])
        let client = makeClient(transport, credential: MangaBakaCredential.personalAccessToken("mb-x"))
        let changes = LibraryEntryChanges(progressChapter: 5)

        _ = await error { try await client.updateLibraryEntry(seriesID: 1, changes) }
        let timeout = await error { try await client.createLibraryEntry(seriesID: 1, changes) }
        _ = await error { try await client.deleteLibraryEntry(seriesID: 1) }

        #expect(transport.requests.map(\.method) == [.patch, .post, .delete])
        guard case .transport? = timeout as? MangaBakaError else {
            Issue.record("Expected transport, got \(String(describing: timeout))")
            return
        }
    }

    @Test
    internal func clientErrorsAreNotRetried() async {
        let transport = MockTransport([.json(Fixture.error(status: 404, message: "NOT_FOUND"), status: 404)])
        let client = makeClient(transport)

        _ = await error { try await client.series(id: 1) }

        #expect(transport.requests.count == 1)
    }
}

internal struct CancellationTests {
    @Test
    internal func cancellingDuringARetryWaitStopsWithoutAnotherRequest() async {
        let transport = MockTransport([
            .response(status: 503, headers: ["Retry-After": "20"], body: "{}"),
            .json(["status": 200, "data": Fixture.series(id: 1)])
        ])
        let (waiting, signal) = AsyncStream<Void>.makeStream()
        let client = MangaBakaClient(
            configuration: MangaBakaConfiguration(userAgent: "MangaBakaSDKTests/1.0"),
            transport: transport
        ) { delay in
            signal.yield()
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        let task = Task { try await client.series(id: 1) }
        var iterator = waiting.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let result = await task.result

        guard case let .failure(thrown) = result, thrown is CancellationError else {
            Issue.record("Expected CancellationError, got \(result)")
            return
        }
        #expect(transport.requests.count == 1)
    }

    @Test
    internal func cancelledTaskSendsNothing() async {
        let transport = MockTransport([.json(["status": 200, "data": Fixture.series(id: 1)])])
        let client = makeClient(transport)

        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.series(id: 1)
        }.result

        guard case let .failure(thrown) = result, thrown is CancellationError else {
            Issue.record("Expected CancellationError, got \(result)")
            return
        }
        #expect(transport.requests.isEmpty)
    }

    @Test
    internal func cancelledURLSessionRequestIsACancellationError() async {
        let client = makeClient(MockTransport([.failure(URLError(.cancelled))]))

        let thrown = await error { try await client.series(id: 1) }

        #expect(thrown is CancellationError)
    }
}

internal struct LoggingTests {
    @Test
    internal func eventsAreRedacted() async throws {
        let logger = LogRecorder()
        let transport = MockTransport([
            .response(status: 503, body: "{}"),
            .json(Fixture.searchPage(ids: [1], page: 1, limit: 20, count: 1)),
            .json(["status": 200, "data": Fixture.libraryEntry(seriesID: 42)])
        ])
        let client = makeClient(transport, credential: MangaBakaCredential.personalAccessToken("mb-secret"), logger: logger)

        _ = try await client.searchSeries(SeriesSearchQuery(text: "private search"))
        _ = try await client.libraryEntry(seriesID: 42)

        // One event per attempt, including the retried one.
        let events = logger.events
        #expect(events.map(\.statusCode) == [503, 200, 200])
        #expect(events.map(\.path) == ["/v2/series/search", "/v2/series/search", "/v1/my/library/{id}"])
        #expect(events.map(\.operationID) == ["get_series_search_v2", "get_series_search_v2", "get_my_library_series_id_v1"])
        let text = events.map { "\($0)" }.joined()
        #expect(!text.contains("mb-secret"))
        #expect(!text.contains("private"))
    }
}
