import Foundation
@testable import MangaBakaSDK
import Testing

internal struct LibraryTests {
    private let token = MangaBakaCredential.personalAccessToken("mb-secret")

    @Test
    internal func catalogRequestsNeverCarryTheCredential() async throws {
        let transport = MockTransport([
            .json(Fixture.searchPage(ids: [1], page: 1, limit: 20, count: 1)),
            .json(["status": 200, "data": ["source_response": NSNull(), "series": [["id": 1995, "state": "active"]]]])
        ])
        let client = makeClient(transport, credential: token)

        _ = try await client.searchSeries(SeriesSearchQuery(text: "x"))
        // The operation ID contains `_my_` but the route is public.
        _ = try await client.seriesIDs(myAnimeListID: 1)

        #expect(transport.requests.count == 2)
        for request in transport.requests {
            #expect(request.header("x-api-key") == nil)
            #expect(request.header("Authorization") == nil)
            #expect(request.header("User-Agent") == "MangaBakaSDKTests/1.0")
        }
    }

    @Test
    internal func personalAccessTokenIsSentAsAPIKey() async throws {
        let transport = MockTransport([.json(["status": 200, "data": Fixture.libraryEntry(seriesID: 42)])])
        let client = makeClient(transport, credential: token)

        _ = try await client.libraryEntry(seriesID: 42)

        let request = try #require(transport.requests.first)
        #expect(request.header("x-api-key") == "mb-secret")
        #expect(request.header("Authorization") == nil)
    }

    @Test
    internal func oauthTokenIsSentAsBearerAndFetchedPerRequest() async throws {
        let provider = RotatingProvider()
        let transport = MockTransport([
            .json(["status": 200, "data": Fixture.libraryEntry(seriesID: 1)]),
            .json(["status": 200, "data": Fixture.libraryEntry(seriesID: 1)])
        ])
        let client = makeClient(transport, credential: provider)

        _ = try await client.libraryEntry(seriesID: 1)
        _ = try await client.libraryEntry(seriesID: 1)

        #expect(transport.requests.map { $0.header("Authorization") } == ["Bearer token-1", "Bearer token-2"])
        #expect(transport.requests.allSatisfy { $0.header("x-api-key") == nil })
    }

    @Test
    internal func libraryRequestWithoutCredentialIsNotSent() async {
        let transport = MockTransport([])
        let client = makeClient(transport)

        let thrown = await error { try await client.profile() }

        guard case .missingCredentials? = thrown as? MangaBakaError else {
            Issue.record("Expected missingCredentials, got \(String(describing: thrown))")
            return
        }
        #expect(transport.requests.isEmpty)
    }

    @Test
    internal func getEntryMapsFieldsAndDays() async throws {
        let transport = MockTransport([.json(["status": 200, "data": Fixture.libraryEntry(seriesID: 42)])])
        let client = makeClient(transport, credential: token)

        let entry = try #require(try await client.libraryEntry(seriesID: 42))

        #expect(transport.requests.first?.pathWithoutQuery == "/v1/my/library/42")
        #expect(entry.seriesID == 42)
        #expect(entry.state == .reading)
        #expect(entry.progressChapter == 12.5)
        #expect(entry.rating == 80)
        #expect(entry.priority == 20)
        #expect(entry.startDate == LibraryDate(year: 2024, month: 1, day: 2))
        #expect(entry.finishDate == nil)
        #expect(entry.numberOfRereads == nil)
    }

    @Test
    internal func missingEntryIsNil() async throws {
        let client = makeClient(
            MockTransport([.json(Fixture.error(status: 404, message: "NOT_FOUND"), status: 404)]),
            credential: token
        )

        #expect(try await client.libraryEntry(seriesID: 42) == nil)
    }

