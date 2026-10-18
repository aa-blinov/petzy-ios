import Foundation
@testable import Petzy
import Testing

/// Место человека в ленте: догруженные страницы не теряются после
/// перечитывания, а запись с датой в прошлом после сохранения не исчезает
/// молча. Сюита по очереди: заготовки ответов у всех тестов общие, и параллельно
/// они забирали бы друг другу ответы.
@MainActor
@Suite("Лента: место и сохранённая запись", .serialized)
struct FeedPlaceTests {
    private func stubEvent(_ id: String, dateTime: String) -> [String: Any] {
        ["_id": id, "type": "weight", "date_time": dateTime, "comment": "", "fields": ["weight": 29.3]]
    }

    /// После сохранения лента читается заново первой страницей, и человек
    /// теряет место, до которого дочитал: страницы приходилось догружать
    /// заново.
    @Test("Догруженные страницы возвращаются после перечитывания ленты")
    func keepsLoadedDepth() async {
        StubURLProtocol.reset()
        stubTwoPageFeed()
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")
        await model.loadFeed()
        await model.loadMore()
        #expect(model.days.flatMap(\.events).count == 2)

        // Лента читается заново, и на этот раз сервер отвечает на всё, что
        // приложение запросит: заготовок ровно шесть запросов.
        stubTwoPageFeed()
        await model.loadFeed()

        #expect(model.days.flatMap(\.events).count == 2, "догруженная страница потерялась")
        #expect(
            pages(of: "pet-1", before: "cur-1") == 2,
            "вторую страницу прочитали \(pages(of: "pet-1", before: "cur-1")) раз, а не два"
        )
    }

    /// Глубина принадлежит питомцу: у другого питомца своей второй страницы
    /// может не быть, и догруженная чужая страница встала бы в его ленту.
    @Test("Смена питомца сбрасывает глубину догрузки")
    func petSwitchResetsDepth() async {
        StubURLProtocol.reset()
        stubTwoPageFeed()
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")
        await model.loadFeed()
        await model.loadMore()

        model.select(petID: "pet-2")
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e3", dateTime: "2026-10-16 09:00")],
            "next_cursor": "cur-2"
        ])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e4", dateTime: "2026-10-15 09:00")],
            "next_cursor": nil
        ])
        await model.loadFeed()

        #expect(read(of: "pet-2"), "лента второго питомца вообще не читалась")
        #expect(
            pages(of: "pet-2", before: "cur-2") == 0,
            "у второго питомца догрузили чужую страницу"
        )
    }

    /// Запись попала в загруженную часть ленты: человек её видит, и лишнее
    /// сообщение «где она» ему не нужно.
    @Test("Сохранённая запись, которая есть в ленте, не тревожит уведомлением")
    func savedEventInLoadedFeedStaysQuiet() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["message": "Запись сохранена", "id": "e1"])
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": nil
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.createEvent(weightDraft())

        #expect(model.feedNotice == nil)
    }

    /// Запись с датой в прошлом лежит на своей странице, и в загруженной её
    /// нет. Молчание читается как «не сохранилось», поэтому говорим словами,
    /// за какой день запись.
    @Test("Запись, которой нет в загруженной ленте, сообщает свою дату")
    func savedEventOutOfLoadedPagesReportsItsDay() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["message": "Запись сохранена", "id": "e-old"])
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": nil
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.createEvent(weightDraft(date: "2026-10-05"))

        #expect(model.feedNotice == "Она за 05.10.2026, в ленте до неё надо долистать")
    }

    /// Сколько раз читалась страница ленты по этому курсору. Считаем по курсору
    /// и питомцу, а не по всему списку запросов: список общий на весь прогон,
    /// и чужие запросы из других сюит в него попадают.
    private func pages(of petID: String, before cursor: String) -> Int {
        StubURLProtocol.requests.filter { request in
            guard let url = request.url, url.path == "/api/events", let query = url.query else { return false }
            return query.contains("pet_id=\(petID)") && query.contains("before=\(cursor)")
        }.count
    }

    /// Читалась ли вообще лента этого питомца: иначе проверка «лишних страниц
    /// нет» прошла бы, не проверив ничего.
    private func read(of petID: String) -> Bool {
        StubURLProtocol.requests.contains { request in
            guard let url = request.url, url.path == "/api/events" else { return false }
            return url.query?.contains("pet_id=\(petID)") == true
        }
    }

    /// Справочник типов и две страницы ленты: первая со стрелкой курсора,
    /// вторая без неё.
    private func stubTwoPageFeed() {
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": "cur-1"
        ])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e2", dateTime: "2026-10-17 09:00")],
            "next_cursor": nil
        ])
    }

    private func weightDraft(date: String = "2026-10-18") -> EventDraft {
        EventDraft(
            type: EventTypeInfo(key: "weight", label: "Вес", icon: "scale", category: "health", fields: [
                EventFieldInfo(
                    name: "weight", label: "Вес (кг)", type: "number",
                    required: true, min: 0, max: 100, options: nil
                )
            ], chart: nil),
            values: ["weight": "29,3"],
            comment: "после прогулки",
            date: date,
            time: "12:00"
        )
    }
}
