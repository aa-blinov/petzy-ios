import Foundation

/// Страница общей ленты: записи дневника и приёмы лекарств вместе. Читается по
/// курсору, как и лента записей: новая запись не сдвигает страницу, поэтому ни
/// одна не читается дважды и ни одна не теряется.
struct TimelinePage: Decodable, Sendable {
    let items: [FeedItem]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

enum HistoryAPI {
    static func timeline(
        _ client: APIClient,
        petID: String,
        before: String? = nil,
        pageSize: Int = 100
    ) async throws -> TimelinePage {
        var path = "/api/history/timeline?page_size=\(pageSize)&pet_id=" + AppModel.query(petID)
        if let before {
            path += "&before=" + AppModel.query(before)
        }
        return try await client.get(path, as: TimelinePage.self)
    }
}
