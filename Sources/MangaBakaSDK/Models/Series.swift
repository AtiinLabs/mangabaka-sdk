import Foundation

/// A MangaBaka series.
///
/// Fields marked as full-detail are only present when the series was requested with
/// ``SeriesDetail/full``; otherwise they are `nil`.
public struct Series: Sendable, Hashable, Identifiable {
    /// The MangaBaka series ID.
    public let id: Int
    /// Whether the record is current, merged or deleted.
    public let state: SeriesState
    /// The series this one was merged into, when ``state`` is ``SeriesState/merged``.
    public let mergedWith: Int?
    /// Titles in every recorded language.
    public let titles: [SeriesTitle]
    /// The publication format.
    public let type: SeriesType
    /// The publication status.
    public let status: SeriesStatus
    /// The content rating.
    public let contentRating: ContentRating
    /// The synopsis.
    public let synopsis: String?
    /// Cover images.
    public let cover: SeriesCover
    /// Author names.
    public let authors: [String]
    /// Artist names.
    public let artists: [String]
    /// Publishers by language.
    public let publishers: [SeriesPublisher]
    /// The language of the original publication.
    public let originalLanguage: String?
    /// Whether the series is licensed in English.
    public let isLicensed: Bool
    /// Whether the series has an anime adaptation.
    public let hasAnime: Bool
    /// The first publication date, as `YYYY-MM-DD` or a shorter prefix.
    public let publishedStart: String?
    /// The last publication date, as `YYYY-MM-DD` or a shorter prefix.
    public let publishedEnd: String?
    /// The total chapter count, if known. Fractional chapters are possible.
    public let totalChapters: Double?
    /// The final volume number, if known.
    public let finalVolume: Double?
    /// The aggregate rating on a 0–100 scale.
    public let rating: Double?
    /// The number of ratings backing ``rating``.
    public let ratingCount: Int?
    /// The series page on mangabaka.org.
    public let canonicalURL: URL?
    /// When MangaBaka last updated the record.
    public let lastUpdatedAt: Date?
    /// IDs of the same series on other sites.
    public let externalIDs: SeriesExternalIDs
    /// Links to official and informational sites. Full detail only.
    public let links: [SeriesLink]?
    /// Tags, including genres. Full detail only.
    public let tags: [MangaBakaTag]?
    /// Related series. Full detail only.
    public let relationships: [SeriesRelationship]?

    /// The best title for display.
    ///
    /// Picks the first primary title in the earliest matching language, then any title in that
    /// language, then the first primary title.
    /// - Parameter languages: Preferred BCP 47 language tags, most preferred first.
    public func title(preferring languages: [String] = ["en", "ja-Latn"]) -> String? {
        for language in languages {
            let matches = titles.filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
            if let title = matches.first(where: \.isPrimary) ?? matches.first {
                return title.title
            }
        }
        return (titles.first(where: \.isPrimary) ?? titles.first)?.title
    }
}

/// How much of a series record to request.
public enum SeriesDetail: String, Sendable, Hashable {
    /// The lean record: no links, tags or relationships.
    case standard
    /// Adds links, tags, relationships and the full title list.
    case full
}

/// A title of a series in one language.
public struct SeriesTitle: Sendable, Hashable {
    /// The title text.
    public let title: String
    /// The BCP 47 language tag, for example `en` or `ja-Latn`.
    public let language: String
    /// Traits such as `official`, `native` or `alternative`.
    public let traits: [String]
    /// Whether this is the primary title for its language.
    public let isPrimary: Bool
}

/// Cover image URLs.
public struct SeriesCover: Sendable, Hashable {
    /// The original image.
    public let raw: URL?
    /// A 150-pixel-wide rendition.
    public let x150: URL?
    /// A 250-pixel-wide rendition.
    public let x250: URL?
    /// A 350-pixel-wide rendition.
    public let x350: URL?
    /// The original width in pixels.
    public let width: Int?
    /// The original height in pixels.
    public let height: Int?
    /// A BlurHash placeholder.
    public let blurhash: String?
}

/// A publisher of a series in one language.
public struct SeriesPublisher: Sendable, Hashable {
    /// The publisher ID.
    public let id: Int?
    /// The publisher name.
    public let name: String?
    /// The language this publisher publishes in.
    public let language: String?
    /// A note, such as the imprint.
    public let note: String?
}

/// IDs of a series on other sites.
public struct SeriesExternalIDs: Sendable, Hashable {
    /// The AniList media ID.
    public let aniList: Int?
    /// The MyAnimeList manga ID.
    public let myAnimeList: Int?
    /// The Kitsu manga ID.
    public let kitsu: Int?
    /// The MangaUpdates series ID.
    public let mangaUpdates: String?
    /// The Anime-Planet slug.
    public let animePlanet: String?
    /// The Anime News Network ID.
    public let animeNewsNetwork: Int?
    /// The Shikimori ID.
    public let shikimori: Int?
}

/// A link to an external site.
public struct SeriesLink: Sendable, Hashable {
    /// The link URL.
    public let url: URL?
    /// The site's display name.
    public let name: String
    /// The kind of site, for example `info` or `webplatform`.
    public let kind: String
    /// The language of the linked content.
    public let language: String
}

/// A relationship from one series to another.
public struct SeriesRelationship: Sendable, Hashable {
    /// The related series ID.
    public let seriesID: Int
    /// The relation, for example `sequel`, `prequel` or `adaptation`.
    public let relationType: String
    /// The relative order, for example `before`, `after` or `unknown`.
    public let chronology: String
    /// A note about the relationship.
    public let note: String?
}

/// A MangaBaka tag. Genres are tags with ``isGenre`` set.
public struct MangaBakaTag: Sendable, Hashable, Identifiable {
    /// The tag ID.
    public let id: Int
    /// The tag name.
    public let name: String
    /// The full path in the tag tree, for example `Activities > Daily Life > Cooking`.
    public let namePath: String
    /// The parent tag ID.
    public let parentID: Int?
    /// Whether the tag is a genre.
    public let isGenre: Bool
    /// Whether the tag reveals plot details.
    public let isSpoiler: Bool
    /// The content rating of the tag.
    public let contentRating: ContentRating?
    /// The tag description.
    public let summary: String?
    /// How strongly the tag applies to a series, when the tag is attached to one.
    public let weight: String?
}

/// A genre filter value.
public struct Genre: Sendable, Hashable {
    /// The value to pass in filters.
    public let value: String
    /// The display name.
    public let label: String
}

/// A series similar to another, by shared tags.
public struct SimilarSeries: Sendable, Hashable {
    /// The similar series.
    public let series: Series
    /// The similarity score.
    public let score: Double
    /// Names of the tags both series share.
    public let sharedTags: [String]
}

/// A series that readers of another series also have in their libraries.
public struct ReadersAlsoLikeSeries: Sendable, Hashable {
    /// The recommended series.
    public let series: Series
    /// The rank, starting at 1.
    public let rank: Int
    /// The recommendation score.
    public let score: Double
    /// The number of readers who have both series.
    public let sharedReaders: Int
}

/// One page of results.
public struct MangaBakaPage<Element: Sendable>: Sendable {
    /// The results on this page.
    public let items: [Element]
    /// The page number, starting at 1.
    public let page: Int
    /// The page size.
    public let limit: Int
    /// The total number of results across all pages.
    public let totalCount: Int
    /// Whether another page follows.
    public let hasNextPage: Bool
}

extension MangaBakaPage: Equatable where Element: Equatable {}
extension MangaBakaPage: Hashable where Element: Hashable {}
