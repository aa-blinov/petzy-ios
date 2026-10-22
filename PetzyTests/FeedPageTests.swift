import Foundation
@testable import Petzy
import Testing

/// Страницы ленты: из чего они состоят и как читаются дальше.
@MainActor
@Suite("Страницы ленты")
struct FeedPageTests {
    private func stubEvent(_ id: String, dateTime: String) -> [String: Any] {
        ["_id": id, "type": "weight", "date_time": dateTime, "comment": "", "fields": ["weight": 29.3]]
    }

    /// Надгробия удалённых записей не должны занимать место в странице. Из
    /// ста записей, попавших на одну страницу, на показ оставалась одна, а
    /// лента выглядела пустой: человек листал её и ничего не находил.
    @Test("Лента читается без надгробий: страница из живых записей")
    func feedPageHasNoTombstones() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "event_types": [["key": "weight", "label": "Вес", "fields": []]]
        ])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": "cur-1"
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.loadFeed()

        let query = StubURLProtocol.requests.first { $0.url?.path == "/api/history/timeline" }?.url?.query ?? ""
        #expect(!query.contains("with_deleted"), "страница ленты читается с надгробиями: \(query)")
    }

    /// Лента догружается сама, когда человек дошёл до конца, и строка внизу
    /// может появиться снова. Две догрузки, начатые одна за другой, взяли бы
    /// одну страницу дважды, и записи показались бы в ленте дважды.
    @Test("Две догрузки подряд не читают страницу дважды")
    func concurrentLoadMoreReadsOnePage() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "event_types": [["key": "weight", "label": "Вес", "fields": []]]
        ])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": "cur-1"
        ])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e2", dateTime: "2026-10-17 09:00")],
            "next_cursor": nil
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")
        await model.loadFeed()

        async let first = model.loadMore()
        async let second = model.loadMore()
        _ = await (first, second)

        let pages = StubURLProtocol.requests.filter {
            $0.url?.path == "/api/history/timeline" && $0.url?.query?.contains("before=") == true
        }
        #expect(pages.count == 1, "страница прочитана \(pages.count) раз")
        #expect(model.days.flatMap(\.items).compactMap(\.event).count == 2, "записи показались дважды")
    }
}
