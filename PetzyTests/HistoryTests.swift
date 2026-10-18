import Foundation
@testable import Petzy
import Testing

/// История записей. Здесь две разные схемы ответа и расчёт корзин графика:
/// сервер отдаёт тип записи в поле `record_type`, а не в `type`, как лента, и
/// для длинного периода дни складываются в недели и месяцы.
@Suite("История записей")
struct HistoryTests {
    /// Таймлайн и лента отдают один и тот же список записей, но называют тип
    /// по-разному. Без второго имени записи истории выглядели бы как записи
    /// неизвестного типа и молча пропали бы из списка.
    @Test("Запись таймлайна разбирается по полю record_type")
    func timelineItemParses() throws {
        let json = """
        {"_id": "e1", "record_type": "weight", "date_time": "2026-10-04 11:00", "fields": {"weight": 29.3}}
        """

        let event = try JSONDecoder().decode(PetEvent.self, from: Data(json.utf8))

        #expect(event.type == "weight")
        #expect(event.day == "2026-10-04")
        #expect(event.time == "11:00")
    }

    @Test("Лента разбирается по-прежнему")
    func feedItemParses() throws {
        let json = """
        {"_id": "e1", "type": "weight", "date_time": "2026-10-04 11:00"}
        """

        let event = try JSONDecoder().decode(PetEvent.self, from: Data(json.utf8))

        #expect(event.type == "weight")
    }

    /// Записи, у которых приложение само отправило часовой пояс, приходят в
    /// ISO с ним: «2026-10-18T14:13:00+05:00». Старые лежат без часового
    /// пояса, «2026-10-04 11:00». Разбор обязан брать оба.
    @Test("Запись с часовым поясом разбирается и показывает время человека")
    func isoDateTimeParses() throws {
        let json = """
        {"_id": "e1", "type": "weight", "date_time": "2026-10-18T14:13:00+05:00"}
        """

        let event = try JSONDecoder().decode(PetEvent.self, from: Data(json.utf8))

        #expect(event.day == "2026-10-18")
        #expect(event.time == "14:13", "время переехало в часовой пояс телефона: \(event.time)")
    }

    @Test("Старый формат даты разбирается так же")
    func plainDateTimeParses() throws {
        let json = """
        {"_id": "e1", "type": "weight", "date_time": "2026-10-04 11:00"}
        """

        let event = try JSONDecoder().decode(PetEvent.self, from: Data(json.utf8))

        #expect(event.day == "2026-10-04")
        #expect(event.time == "11:00")
    }

    /// То же для точек графика: они приходят с тем же форматом.
    @Test("Точка графика разбирается в обоих форматах")
    func statsPointParsesBothFormats() {
        let iso = EventStatsPoint(date: "2026-10-18T14:13:00+05:00", value: 29.3)
        let plain = EventStatsPoint(date: "2026-10-04 11:00", value: 29.1)

        #expect(iso.day == "2026-10-18")
        #expect(iso.time == "14:13")
        #expect(plain.day == "2026-10-04")
        #expect(plain.time == "11:00")
    }

    private func point(_ date: String, _ value: Double) -> EventStatsPoint {
        EventStatsPoint(date: date, value: value)
    }

    /// Человек смотрит на месяц и видит тридцать точек. График в 300 точках на
    /// телефоне не читается, поэтому дни складываются в корзины, и вид
    /// корзины зависит от длины периода, а не от числа записей.
    @Test("Длинный период сворачивается в недели и месяцы")
    func granularityGrowsWithPeriod() {
        #expect(EventStats.granularity(days: 30) == .day)
        #expect(EventStats.granularity(days: 60) == .day)
        #expect(EventStats.granularity(days: 90) == .week)
        #expect(EventStats.granularity(days: 365) == .week)
        #expect(EventStats.granularity(days: 730) == .month)
    }

    /// Средний вес за день, а не сумма: два взвешивания утром и вечером не
    /// должны читаться как «за день набрали два килограмма».
    @Test("Корзина за день усредняет значения")
    func dayBucketAverages() {
        let points = [
            point("2026-10-04 09:00", 29.2),
            point("2026-10-04 19:00", 29.4)
        ]

        let buckets = EventStats.buckets(points, granularity: .day, averaged: true)

        #expect(buckets.count == 1)
        #expect(buckets.first?.value == 29.3)
    }

    /// Для счётных типов, у которых нет величины, корзина складывает: сколько
    /// раз за неделю мерили температуру.
    @Test("Корзина счётного типа складывает значения")
    func weekBucketSumsCounts() {
        let points = [
            point("2026-10-05 09:00", 1),
            point("2026-10-07 09:00", 1),
            point("2026-10-08 09:00", 1)
        ]

        let buckets = EventStats.buckets(points, granularity: .week, averaged: false)

        #expect(buckets.count == 1)
        #expect(buckets.first?.value == 3)
    }

    /// Корзины идут по времени, и в подписи видно, за что отвечает точка:
    /// день, неделя или месяц.
    @Test("Корзины разложены по времени и подписаны по-русски")
    func bucketsAreSortedAndLabelled() {
        let points = [
            point("2026-10-08 09:00", 29.5),
            point("2026-09-15 09:00", 28.5)
        ]

        let days = EventStats.buckets(points, granularity: .day, averaged: true)
        let weeks = EventStats.buckets(points, granularity: .week, averaged: true)
        let months = EventStats.buckets(points, granularity: .month, averaged: true)

        #expect(days.map(\.label) == ["15.09", "08.10"])
        #expect(weeks.count == 2, "15 и 8 октября это разные недели")
        #expect(months.map(\.label) == ["сентябрь", "октябрь"])
    }

    @Test("Пустые точки не дают пустого графика")
    func noPointsNoBuckets() {
        #expect(EventStats.buckets([], granularity: .day, averaged: true).isEmpty)
    }

    /// Шкала от нуля убивает тренд: кот, который поправился с 4,2 до 4,5 кг,
    /// на шкале 0–5 рисуется прямой линией у самого верха, и изменение, ради
    /// которого человек и смотрит график, это несколько пикселей. Ось
    /// подгоняется под сами значения, с воздухом вокруг них и круглыми
    /// границами, но не уходит ниже нуля: вес и температура отрицательными
    /// не бывают.
    @Test("Шкала подгоняется под значения, а не начинается с нуля")
    func scaleFitsValues() throws {
        let scale = try #require(EventStats.valueScale([28.4, 29.3]))

        #expect(scale.lower <= 28.4, "первая точка оказалась за нижней границей: \(scale)")
        #expect(scale.upper >= 29.3, "последняя точка оказалась за верхней границей: \(scale)")
        #expect(scale.lower >= 0, "шкала ушла в отрицательные веса: \(scale)")
        #expect(scale.upper - scale.lower < 5, "шкала растянулась почти на всю ось: \(scale)")
    }

    @Test("Одно значение без разброса всё равно даёт полосу, а не высоту в ноль")
    func scaleSurvivesSingleValue() throws {
        let scale = try #require(EventStats.valueScale([4.9]))

        #expect(scale.upper > scale.lower, "высота нулевая, график нечем рисовать: \(scale)")
        #expect(scale.lower <= 4.9)
        #expect(scale.upper >= 4.9)
    }

    @Test("Без точек шкалы нет")
    func scaleNeedsValues() {
        #expect(EventStats.valueScale([]) == nil)
    }
}
