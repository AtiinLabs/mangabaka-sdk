import Foundation

extension MangaBakaClient {
    /// Returns the signed-in user.
    public func profile() async throws -> MangaBakaProfile {
        try await call {
            let user = try await api.getMyProfileV1().ok.body.json.data
            return MangaBakaProfile(
                id: user.id,
                nickname: user.nickname,
                preferredUsername: user.preferredUsername,
                pictureURL: URL(api: user.picture),
                role: user.role,
                authenticationType: user.authType,
                scopes: user.scopes,
                libraryDefaultState: user.libraryDefaultState.map(LibraryState.init(rawValue:))
            )
        }
    }

    /// Returns a page of the signed-in user's library.
    public func library(_ query: LibraryQuery = LibraryQuery()) async throws -> MangaBakaPage<LibraryItem> {
        try validate(page: query.page, limit: query.limit, maximumLimit: LibraryQuery.maximumLimit)
        guard query.page <= LibraryQuery.maximumPage else {
            throw MangaBakaError.invalidRequest("page must not exceed \(LibraryQuery.maximumPage).")
        }
        return try await call {
            let response = try await api.getMyLibraryV2(query: .init(
                page: query.page,
                limit: query.limit,
                state: query.states.rawValues,
                updatedAfter: query.updatedAfter,
                sortBy: query.sort?.rawValue,
                schema: query.detail.schema
            )).ok.body.json
            return try MangaBakaPage(response.pagination, items: response.data.map { item in
                let series = try Series(item.series)
                return LibraryItem(
                    entry: LibraryEntry(item.entry, seriesID: series.id),
                    series: series,
                    lists: item.lists.map { LibraryList(id: Int(api: $0.id), name: $0.name, isPrivate: $0.isPrivate) }
                )
            })
        }
    }

    /// Returns the library entry for a series, or `nil` when the series is not in the library.
    public func libraryEntry(seriesID: Int) async throws -> LibraryEntry? {
        do {
            return try await call {
                let entry = try await api.getMyLibrarySeriesIdV1(path: .init(seriesId: seriesID)).ok.body.json.data
                return LibraryEntry(entry, seriesID: seriesID)
            }
        } catch MangaBakaError.notFound {
            return nil
        }
    }

    /// Adds a series to the library. Fails with ``MangaBakaError/badRequest(_:)`` and
    /// ``MangaBakaErrorCode/duplicateEntry`` when the series is already in the library.
    ///
    /// Never retried automatically.
    public func createLibraryEntry(seriesID: Int, _ changes: LibraryEntryChanges) async throws {
        try await call {
            _ = try await api.postMyLibrarySeriesIdV1(
                path: .init(seriesId: seriesID),
                body: .json(changes.createBody)
            ).created
        }
    }

    /// Writes the non-`nil` fields of `changes` to an existing library entry.
    ///
    /// Never retried automatically.
    public func updateLibraryEntry(seriesID: Int, _ changes: LibraryEntryChanges) async throws {
        try await call {
            _ = try await api.patchMyLibrarySeriesIdV1(
                path: .init(seriesId: seriesID),
                body: .json(changes.updateBody)
            ).ok
        }
    }

    /// Removes a series from the library.
    ///
    /// Never retried automatically.
    public func deleteLibraryEntry(seriesID: Int) async throws {
        try await call {
            _ = try await api.deleteMyLibrarySeriesIdV1(path: .init(seriesId: seriesID)).ok
        }
    }

    /// Creates or updates up to 100 library entries atomically: if one fails, none are written.
    ///
    /// Never retried automatically.
    /// - Parameters:
    ///   - items: The entries to write, 1–100.
    ///   - insertOnly: Skip series already in the library instead of updating them.
    public func upsertLibraryEntries(
        _ items: [LibraryBatchItem],
        insertOnly: Bool = false
    ) async throws -> [LibraryBatchResult] {
        guard (1...100).contains(items.count) else {
            throw MangaBakaError.invalidRequest("A batch must contain 1 to 100 entries.")
        }
        return try await call {
            let response = try await api.postMyLibraryBatchV1(
                query: .init(insertOnly: insertOnly ? true : nil),
                body: .json(items.map { $0.changes.batchBody(seriesID: $0.seriesID) })
            ).ok.body.json
            return response.data.map {
                LibraryBatchResult(seriesID: $0.seriesId, action: LibraryBatchAction(rawValue: $0.action))
            }
        }
    }
}
