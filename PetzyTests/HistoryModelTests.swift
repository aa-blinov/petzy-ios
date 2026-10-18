import Foundation
@testable import Petzy
import Testing

/// История: свой маршрут, фильтр по типу и график. Логика разбора корзин
/// графика держится в `HistoryTests`, здесь проверяется только проводка.
@MainActor
@Suite("История")
struct HistoryModelTests {
    private func stubTimeline(_ items: [[String: Any]], cursor: String? = nil) {
        StubURLProtocol.stub(status: 200, json: ["items": items, "next_cursor": cursor])
    }

    /// История читается своим маршрутом и с фильтром по типу, который уходит
    /// на сервер. Фильтр на устройстве видел бы только текущую страницу:
    /// редкий тип рядом с частым читался бы пустым, пока не наберёшь «Ещё».
    @Test("История с фильтром уходит на сервер и группируется по дням")
    func historyGoesToServerWithType() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["types": ["weight", "feeding"]])
        TestSupport.stubTypeReference()
        stubTimeline([
            ["_id": "e1", "record_type": "weight", "date_time": "2026-10-04 11:00",
             "fields": ["weight": 29.3]],
            ["_id": "e2", "record_type": "weight", "date_time": "2026-10-03 09:00",
             "fields": ["weight": 29.1]]
        ])
        // Выбран тип — за ним тянется и график, отдельным запросом.
        StubURLProtocol.stub(status: 200, json: ["data": [["date": "2026-10-04 11:00", "value": 29.3]]])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.loadHistory(type: "weight")

        #expect(
            StubURLProtocol.requestedPaths == ["/api/events/used-types", "/api/event-types", "/api/history/timeline",
                                               "/api/stats/health"],
            "история пошла не туда: \(StubURLProtocol.requestedPaths)"
        )
        let query = StubURLProtocol.requests.last?.url?.query ?? ""
        #expect(query.contains("type=weight"), "фильтр не ушёл на сервер: \(query)")
        #expect(model.usedTypes == ["weight", "feeding"], "фильтр без типов питомца пустой: \(model.usedTypes)")
        #expect(model.historyDays.map(\.date) == ["2026-10-04", "2026-10-03"])
        #expect(model.historyDays.flatMap(\.events).count == 2)
        #expect(model.historyErrorText == nil)
    }

    /// «Все» — это отсутствие фильтра, а не отдельный тип: пустой параметр
    /// серверу не отправляется, а в адрес попадает как «все».
    @Test("Фильтр «Все» уходит без типа")
    func historyWithoutFilterHasNoType() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["types": ["weight"]])
        TestSupport.stubTypeReference()
        stubTimeline([])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.loadHistory(type: nil)

        let query = StubURLProtocol.requests.last?.url?.query ?? ""
        #expect(!query.contains("type="), "фильтр «Все» ушёл как тип: \(query)")
    }

    /// График отдельно от списка: у него свой маршрут и своя длина периода.
    @Test("График спрашивается по своему маршруту с выбранным периодом")
    func statsAreLoadedForPeriod() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["data": [
            ["date": "2026-10-04 11:00", "value": 29.3],
            ["date": "2026-09-15 09:00", "value": 28.8]
        ]])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.loadStats(type: "weight", days: 90)

        #expect(StubURLProtocol.requestedPaths == ["/api/stats/health"])
        let query = StubURLProtocol.requests.last?.url?.query ?? ""
        #expect(query.contains("type=weight"), "график пошёл не по тому типу: \(query)")
        #expect(query.contains("days=90"), "период не ушёл на сервер: \(query)")
        #expect(model.statsBuckets.count == 2, "корзины не собраны: \(model.statsBuckets)")
        #expect(model.statsBuckets.map(\.value) == [28.8, 29.3])
    }

    /// У типа записи бывает вид графика: по величине, как у веса, и по
    /// количеству, как у прививок. Без него среднее показывалось бы там,
    /// где нужен счёт, и наоборот.
    @Test("Вид графика берётся из описания типа")
    func chartKindComesFromType() {
        let value = EventTypeInfo(
            key: "weight", label: "Вес", icon: "scale", category: "health",
            fields: [], chart: EventChart(kind: "value", valueField: "weight", valueLabel: "Вес (кг)")
        )
        let count = EventTypeInfo(
            key: "cough", label: "Кашель", icon: "wind", category: "health",
            fields: [], chart: EventChart(kind: "count", valueField: nil, valueLabel: nil)
        )

        #expect(value.chart?.kind == "value")
        #expect(count.chart?.kind == "count")
    }
}
