import Foundation

/// Converts JSON numbers that MangaBaka documents as integers.
internal extension Int {
    init?(api value: Double?) {
        guard let value, let exact = Int(exactly: value) else {
            return nil
        }
        self = exact
    }

    /// Converts an ID MangaBaka requires, failing decoding when it is not an integer.
    init(requiredAPI value: Double, field: String) throws {
        guard let exact = Int(exactly: value) else {
            throw MangaBakaError.invalidResponse(DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "\(field) is not an integer: \(value)"
            )))
        }
        self = exact
    }
}

internal extension URL {
    init?(api string: String?) {
        guard let string, !string.isEmpty else {
            return nil
        }
        self.init(string: string)
    }
}

internal extension LibraryDate {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }()

    /// MangaBaka returns a day as midnight UTC.
    init?(api date: Date?) {
        guard let date else {
            return nil
        }
        let components = Self.utc.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// MangaBaka reads the day from a date-time as written, so the day is sent as midnight UTC.
    var apiDate: Date? {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day))
    }
}

internal extension Series {
    init(_ series: Components.Schemas.SeriesV2Full) throws {
        try self.init(
            id: Int(requiredAPI: series.id, field: "series.id"),
            state: SeriesState(rawValue: series.state),
            mergedWith: Int(api: series.mergedWith),
            titles: (series.titles ?? []).map {
                SeriesTitle(title: $0.title, language: $0.language, traits: $0.traits, isPrimary: $0.isPrimary ?? false)
            },
            type: SeriesType(rawValue: series._type),
            status: SeriesStatus(rawValue: series.status),
            contentRating: ContentRating(rawValue: series.contentRating),
            synopsis: series.description,
            cover: SeriesCover(series.cover),
            authors: series.authors ?? [],
            artists: series.artists ?? [],
            publishers: (series.publishers ?? []).map {
                SeriesPublisher(id: $0.id, name: $0.name, language: $0.language, note: $0.note)
            },
            originalLanguage: series.originalLanguage,
            isLicensed: series.isLicensed,
            hasAnime: series.anime.exists,
            publishedStart: series.published?.startDate,
            publishedEnd: series.published?.endDate,
            totalChapters: series.totalChapters,
            finalVolume: series.finalVolume,
            rating: series.rating,
            ratingCount: Int(api: series.ratingCount),
            canonicalURL: URL(api: series.canonicalUrl),
            lastUpdatedAt: series.lastUpdatedAt,
            externalIDs: SeriesExternalIDs(series.source),
            links: series.links?.map {
                SeriesLink(url: URL(api: $0.url), name: $0.nameDisplay, kind: $0._type, language: $0.language)
            },
            tags: series.tags?.map(MangaBakaTag.init),
            relationships: try series.relationships?.map {
                SeriesRelationship(
                    seriesID: try Int(requiredAPI: $0.toSeriesId, field: "relationship.to_series_id"),
                    relationType: $0.relationType,
                    chronology: $0.chronology,
                    note: $0.note
                )
            }
        )
    }
}

internal extension SeriesCover {
    init(_ cover: Components.Schemas.SeriesV2Full.CoverPayload) {
        self.init(
            raw: URL(api: cover.raw),
            x150: URL(api: cover.x150),
            x250: URL(api: cover.x250),
            x350: URL(api: cover.x350),
            width: Int(api: cover.width),
            height: Int(api: cover.height),
            blurhash: cover.blurhash
        )
    }
}

internal extension SeriesExternalIDs {
    init(_ source: Components.Schemas.SeriesV2Full.SourcePayload) {
        self.init(
            aniList: Int(api: source.anilist.id),
            myAnimeList: Int(api: source.myAnimeList.id),
            kitsu: Int(api: source.kitsu.id),
            mangaUpdates: source.mangaUpdates.id,
            animePlanet: source.animePlanet.id,
            animeNewsNetwork: Int(api: source.animeNewsNetwork.id),
            shikimori: Int(api: source.shikimori.id)
        )
    }
}

internal extension MangaBakaTag {
    init(_ tag: Components.Schemas.V1SeriesTag) {
        self.init(
            id: tag.id,
            name: tag.name,
            namePath: tag.namePath,
            parentID: tag.parentId,
            isGenre: tag.isGenre ?? false,
            isSpoiler: tag.isSpoiler ?? false,
            contentRating: ContentRating(rawValue: tag.contentRating),
            summary: tag.description,
            weight: tag.weight
        )
    }

