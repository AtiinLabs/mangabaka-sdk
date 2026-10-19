# mangabaka-sdk

A Swift client for the [MangaBaka](https://mangabaka.org) API: catalog search and series details,
plus the signed-in user's library and profile.

This is an unofficial SDK. It is not made or endorsed by MangaBaka.

- async/await, `Sendable` value types, Swift 6 language mode
- Typed errors for 400, 401, 403, 404, 422, 429 and 5xx responses
- Retries for reads only, honoring `Retry-After`; library writes are never repeated automatically
- Credentials are sent only to `/my` routes, never with catalog requests
- Decoding keeps working when MangaBaka adds fields or enumeration values
- Redacted request logging

## Requirements

iOS 15 or macOS 12, Swift 6.0 or later.

## Installation

```swift
.package(url: "https://github.com/AtiinLabs/mangabaka-sdk", branch: "main")
```

```swift
.product(name: "MangaBakaSDK", package: "mangabaka-sdk")
```

## Usage

### Catalog

Catalog requests need no credential. Identify your app in the user agent.

```swift
import MangaBakaSDK

let client = MangaBakaClient(configuration: MangaBakaConfiguration(
    userAgent: "MyApp/1.0 (https://example.com)"
))

let page = try await client.searchSeries(SeriesSearchQuery(
    text: "Frieren",
    types: [.manga],
    statuses: [.releasing, .completed],
    sort: .popularity,
    limit: 20
))
for series in page.items {
    print(series.id, series.title() ?? "", series.cover.x250 as Any)
}
if page.hasNextPage { /* request page.page + 1 */ }

let frieren = try await client.series(id: 1995, detail: .full)  // adds tags, links, relationships
```

A search serves at most 12,000 results: `page * limit` must not exceed 12,000, and `limit` is at
most 100. Out-of-range values throw `MangaBakaError.invalidRequest` without sending a request.

Other catalog calls:

| Method | Endpoint |
| --- | --- |
| `matchSeries(title:types:limit:detail:)` | `GET /v2/series/match` |
| `similarSeries(to:limit:contentRatings:detail:)` | `GET /v2/series/{id}/similar` |
| `readersAlsoLike(_:limit:contentRatings:detail:)` | `GET /v2/series/{id}/readers-also-like` |
| `seriesIDs(aniListID:)` | `GET /v1/source/anilist/{id}` |
| `seriesIDs(myAnimeListID:)` | `GET /v1/source/my-anime-list/{id}` |
| `genres()` | `GET /v1/genres` |
| `tags(matching:genresOnly:page:limit:)` | `GET /v1/tags` |

### Library and profile

Library and profile requests need a credential:

- A Personal Access Token (`mb-…`), created in your MangaBaka settings, is sent in the `x-api-key` header.
- An OAuth 2 access token is sent as `Authorization: Bearer`. The SDK does not run the OAuth flow.
  MangaBaka's OpenID configuration is at `https://mangabaka.org/.well-known/openid-configuration`
  (authorization code with PKCE `S256`, scopes `library.read`, `library.write`, `offline_access`, …).

```swift
let client = MangaBakaClient(configuration: MangaBakaConfiguration(
    userAgent: "MyApp/1.0 (https://example.com)",
    credentialProvider: MangaBakaCredential.personalAccessToken(token)
))

let profile = try await client.profile()
let library = try await client.library(LibraryQuery(states: [.reading], sort: .recentlyUpdated))
let entry = try await client.libraryEntry(seriesID: 1995)  // nil when not in the library

try await client.createLibraryEntry(seriesID: 1995, LibraryEntryChanges(state: .planToRead))
try await client.updateLibraryEntry(seriesID: 1995, LibraryEntryChanges(progressChapter: 61))
try await client.deleteLibraryEntry(seriesID: 1995)

let results = try await client.upsertLibraryEntries([
    LibraryBatchItem(seriesID: 1995, changes: LibraryEntryChanges(state: .reading))
], insertOnly: true)
```

`LibraryEntryChanges` sends only the fields you set; the rest stay unchanged. Fields cannot be
cleared yet, except rating and progress, where MangaBaka stores `0` as none. Start and finish
dates are `LibraryDate` days, so they do not shift between time zones; `LibraryDate(year:month:day:)`
returns `nil` for days that do not exist. `LibraryQuery.updatedAfter` returns only entries changed
since a time, for incremental sync.

To refresh OAuth tokens, implement `MangaBakaCredentialProvider`. The client asks for a credential
before each attempt; if the provider throws, nothing is sent and the call throws
`MangaBakaError.credentialUnavailable`. When MangaBaka answers 401 the call throws
`MangaBakaError.unauthorized`. Credentials print as `personalAccessToken(<redacted>)`.

### Errors, retries and cancellation

Unsuccessful responses throw `MangaBakaError` with the status, MangaBaka's message, its `code`
(for example `duplicateEntry` or `staleToken`), any field `issues` and the `Retry-After` wait.

`GET` requests are retried after 429, 502, 503 and 504 responses and after timeouts or dropped
connections: two retries by default, waiting for `Retry-After` when the server sends it and
backing off exponentially otherwise. A retry that would wait longer than `maximumDelay`
(30 seconds by default) is not made. `POST`, `PATCH` and `DELETE` are never retried. Configure this
with `MangaBakaRetryPolicy`, or turn it off with `.none`.

A library write succeeds on any 2xx status. If it throws `MangaBakaError.transport` or
`CancellationError`, the request may or may not have reached MangaBaka: read the entry before
trying again.

Cancelling the calling task cancels the request and any pending retry and throws `CancellationError`.

### Caching

The default initializer uses `URLSession.shared`. Its `URLCache` keeps catalog responses for as
long as MangaBaka's `Cache-Control` header allows. MangaBaka marks library and profile responses
`no-store`. Pass a `URLSession` with its own cache, or any `ClientTransport`, to change this.

### Logging

Set `MangaBakaConfiguration.logger` to receive one `MangaBakaRequestEvent` per HTTP attempt: the
operation, method, path, status and duration. Events never contain query strings, headers,
credentials or bodies, and series IDs in library paths are replaced with `{id}`.

## Rate limits

MangaBaka allows 30 uncached searches and 180 other uncached requests per minute per IP address.
Responses served from its cache do not count. See [the API page](https://mangabaka.org/data/api).

## OpenAPI document

The generated client comes from MangaBaka's OpenAPI document, built with
[Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator) at build time. Only the
operations listed in `Sources/MangaBakaSDK/openapi-generator-config.yaml` are generated, and
`MangaBakaClient` is the public API; generated types are internal.

| | |
| --- | --- |
| Source | https://mangabaka.org/api.json |
| Title and version | MangaBaka API 1.0 |
| Retrieved | 2026-10-19 |
| Upstream SHA-256 | `022d0b60da69ba7a65e2777fd8188e2bd47d6a88f366cd5ed5d75c02130a9155` |

`Sources/MangaBakaSDK/openapi.json` is that document with the compatibility patches in
`Scripts/update-openapi.py` applied. To update it, run `python3 Scripts/update-openapi.py` from the
package root, then review the document diff and run the tests.

Not wrapped yet: recommendations, mix, discover lists, publishers, editions, works, stacks, user
lists, Kitsu, MangaUpdates and Anime-Planet source lookups, and `PUT` library entries (currently
identical to `PATCH`).

## Testing

```sh
swift test
```

The unit tests use a mock transport. Live read-only tests against the production API are opt-in:

```sh
MANGABAKA_LIVE_TESTS=1 swift test --filter LiveSmokeTests
MANGABAKA_LIVE_TESTS=1 MANGABAKA_TOKEN=mb-… swift test --filter LiveSmokeTests  # also reads profile and library
```

The live tests never write to a library.

## License and attribution

The SDK code is released under the MIT license; see [LICENSE](LICENSE).

MangaBaka's community-contributed data is licensed
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) (see
[About MangaBaka](https://mangabaka.org/about)). Apps that show it must credit MangaBaka, must not use
it commercially, and must share adaptations under the same license. Covers, descriptions and other
data that MangaBaka aggregates from AniList, MyAnimeList, MangaUpdates, Kitsu, Anime-Planet and
other sources remain subject to those providers' terms.
