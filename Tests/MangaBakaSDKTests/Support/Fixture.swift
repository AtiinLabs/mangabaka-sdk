import Foundation

/// Response bodies shaped like MangaBaka's, built from the OpenAPI schemas and a live response.
internal enum Fixture {
    internal static func encode(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            preconditionFailure("Fixture is not valid JSON.")
        }
        return string
    }

    /// A lean series with every field the API documents.
    internal static func series(id: Int, type: String = "manga") -> [String: Any] {
        [
            "id": id,
            "state": "active",
            "merged_with": NSNull(),
            "canonical_url": "https://mangabaka.org/manga/\(id)/Frieren",
            "authors": ["Kanehito Yamada"],
            "artists": ["Tsukasa Abe"],
            "description": "An elf mage outlives her party.",
            "status": "releasing",
            "is_licensed": true,
            "content_rating": "safe",
            "type": type,
            "original_language": "ja",
            "rating": 87.045,
            "rating_count": 1520,
            "last_updated_at": "2026-10-19T00:26:15.355Z",
            "source": [
                "anilist": ["id": 118_586, "rating": 8.7, "rating_normalized": 87],
                "my_anime_list": ["id": 126_287, "rating": 8.86, "rating_normalized": 89],
                "kitsu": ["id": NSNull(), "rating": NSNull(), "rating_normalized": NSNull()],
                "manga_updates": ["id": "ugf5dzu", "rating": 8.59, "rating_normalized": 86],
                "anime_planet": ["id": "frieren-beyond-journeys-end", "rating": 4.4, "rating_normalized": 88],
                "anime_news_network": ["id": NSNull(), "rating": NSNull(), "rating_normalized": NSNull()],
                "shikimori": ["id": 126_287, "rating": NSNull(), "rating_normalized": NSNull()]
            ],
            "publishers": [
                ["id": 254, "name": "Devir", "canonical_url": "https://mangabaka.org/publisher/254/Devir", "language": "pt", "note": NSNull()]
            ],
            "final_volume": NSNull(),
            "total_chapters": 147,
            "cover": [
                "raw": "https://images.mangabaka.dev/raw",
                "x150": "https://cdn.mangabaka.dev/x150",
                "x250": "https://cdn.mangabaka.dev/x250",
                "x350": "https://cdn.mangabaka.dev/x350",
                "blurhash": "|PMHMir",
                "width": 1303,
                "height": 2048
            ],
            "anime": ["exists": true, "start": "Vol 1, Chap 1", "end": NSNull()],
            "published": ["start_date": "2020-04-28", "end_date": NSNull(), "start_date_is_estimated": false, "end_date_is_estimated": NSNull()],
            "titles": [
                ["language": "ja", "traits": ["native"], "title": "葬送のフリーレン", "is_primary": true],
                ["language": "en", "traits": [], "title": "Frieren at the Funeral", "is_primary": false],
                ["language": "en", "traits": ["official"], "title": "Frieren: Beyond Journey's End", "is_primary": true]
            ]
        ]
    }

    /// The fields only the `full` schema adds.
    internal static func fullSeries(id: Int) -> [String: Any] {
        var series = series(id: id)
        series["links"] = [
            ["id": "019d", "url": "https://websunday.net/work/708/", "name": "websunday.net", "name_display": "Shounen Sunday", "type": "info", "language": "ja"]
        ]
        series["tags"] = [
            [
                "id": 669, "is_spoiler": false, "is_genre": false, "is_explicit": false, "implied_by_tag_ids": [2],
                "parent_id": 1141, "name": "Cooking", "level": 3, "name_path": "Activities > Daily Life > Cooking",
                "series_count": 2698, "description": NSNull(), "content_rating": "safe", "weight": "unweighted"
            ]
        ]
        series["relationships"] = [
            [
                "id": "01a1", "to_series_id": 77_346, "relation_type": "parody", "is_manual": false,
                "note": NSNull(), "chronology": "unknown", "published_start_date": NSNull()
            ]
        ]
        return series
    }

    internal static func searchPage(ids: [Int], page: Int, limit: Int, count: Int) -> [String: Any] {
        let hasNext = page * limit < count
        return [
            "status": 200,
            "pagination": [
                "count": count,
                "page": page,
                "limit": limit,
                "next": hasNext ? "https://api.mangabaka.org/v2/series/search?page=\(page + 1)" as Any : NSNull(),
                "previous": page > 1 ? "https://api.mangabaka.org/v2/series/search?page=\(page - 1)" as Any : NSNull()
            ],
            "data": ids.map { series(id: $0) }
        ]
    }

    internal static func libraryEntry(seriesID: Int) -> [String: Any] {
        [
            "id": 9001,
            "series_id": seriesID,
            "user_id": "user-1",
            "state": "reading",
            "progress_chapter": 12.5,
            "progress_volume": 2,
            "rating": 80,
            "priority": 20,
            "is_private": false,
            "number_of_rereads": NSNull(),
            "note": NSNull(),
            "read_link": NSNull(),
            "start_date": "2024-01-02T00:00:00.000Z",
            "finish_date": NSNull()
        ]
    }

    internal static func error(status: Int, message: String, code: Any = NSNull()) -> [String: Any] {
        ["status": status, "message": message, "code": code]
    }
}
