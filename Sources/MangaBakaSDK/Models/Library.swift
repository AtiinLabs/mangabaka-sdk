import Foundation

/// A calendar day, without time or time zone.
///
/// MangaBaka stores library start and finish dates as days. Using a day instead of `Date`
/// avoids shifting the day when the device and the server are in different time zones.
public struct LibraryDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The year.
    public let year: Int
    /// The month, 1–12.
    public let month: Int
    /// The day of the month, 1–31.
    public let day: Int

    /// Creates a day.
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day as `YYYY-MM-DD`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Orders days chronologically.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// A series in the signed-in user's library.
public struct LibraryEntry: Sendable, Hashable {
    /// The series ID.
    public let seriesID: Int
    /// The reading state.
    public let state: LibraryState?
    /// The chapter read up to. Fractional chapters are possible.
    public let progressChapter: Double?
    /// The volume read up to.
    public let progressVolume: Double?
    /// The personal rating on a 0–100 scale.
    public let rating: Double?
    /// The priority, 10–30.
    public let priority: Int?
    /// Whether the entry is hidden from other users.
    public let isPrivate: Bool
    /// How many times the series was reread.
    public let numberOfRereads: Int?
    /// A personal note.
    public let note: String?
    /// A personal link to where the series is read.
    public let readLink: String?
    /// The day reading started.
    public let startDate: LibraryDate?
    /// The day reading finished.
    public let finishDate: LibraryDate?
}

/// A library entry with its series and the user's lists that contain it.
public struct LibraryItem: Sendable, Hashable {
    /// The library entry.
    public let entry: LibraryEntry
    /// The series.
    public let series: Series
    /// The user's lists that contain the series.
    public let lists: [LibraryList]
}

/// A user-defined list.
public struct LibraryList: Sendable, Hashable {
    /// The list ID.
    public let id: Int?
    /// The list name.
    public let name: String
    /// Whether the list is hidden from other users.
    public let isPrivate: Bool
}

/// Fields to write to a library entry. `nil` fields are not sent and stay unchanged.
public struct LibraryEntryChanges: Sendable, Hashable {
    /// The reading state.
    public var state: LibraryState?
    /// The chapter read up to, 0–10000. MangaBaka stores `0` as no progress.
    public var progressChapter: Double?
    /// The volume read up to. MangaBaka stores `0` as no progress.
    public var progressVolume: Double?
    /// The personal rating, 0–100. MangaBaka stores `0` as no rating.
    public var rating: Double?
    /// The priority, 10–30.
    public var priority: Int?
    /// Whether the entry is hidden from other users.
    public var isPrivate: Bool? // swiftlint:disable:this discouraged_optional_boolean
    /// How many times the series was reread.
    public var numberOfRereads: Int?
    /// A personal note.
    public var note: String?
    /// A personal link to where the series is read.
    public var readLink: String?
    /// The day reading started.
    public var startDate: LibraryDate?
    /// The day reading finished.
    public var finishDate: LibraryDate?

    /// Creates a set of changes. Omitted fields stay unchanged.
    public init(
        state: LibraryState? = nil,
        progressChapter: Double? = nil,
        progressVolume: Double? = nil,
        rating: Double? = nil,
        priority: Int? = nil,
        isPrivate: Bool? = nil, // swiftlint:disable:this discouraged_optional_boolean
        numberOfRereads: Int? = nil,
        note: String? = nil,
        readLink: String? = nil,
        startDate: LibraryDate? = nil,
        finishDate: LibraryDate? = nil
    ) {
        self.state = state
        self.progressChapter = progressChapter
        self.progressVolume = progressVolume
        self.rating = rating
        self.priority = priority
        self.isPrivate = isPrivate
        self.numberOfRereads = numberOfRereads
        self.note = note
        self.readLink = readLink
        self.startDate = startDate
        self.finishDate = finishDate
    }
}

/// One entry of a library batch write.
public struct LibraryBatchItem: Sendable, Hashable {
    /// The series to create or update.
    public var seriesID: Int
    /// The fields to write.
    public var changes: LibraryEntryChanges

    /// Creates a batch item.
    public init(seriesID: Int, changes: LibraryEntryChanges) {
        self.seriesID = seriesID
        self.changes = changes
    }
}

/// The outcome for one entry of a library batch write.
public struct LibraryBatchResult: Sendable, Hashable {
    /// The series ID.
    public let seriesID: Int?
    /// Whether the entry was created, updated or skipped.
    public let action: LibraryBatchAction
}

/// The signed-in user.
public struct MangaBakaProfile: Sendable, Hashable, Identifiable {
    /// The user ID.
    public let id: String
    /// The display name.
    public let nickname: String?
    /// The username.
    public let preferredUsername: String?
    /// The avatar image.
    public let pictureURL: URL?
    /// The site role, for example `user`.
    public let role: String
    /// How the request was authenticated: `pat`, `oauth` or `session`.
    public let authenticationType: String
    /// The scopes granted to the credential.
    public let scopes: [String]
    /// The state MangaBaka assigns to new entries by default.
    public let libraryDefaultState: LibraryState?
}
