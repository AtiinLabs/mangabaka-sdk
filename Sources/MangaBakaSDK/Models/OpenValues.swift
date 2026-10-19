/// A string-backed value that accepts values the SDK does not list.
///
/// MangaBaka adds enumeration values without notice. Types conforming to this protocol decode any
/// string, offer the documented values as static constants and send their raw value unchanged.
public protocol MangaBakaOpenValue: RawRepresentable, Hashable, Sendable, CustomStringConvertible,
    ExpressibleByStringLiteral where RawValue == String {
    /// Creates a value from its raw API representation.
    init(rawValue: String)
}

extension MangaBakaOpenValue {
    /// Creates a value from a string literal.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// The raw API representation.
    public var description: String { rawValue }
}

/// The publication format of a series.
public struct SeriesType: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Japanese comics.
    public static let manga = Self(rawValue: "manga")
    /// Prose novels, including light novels.
    public static let novel = Self(rawValue: "novel")
    /// Korean comics.
    public static let manhwa = Self(rawValue: "manhwa")
    /// Chinese comics.
    public static let manhua = Self(rawValue: "manhua")
    /// Original English-language comics.
    public static let oel = Self(rawValue: "oel")
    /// Any other format.
    public static let other = Self(rawValue: "other")
}

/// The publication status of a series.
public struct SeriesStatus: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Publication was cancelled.
    public static let cancelled = Self(rawValue: "cancelled")
    /// Publication has finished.
    public static let completed = Self(rawValue: "completed")
    /// Publication is paused.
    public static let hiatus = Self(rawValue: "hiatus")
    /// New chapters are being released.
    public static let releasing = Self(rawValue: "releasing")
    /// The status is unknown.
    public static let unknown = Self(rawValue: "unknown")
    /// Publication has not started.
    public static let upcoming = Self(rawValue: "upcoming")
}

/// The content rating of a series or tag.
public struct ContentRating: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Suitable for all readers.
    public static let safe = Self(rawValue: "safe")
    /// Contains suggestive content.
    public static let suggestive = Self(rawValue: "suggestive")
    /// Contains erotic content.
    public static let erotica = Self(rawValue: "erotica")
    /// Contains pornographic content.
    public static let pornographic = Self(rawValue: "pornographic")
}

/// Whether a series record is current.
public struct SeriesState: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The series is current.
    public static let active = Self(rawValue: "active")
    /// The series was merged into the series in ``Series/mergedWith``.
    public static let merged = Self(rawValue: "merged")
    /// The series was removed.
    public static let deleted = Self(rawValue: "deleted")
}

/// The reading state of a library entry.
public struct LibraryState: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The reader is considering the series.
    public static let considering = Self(rawValue: "considering")
    /// The reader finished the series.
    public static let completed = Self(rawValue: "completed")
    /// The reader stopped reading the series.
    public static let dropped = Self(rawValue: "dropped")
    /// The reader paused the series.
    public static let paused = Self(rawValue: "paused")
    /// The reader plans to read the series.
    public static let planToRead = Self(rawValue: "plan_to_read")
    /// The reader is reading the series.
    public static let reading = Self(rawValue: "reading")
    /// The reader is reading the series again.
    public static let rereading = Self(rawValue: "rereading")
}

/// The sort order of a series search.
public struct SeriesSort: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Best text match first.
    public static let relevance = Self(rawValue: "relevance_desc")
    /// Most popular first.
    public static let popularity = Self(rawValue: "popularity_desc")
    /// Highest rated first.
    public static let score = Self(rawValue: "score_desc")
    /// Most trending over the last 7 days first.
    public static let trendingWeek = Self(rawValue: "trending_7d")
    /// Most trending over the last 30 days first.
    public static let trendingMonth = Self(rawValue: "trending_30d")
    /// Most recently added first.
    public static let latest = Self(rawValue: "latest")
    /// Most recently started publication first.
    public static let newestPublished = Self(rawValue: "published_start_date_desc")
    /// Most chapters first.
    public static let mostChapters = Self(rawValue: "chapters_desc")
    /// Random order; pass ``SeriesSearchQuery/randomSeed`` for stable pages.
    public static let random = Self(rawValue: "random")
}

/// The sort order of a library listing.
public struct LibrarySort: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// MangaBaka's default library order.
    public static let `default` = Self(rawValue: "default")
    /// Most recently updated entries first.
    public static let recentlyUpdated = Self(rawValue: "updated_at_desc")
    /// Least recently updated entries first.
    public static let leastRecentlyUpdated = Self(rawValue: "updated_at_asc")
    /// Most recently added entries first.
    public static let recentlyAdded = Self(rawValue: "created_at_desc")
    /// Highest personal rating first.
    public static let myRating = Self(rawValue: "my_rating_desc")
    /// Highest priority first.
    public static let priority = Self(rawValue: "priority_desc")
}

/// A machine-readable reason MangaBaka refused a request.
public struct MangaBakaErrorCode: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The token is no longer valid; sign in again.
    public static let staleToken = Self(rawValue: "stale_token")
    /// The entry already exists.
    public static let duplicateEntry = Self(rawValue: "duplicate_entry")
    /// The series is merged or inactive and cannot be added.
    public static let seriesUnavailable = Self(rawValue: "series_unavailable")
    /// The request was rate limited.
    public static let rateLimited = Self(rawValue: "rate_limited")
}

/// The outcome for one entry of a library batch.
public struct LibraryBatchAction: MangaBakaOpenValue {
    /// The raw API representation.
    public let rawValue: String

    /// Creates a value from its raw API representation.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A new entry was created.
    public static let created = Self(rawValue: "created")
    /// An existing entry was updated.
    public static let updated = Self(rawValue: "updated")
    /// The series was already in the library and `insertOnly` was set.
    public static let skipped = Self(rawValue: "skipped")
}
