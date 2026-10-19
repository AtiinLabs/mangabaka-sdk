import Foundation
@testable import MangaBakaSDK
import Testing

internal struct CatalogTests {
    @Test
    internal func searchSendsFiltersAndPagesThroughResults() async throws {
        let transport = MockTransport([
            .json(Fixture.searchPage(ids: [1, 2], page: 1, limit: 2, count: 3)),
            .json(Fixture.searchPage(ids: [3], page: 2, limit: 2, count: 3))
        ])
        let client = makeClient(transport)
        var query = SeriesSearchQuery(
            text: "frieren",
            types: [.manga, .manhwa],
            statuses: [.releasing],
            tags: ["Cooking"],
            tagMatching: .any,
            licensed: .excluded,
            sort: .popularity,
            limit: 2
        )

        let first = try await client.searchSeries(query)
        query.page = 2
        let second = try await client.searchSeries(query)

        #expect(first.items.map(\.id) == [1, 2])
        #expect(first.totalCount == 3)
        #expect(first.hasNextPage)
        #expect(second.items.map(\.id) == [3])
        #expect(second.page == 2)
        #expect(!second.hasNextPage)

        let request = try #require(transport.requests.first)
        #expect(request.method == .get)
        #expect(request.pathWithoutQuery == "/v2/series/search")
        #expect(request.query("q") == ["frieren"])
        #expect(request.query("type") == ["manga", "manhwa"])
        #expect(request.query("status") == ["releasing"])
        #expect(request.query("tag") == ["Cooking"])
        #expect(request.query("tag_mode") == ["or"])
        #expect(request.query("is_licensed") == ["false"])
        #expect(request.query("has_anime").isEmpty)
        #expect(request.query("sort_by") == ["popularity_desc"])
        #expect(request.query("limit") == ["2"])
        #expect(request.query("schema").isEmpty)
        #expect(transport.requests[1].query("page") == ["2"])
    }

    @Test
    internal func searchMapsSeriesFields() async throws {
        let client = makeClient(MockTransport([.json(Fixture.searchPage(ids: [1995], page: 1, limit: 20, count: 1))]))

        let series = try #require(try await client.searchSeries(SeriesSearchQuery(text: "frieren")).items.first)

        #expect(series.id == 1995)
        #expect(series.state == .active)
        #expect(series.type == .manga)
        #expect(series.status == .releasing)
        #expect(series.contentRating == .safe)
        #expect(series.title() == "Frieren: Beyond Journey's End")
        #expect(series.title(preferring: ["ja"]) == "葬送のフリーレン")
        #expect(series.title(preferring: ["fr"]) == "葬送のフリーレン")
        #expect(series.cover.x250?.absoluteString == "https://cdn.mangabaka.dev/x250")
        #expect(series.cover.width == 1303)
        #expect(series.externalIDs.aniList == 118_586)
        #expect(series.externalIDs.myAnimeList == 126_287)
        #expect(series.externalIDs.kitsu == nil)
        #expect(series.externalIDs.mangaUpdates == "ugf5dzu")
        #expect(series.totalChapters == 147)
        #expect(series.finalVolume == nil)
        #expect(series.ratingCount == 1520)
        #expect(series.hasAnime)
        #expect(series.publishedStart == "2020-04-28")
        #expect(series.publishers.first?.name == "Devir")
        #expect(series.lastUpdatedAt == Date(timeIntervalSince1970: 1_792_369_575.355))
        #expect(series.tags == nil)
    }