    @Test
    internal func createSendsOnlyTheGivenFields() async throws {
        let transport = MockTransport([.json(["status": 201, "data": true], status: 201)])
        let client = makeClient(transport, credential: token)

        try await client.createLibraryEntry(
            seriesID: 42,
            LibraryEntryChanges(state: .planToRead, progressChapter: 3, startDate: LibraryDate(year: 2024, month: 1, day: 2))
        )

        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.pathWithoutQuery == "/v1/my/library/42")
        let body = try #require(try request.jsonBody() as? [String: Any])
        #expect(Set(body.keys) == ["state", "progress_chapter", "start_date"])
        #expect(body["state"] as? String == "plan_to_read")
        #expect(body["progress_chapter"] as? Double == 3)
        #expect(body["start_date"] as? String == "2024-01-02T00:00:00Z")
    }

    @Test
    internal func updatePatchesAndDeleteDeletes() async throws {
        let transport = MockTransport([
            .json(["status": 200, "data": true]),
            .json(["status": 200, "data": true])
        ])
        let client = makeClient(transport, credential: token)

        try await client.updateLibraryEntry(seriesID: 42, LibraryEntryChanges(progressChapter: 13, isPrivate: true))
        try await client.deleteLibraryEntry(seriesID: 42)

        #expect(transport.requests.map(\.method) == [.patch, .delete])
        #expect(transport.requests.map(\.pathWithoutQuery) == ["/v1/my/library/42", "/v1/my/library/42"])
        let body = try #require(try transport.requests[0].jsonBody() as? [String: Any])
        #expect(Set(body.keys) == ["progress_chapter", "is_private"])
        #expect(transport.requests[1].body?.isEmpty ?? true)
    }

    @Test
    internal func writesSucceedOnAny2xxWhateverTheBody() async throws {
        let transport = MockTransport([
            .response(status: 200, body: #"{"ok":1}"#),
            .response(status: 204, body: ""),
            .response(status: 202, body: "not json")
        ])
        let client = makeClient(transport, credential: token)

        try await client.createLibraryEntry(seriesID: 1, LibraryEntryChanges(state: .reading))
        try await client.deleteLibraryEntry(seriesID: 1)
        try await client.updateLibraryEntry(seriesID: 1, LibraryEntryChanges(progressChapter: 2))

        #expect(transport.requests.count == 3)
    }

    @Test
    internal func libraryDatesRejectDaysThatDoNotExist() {
        #expect(LibraryDate(year: 2024, month: 2, day: 29)?.description == "2024-02-29")
        #expect(LibraryDate(year: 2023, month: 2, day: 29) == nil)
        #expect(LibraryDate(year: 2024, month: 2, day: 30) == nil)
        #expect(LibraryDate(year: 2024, month: 13, day: 1) == nil)
        #expect(LibraryDate(year: 2024, month: 4, day: 0) == nil)
        #expect(LibraryDate(year: 0, month: 1, day: 1) == nil)
    }

    @Test
    internal func libraryListIncludesSeriesAndLists() async throws {
        let item: [String: Any] = [
            "entry": Fixture.libraryEntry(seriesID: 1995),
            "lists": [["id": 3, "name": "Favorites", "is_private": false]],
            "series": Fixture.series(id: 1995)
        ]
        let response: [String: Any] = [
            "status": 200,
            "pagination": ["count": 1, "page": 1, "limit": 50, "next": NSNull(), "previous": NSNull()],
            "data": [item]
        ]
        let transport = MockTransport([.json(response)])
        let client = makeClient(transport, credential: token)
        let since = Date(timeIntervalSince1970: 1_782_864_000)

        let page = try await client.library(LibraryQuery(states: [.reading, .rereading], updatedAfter: since, sort: .recentlyUpdated))

        let request = try #require(transport.requests.first)
        #expect(request.pathWithoutQuery == "/v2/my/library")
        #expect(request.query("state") == ["reading", "rereading"])
        #expect(request.query("updated_after") == ["2026-07-01T00:00:00Z"])
        #expect(request.query("sort_by") == ["updated_at_desc"])
        #expect(page.items.first?.entry.seriesID == 1995)
        #expect(page.items.first?.series.title() == "Frieren: Beyond Journey's End")
        #expect(page.items.first?.lists == [LibraryList(id: 3, name: "Favorites", isPrivate: false)])
        #expect(!page.hasNextPage)
    }

    @Test
    internal func batchSendsEveryEntryAndReportsActions() async throws {
        let response: [String: Any] = [
            "status": 200,
            "data": [["series_id": 1, "action": "created"], ["series_id": 2, "action": "skipped"]]
        ]
        let transport = MockTransport([.json(response)])
        let client = makeClient(transport, credential: token)

        let results = try await client.upsertLibraryEntries(
            [
                LibraryBatchItem(seriesID: 1, changes: LibraryEntryChanges(state: .reading)),
                LibraryBatchItem(seriesID: 2, changes: LibraryEntryChanges(rating: 90))
            ],
            insertOnly: true
        )

        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.pathWithoutQuery == "/v1/my/library/batch")
        #expect(request.query("insert_only") == ["true"])
        let body = try #require(try request.jsonBody() as? [[String: Any]])
        #expect(body.map { $0["series_id"] as? Int } == [1, 2])
        #expect(body.map { Set($0.keys) } == [["series_id", "state"], ["series_id", "rating"]])
        #expect(results == [
            LibraryBatchResult(seriesID: 1, action: .created),
            LibraryBatchResult(seriesID: 2, action: .skipped)
        ])
    }

    @Test
    internal func emptyOrOversizedBatchIsNotSent() async {
        let transport = MockTransport([])
        let client = makeClient(transport, credential: token)
        let tooMany = (1...101).map { LibraryBatchItem(seriesID: $0, changes: LibraryEntryChanges(state: .reading)) }

        let empty = await error { try await client.upsertLibraryEntries([]) }
        let oversized = await error { try await client.upsertLibraryEntries(tooMany) }

        for thrown in [empty, oversized] {
            guard case .invalidRequest? = thrown as? MangaBakaError else {
                Issue.record("Expected invalidRequest, got \(String(describing: thrown))")
                return
            }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test
    internal func profileMapsTheSignedInUser() async throws {
        let user: [String: Any] = [
            "id": "user-1", "nickname": "Bao", "preferred_username": "bao", "picture": NSNull(), "role": "user",
            "auth_type": "pat", "scopes": ["library.read"], "rating_steps": 10, "library_default_state": "plan_to_read"
        ]
        let transport = MockTransport([.json(["status": 200, "data": user])])
        let client = makeClient(transport, credential: token)

        let profile = try await client.profile()

        #expect(profile.preferredUsername == "bao")
        #expect(profile.authenticationType == "pat")
        #expect(profile.scopes == ["library.read"])
        #expect(profile.libraryDefaultState == .planToRead)
    }
}

/// Returns a new OAuth token each time, as a refreshing provider would.
internal actor RotatingProvider: MangaBakaCredentialProvider {
    private var count = 0

    internal func credential() -> MangaBakaCredential {
        count += 1
        return .oauthAccessToken("token-\(count)")
    }
}
