import Foundation

/// Parameters for ``MangaBakaClient/searchSeries(_:)``.
///
/// MangaBaka serves at most 12,000 results per query: `page * limit` must not exceed 12,000.
public struct SeriesSearchQuery: Sendable, Hashable {
    /// The largest page size.
    public static let maximumLimit = 100
    /// The deepest result MangaBaka serves for one query.
    public static let resultWindow = 12_000

    /// Text to match against titles.
    public var text: String?
    /// Only include these formats.
    public var types: [SeriesType]
    /// Exclude these formats.
    public var excludedTypes: [SeriesType]
    /// Only include these statuses.
    public var statuses: [SeriesStatus]
    /// Only include these content ratings. Empty uses MangaBaka's default.
    public var contentRatings: [ContentRating]
    /// Only include series with these tags, by name or ID.
    public var tags: [String]
    /// Exclude series with these tags, by name or ID.
    public var excludedTags: [String]
    /// Whether every tag in ``tags`` must match, or any of them.
    public var tagMatching: TagMatching
    /// Filter by English licensing.
    public var licensed: Inclusion?
    /// Filter by anime adaptation.
    public var anime: Inclusion?
    /// The sort order. `nil` uses MangaBaka's default.
    public var sort: SeriesSort?
    /// The seed for ``SeriesSort/random``, at least 0 and less than 1, so pages stay consistent.
    public var randomSeed: Double?
    /// The page number, starting at 1.
    public var page: Int
    /// The page size, 1–100.
    public var limit: Int
    /// How much of each series to return.
    public var detail: SeriesDetail

    /// Creates a search query.
    public init(
        text: String? = nil,
        types: [SeriesType] = [],
        excludedTypes: [SeriesType] = [],
        statuses: [SeriesStatus] = [],
        contentRatings: [ContentRating] = [],
        tags: [String] = [],
        excludedTags: [String] = [],
        tagMatching: TagMatching = .all,
        licensed: Inclusion? = nil,
        anime: Inclusion? = nil,
        sort: SeriesSort? = nil,
        randomSeed: Double? = nil,
        page: Int = 1,
        limit: Int = 20,
        detail: SeriesDetail = .standard
    ) {
        self.text = text
        self.types = types
        self.excludedTypes = excludedTypes
        self.statuses = statuses
        self.contentRatings = contentRatings
        self.tags = tags
        self.excludedTags = excludedTags
        self.tagMatching = tagMatching
        self.licensed = licensed
        self.anime = anime
        self.sort = sort
        self.randomSeed = randomSeed
        self.page = page
        self.limit = limit
        self.detail = detail
    }
}

/// How several tag filters combine.
public enum TagMatching: String, Sendable, Hashable {
    /// Every tag must match.
    case all = "and"
    /// At least one tag must match.
    case any = "or"
}

/// Whether a filter keeps only matching series or removes them.
public enum Inclusion: Sendable, Hashable {
    /// Keep only series that match.
    case only
    /// Remove series that match.
    case excluded
}

/// Parameters for ``MangaBakaClient/library(_:)``.
public struct LibraryQuery: Sendable, Hashable {
    /// The largest page size.
    public static let maximumLimit = 100
    /// The deepest page MangaBaka serves.
    public static let maximumPage = 10_000

    /// Only include entries in these states.
    public var states: [LibraryState]
    /// Only include entries updated at or after this time, for incremental sync.
    public var updatedAfter: Date?
    /// The sort order. `nil` uses MangaBaka's default.
    public var sort: LibrarySort?
    /// The page number, 1–10000.
    public var page: Int
    /// The page size, 1–100.
    public var limit: Int
    /// How much of each series to return.
    public var detail: SeriesDetail

    /// Creates a library query.
    public init(
        states: [LibraryState] = [],
        updatedAfter: Date? = nil,
        sort: LibrarySort? = nil,
        page: Int = 1,
        limit: Int = 50,
        detail: SeriesDetail = .standard
    ) {
        self.states = states
        self.updatedAfter = updatedAfter
        self.sort = sort
        self.page = page
        self.limit = limit
        self.detail = detail
    }
}