    @Test
    internal func searchRejectsPagesPastTheResultWindowWithoutSending() async {
        let transport = MockTransport([])
        let client = makeClient(transport)

        // 120 * 100 is the last page; Int.max / 2 * 100 would overflow if multiplied.
        for page in [121, Int.max / 2] {
            let thrown = await error { try await client.searchSeries(SeriesSearchQuery(page: page, limit: 100)) }
            guard case .invalidRequest? = thrown as? MangaBakaError else {
                Issue.record("Expected invalidRequest, got \(String(describing: thrown))")
                return
            }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test
    internal func seriesDecodesAbsentOptionalAndUnknownFields() async throws {
        var series = Fixture.series(id: 7, type: "webtoon")
        for optional in ["titles", "published", "rating_count", "popularity"] {
            series.removeValue(forKey: optional)
        }
        series["status"] = "rebooting"
        series["future_field"] = ["nested": true]
        series["cover"] = ["raw": NSNull(), "future_size": "x900"]
        series["source"] = (series["source"] as? [String: Any] ?? [:]).merging(["new_site": ["id": 1]]) { old, _ in old }
        let client = makeClient(MockTransport([.json(["status": 200, "data": series, "cache": "hit"])]))

        let decoded = try await client.series(id: 7)

        #expect(decoded.type == SeriesType(rawValue: "webtoon"))
        #expect(decoded.status.rawValue == "rebooting")
        #expect(decoded.titles.isEmpty)
        #expect(decoded.title() == nil)
        #expect(decoded.publishedStart == nil)
        #expect(decoded.ratingCount == nil)
        #expect(decoded.cover.raw == nil)
    }

    @Test
    internal func seriesWithMissingRequiredFieldIsAnInvalidResponse() async {
        var series = Fixture.series(id: 7)
        series.removeValue(forKey: "id")
        let client = makeClient(MockTransport([.json(["status": 200, "data": series])]))

        let thrown = await error { try await client.series(id: 7) }

        guard case .invalidResponse? = thrown as? MangaBakaError else {
            Issue.record("Expected invalidResponse, got \(String(describing: thrown))")
            return
        }
    }

    @Test
    internal func fullSeriesIncludesLinksTagsAndRelationships() async throws {
        let transport = MockTransport([.json(["status": 200, "data": Fixture.fullSeries(id: 1995)])])
        let client = makeClient(transport)

        let series = try await client.series(id: 1995, detail: .full)

        #expect(transport.requests.first?.pathWithoutQuery == "/v2/series/1995")
        #expect(transport.requests.first?.query("schema") == ["full"])
        #expect(series.links?.first?.name == "Shounen Sunday")
        #expect(series.links?.first?.kind == "info")
        #expect(series.tags?.first?.namePath == "Activities > Daily Life > Cooking")
        #expect(series.tags?.first?.weight == "unweighted")
        #expect(series.relationships?.first?.seriesID == 77_346)
        #expect(series.relationships?.first?.relationType == "parody")
    }

    @Test
    internal func mergedSeriesPointsToItsReplacement() async throws {
        var series = Fixture.series(id: 10)
        series["state"] = "merged"
        series["merged_with"] = 1995
        let client = makeClient(MockTransport([.json(["status": 200, "data": series])]))

        let decoded = try await client.series(id: 10)

        #expect(decoded.state == .merged)
        #expect(decoded.mergedWith == 1995)
    }

    @Test
    internal func sourceLookupReturnsSeriesIDs() async throws {
        let transport = MockTransport([
            .json(["status": 200, "data": ["source_response": NSNull(), "series": [["id": 1995, "state": "active", "title": "Frieren"]]]]),
            .json(["status": 200, "data": ["source_response": NSNull()]])
        ])
        let client = makeClient(transport)

        #expect(try await client.seriesIDs(aniListID: 118_586) == [1995])
        #expect(try await client.seriesIDs(myAnimeListID: 1).isEmpty)
        #expect(transport.requests.map(\.pathWithoutQuery) == ["/v1/source/anilist/118586", "/v1/source/my-anime-list/1"])
    }

    @Test
    internal func similarAndReadersAlsoLikeCarryTheirScores() async throws {
        let similar: [[String: Any]] = [
            ["series": Fixture.series(id: 2), "score": 0.82, "shared_tags": [["id": 669, "name": "Cooking", "weight": NSNull()]], "shared_tags_total": 1]
        ]
        let alsoLike: [[String: Any]] = [["series": Fixture.series(id: 3), "rank": 1, "score": 0.5, "shared_users": 40]]
        let transport = MockTransport([.json(["status": 200, "data": similar]), .json(["status": 200, "data": alsoLike])])
        let client = makeClient(transport)

        let similarResults = try await client.similarSeries(to: 1, limit: 5, contentRatings: [.safe])
        let alsoLikeResults = try await client.readersAlsoLike(1)

        #expect(similarResults.first?.series.id == 2)
        #expect(similarResults.first?.sharedTags == ["Cooking"])
        #expect(alsoLikeResults.first?.sharedReaders == 40)
        #expect(transport.requests[0].query("content_rating") == ["safe"])
        #expect(transport.requests[0].query("limit") == ["5"])
        #expect(transport.requests[1].pathWithoutQuery == "/v2/series/1/readers-also-like")
    }
}
