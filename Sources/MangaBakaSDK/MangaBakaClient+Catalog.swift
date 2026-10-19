import Foundation

extension MangaBakaClient {
    /// Searches the catalog.
    ///
    /// MangaBaka allows 30 uncached searches per minute per IP address.
    public func searchSeries(_ query: SeriesSearchQuery) async throws -> MangaBakaPage<Series> {
        try validate(page: query.page, limit: query.limit, maximumLimit: SeriesSearchQuery.maximumLimit)
        guard query.page <= SeriesSearchQuery.resultWindow / query.limit else {
            throw MangaBakaError.invalidRequest(
                "page * limit must not exceed \(SeriesSearchQuery.resultWindow); the deepest page at limit \(query.limit) is \(SeriesSearchQuery.resultWindow / query.limit)."
            )
        }
        return try await call {
            let response = try await api.getSeriesSearchV2(query: .init(
                q: query.text,
                _type: query.types.rawValues,
                typeNot: query.excludedTypes.rawValues,
                status: query.statuses.rawValues,
                contentRating: query.contentRatings.rawValues,
                tag: query.tags.nonEmpty,
                tagNot: query.excludedTags.nonEmpty,
                tagMode: query.tags.isEmpty ? nil : query.tagMatching.rawValue,
                isLicensed: query.licensed.map { $0 == .only },
                hasAnime: query.anime.map { $0 == .only },
                page: query.page,
                limit: query.limit,
                sortBy: query.sort?.rawValue,
                randomSeed: query.randomSeed,
                schema: query.detail.schema
            )).ok.body.json
            return try MangaBakaPage(response.pagination, items: response.data.map(Series.init))
        }
    }

    /// Returns a series.
    ///
    /// Merged and deleted series are returned with ``Series/state`` set; follow
    /// ``Series/mergedWith`` to reach the current record.
    public func series(id: Int, detail: SeriesDetail = .standard) async throws -> Series {
        try await call {
            let response = try await api.getSeriesIdV2(
                path: .init(id: id),
                query: .init(schema: detail.schema)
            ).ok.body.json
            return try Series(response.data)
        }
    }

    /// Resolves an exact full title to matching series. Returns nothing rather than guessing.
    /// - Parameters:
    ///   - title: The full title, with words in order and no typos.
    ///   - types: Only include these formats.
    ///   - limit: The number of results, 1–100.
    ///   - detail: How much of each series to return.
    public func matchSeries(
        title: String,
        types: [SeriesType] = [],
        limit: Int = 10,
        detail: SeriesDetail = .standard
    ) async throws -> [Series] {
        try validate(page: 1, limit: limit, maximumLimit: 100)
        return try await call {
            let response = try await api.getSeriesMatchV2(query: .init(
                q: title,
                _type: types.rawValues,
                limit: limit,
                schema: detail.schema
            )).ok.body.json
            return try response.data.map(Series.init)
        }
    }

    /// Returns series that share tags with a series.
    /// - Parameters:
    ///   - seriesID: The series to compare with.
    ///   - limit: The number of results, 1–24.
    ///   - contentRatings: Only include these content ratings. Empty uses MangaBaka's default.
    ///   - detail: How much of each series to return.
    public func similarSeries(
        to seriesID: Int,
        limit: Int = 12,
        contentRatings: [ContentRating] = [],
        detail: SeriesDetail = .standard
    ) async throws -> [SimilarSeries] {
        try validate(page: 1, limit: limit, maximumLimit: 24)
        return try await call {
            let response = try await api.getSeriesIdSimilarV2(
                path: .init(id: seriesID),
                query: .init(limit: limit, contentRating: contentRatings.rawValues, schema: detail.schema)
            ).ok.body.json
            return try response.data.map {
                SimilarSeries(series: try Series($0.series), score: $0.score, sharedTags: $0.sharedTags.map(\.name))
            }
        }
    }

    /// Returns series that readers of a series also have in their libraries.
    /// - Parameters:
    ///   - seriesID: The series to start from.
    ///   - limit: The number of results, 1–24.
    ///   - contentRatings: Only include these content ratings. Empty uses MangaBaka's default.
    ///   - detail: How much of each series to return.
    public func readersAlsoLike(
        _ seriesID: Int,
        limit: Int = 12,
        contentRatings: [ContentRating] = [],
        detail: SeriesDetail = .standard
    ) async throws -> [ReadersAlsoLikeSeries] {
        try validate(page: 1, limit: limit, maximumLimit: 24)
        return try await call {
            let response = try await api.getSeriesIdReadersAlsoLikeV2(
                path: .init(id: seriesID),
                query: .init(limit: limit, contentRating: contentRatings.rawValues, schema: detail.schema)
            ).ok.body.json
            return try response.data.map {
                ReadersAlsoLikeSeries(series: try Series($0.series), rank: $0.rank, score: $0.score, sharedReaders: $0.sharedUsers)
            }
        }
    }

    /// Returns the IDs of active MangaBaka series linked to an AniList media ID.
    public func seriesIDs(aniListID: Int) async throws -> [Int] {
        try await call {
            let response = try await api.getSourceAnilistIdV1(path: .init(id: aniListID)).ok.body.json
            return try (response.data.series ?? []).map { try Int(requiredAPI: $0.id, field: "series.id") }
        }
    }

    /// Returns the IDs of active MangaBaka series linked to a MyAnimeList manga ID.
    public func seriesIDs(myAnimeListID: Int) async throws -> [Int] {
        try await call {
            let response = try await api.getSourceMyAnimeListIdV1(path: .init(id: myAnimeListID)).ok.body.json
            return try (response.data.series ?? []).map { try Int(requiredAPI: $0.id, field: "series.id") }
        }
    }

    /// Returns the genre filter values.
    public func genres() async throws -> [Genre] {
        try await call {
            try await api.getGenresV1().ok.body.json.data.map { Genre(value: $0.value, label: $0.label) }
        }
    }

    /// Returns tags, ranked by relevance when `text` is set and in tree order otherwise.
    /// - Parameters:
    ///   - text: Text to rank tags by.
    ///   - genresOnly: Only return genres.
    ///   - page: The page number, starting at 1.
    ///   - limit: The page size, 1–10000.
    public func tags(
        matching text: String? = nil,
        genresOnly: Bool = false,
        page: Int = 1,
        limit: Int = 100
    ) async throws -> MangaBakaPage<MangaBakaTag> {
        try validate(page: page, limit: limit, maximumLimit: 10_000)
        return try await call {
            let response = try await api.getTagsV1(query: .init(
                q: text,
                isGenre: genresOnly ? true : nil,
                page: page,
                limit: limit
            )).ok.body.json
            return MangaBakaPage(response.pagination, items: response.data.map(MangaBakaTag.init))
        }
    }
}