    init(_ tag: Operations.GetTagsV1.Output.Ok.Body.JsonPayload.DataPayloadPayload) {
        self.init(
            id: tag.id,
            name: tag.name,
            namePath: tag.namePath,
            parentID: Int(api: tag.parentId),
            isGenre: tag.isGenre ?? false,
            isSpoiler: tag.isSpoiler ?? false,
            contentRating: tag.contentRating.map(ContentRating.init(rawValue:)),
            summary: tag.description,
            weight: nil
        )
    }
}

internal extension LibraryEntry {
    init(_ entry: Components.Schemas.LibraryEntryV2.EntryPayload, seriesID: Int) {
        self.init(
            seriesID: Int(api: entry.seriesId) ?? seriesID,
            state: entry.state.map(LibraryState.init(rawValue:)),
            progressChapter: entry.progressChapter,
            progressVolume: entry.progressVolume,
            rating: entry.rating,
            priority: Int(api: entry.priority),
            isPrivate: entry.isPrivate ?? false,
            numberOfRereads: Int(api: entry.numberOfRereads),
            note: entry.note,
            readLink: entry.readLink,
            startDate: LibraryDate(api: entry.startDate),
            finishDate: LibraryDate(api: entry.finishDate)
        )
    }

    init(_ entry: Operations.GetMyLibrarySeriesIdV1.Output.Ok.Body.JsonPayload.DataPayload, seriesID: Int) {
        self.init(
            seriesID: Int(api: entry.seriesId) ?? seriesID,
            state: entry.state.map(LibraryState.init(rawValue:)),
            progressChapter: entry.progressChapter,
            progressVolume: entry.progressVolume,
            rating: entry.rating,
            priority: Int(api: entry.priority),
            isPrivate: entry.isPrivate ?? false,
            numberOfRereads: Int(api: entry.numberOfRereads),
            note: entry.note,
            readLink: entry.readLink,
            startDate: LibraryDate(api: entry.startDate),
            finishDate: LibraryDate(api: entry.finishDate)
        )
    }
}

internal extension LibraryEntryChanges {
    var createBody: Operations.PostMyLibrarySeriesIdV1.Input.Body.JsonPayload {
        .init(
            finishDate: finishDate?.apiDate,
            isPrivate: isPrivate,
            note: note,
            numberOfRereads: numberOfRereads.map(Double.init),
            priority: priority.map(Double.init),
            progressChapter: progressChapter,
            progressVolume: progressVolume,
            rating: rating,
            readLink: readLink,
            startDate: startDate?.apiDate,
            state: state?.rawValue
        )
    }

    var updateBody: Operations.PatchMyLibrarySeriesIdV1.Input.Body.JsonPayload {
        .init(
            finishDate: finishDate?.apiDate,
            isPrivate: isPrivate,
            note: note,
            numberOfRereads: numberOfRereads.map(Double.init),
            priority: priority.map(Double.init),
            progressChapter: progressChapter,
            progressVolume: progressVolume,
            rating: rating,
            readLink: readLink,
            startDate: startDate?.apiDate,
            state: state?.rawValue
        )
    }

    func batchBody(seriesID: Int) -> Operations.PostMyLibraryBatchV1.Input.Body.JsonPayloadPayload {
        .init(
            finishDate: finishDate?.apiDate,
            isPrivate: isPrivate,
            note: note,
            numberOfRereads: numberOfRereads.map(Double.init),
            priority: priority.map(Double.init),
            progressChapter: progressChapter,
            progressVolume: progressVolume,
            rating: rating,
            readLink: readLink,
            seriesId: seriesID,
            startDate: startDate?.apiDate,
            state: state?.rawValue
        )
    }
}

internal extension MangaBakaPage {
    init(_ pagination: Components.Schemas.V1Pagination, items: [Element]) {
        self.init(
            items: items,
            page: Int(api: pagination.page) ?? 1,
            limit: Int(api: pagination.limit) ?? items.count,
            totalCount: Int(api: pagination.count) ?? items.count,
            hasNextPage: pagination.next != nil
        )
    }
}
