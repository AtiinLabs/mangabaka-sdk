import Foundation
import MangaBakaSDK
import Testing

/// Read-only requests against the production API.
///
/// Run with `MANGABAKA_LIVE_TESTS=1 swift test --filter LiveSmokeTests`. Set `MANGABAKA_TOKEN` to a
/// Personal Access Token to also read the profile and the first library page. These tests never write.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MANGABAKA_LIVE_TESTS"] == "1"))
internal struct LiveSmokeTests {
    private let client: MangaBakaClient

    internal init() {
        let token = ProcessInfo.processInfo.environment["MANGABAKA_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
        client = MangaBakaClient(configuration: MangaBakaConfiguration(
            userAgent: "mangabaka-sdk-live-tests (https://github.com/AtiinLabs/mangabaka-sdk)",
            credentialProvider: token.map(MangaBakaCredential.personalAccessToken)
        ))
    }

    @Test
    internal func searchAndDetail() async throws {
        let page = try await client.searchSeries(SeriesSearchQuery(text: "Frieren", limit: 5))
        let first = try #require(page.items.first)
        #expect(page.totalCount >= page.items.count)

        let detail = try await client.series(id: first.id, detail: .full)
        #expect(detail.id == first.id)
        #expect(detail.title() != nil)
        #expect(detail.tags != nil)
    }

    @Test
    internal func sourceLookupFindsFrieren() async throws {
        let ids = try await client.seriesIDs(aniListID: 118_586)
        #expect(ids.contains(1995))
    }

    @Test(.enabled(if: !(ProcessInfo.processInfo.environment["MANGABAKA_TOKEN"] ?? "").isEmpty))
    internal func profileAndLibraryRead() async throws {
        let profile = try await client.profile()
        #expect(!profile.id.isEmpty)

        let page = try await client.library(LibraryQuery(limit: 1))
        #expect(page.items.count <= 1)
    }
}
