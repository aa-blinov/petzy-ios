import Foundation
@testable import Petzy
import Testing
import UIKit

/// Лента разбирает записи по дням. Разбор дат и подписи вынесены отдельно,
/// чтобы их можно было проверить без приложения и без сети: именно здесь
/// чаще всего и ломается вид, а сеть тут ни при чём.
@Suite("Разбор ленты")
struct FeedTests {
    private func event(
        _ id: String,
        dateTime: String,
        type: String = "weight",
        isDeleted: Bool = false
    ) -> PetEvent {
        PetEvent(
            id: id,
            type: type,
            dateTime: dateTime,
            comment: "",
            fields: [:],
            isDeleted: isDeleted
        )
    }

    /// 18 октября 2026. Точка зафиксирована числами, а не константой эпохи:
    /// видно, какой именно день имеется в виду, и «сегодня» не поедет вместе
    /// с часами машины.
    private func referenceDay() -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 18
        // swiftlint:disable:next force_unwrapping
        return calendar.date(from: parts)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("Записи собираются по дням, порядок внутри дня не меняется")
    func groupsByDayKeepingOrder() {
        let days = Feed.group([
            event("a", dateTime: "2026-10-18 09:00"),
            event("b", dateTime: "2026-10-17 21:00"),
            event("c", dateTime: "2026-10-18 14:30"),
            event("d", dateTime: "2026-10-18 07:15")
        ])

        #expect(days.map(\.date) == ["2026-10-18", "2026-10-17"])
        #expect(days.first?.events.map(\.id) == ["a", "c", "d"])
        #expect(days.last?.events.count == 1)
    }

    @Test("Сегодня и вчера подписываются словами, остальное датой")
    func dayHeaderWords() {
        let today = calendar.startOfDay(for: referenceDay())

        #expect(Feed.dayHeader("2026-10-18", today: today, calendar: calendar) == "Сегодня")
        #expect(Feed.dayHeader("2026-10-17", today: today, calendar: calendar) == "Вчера")
        #expect(Feed.dayHeader("2026-10-15", today: today, calendar: calendar) == "15.10.2026")
    }

    @Test("Больше года назад тоже датой, а не словом")
    func oldDayStaysNumeric() {
        let today = calendar.startOfDay(for: referenceDay())

        #expect(Feed.dayHeader("2025-10-18", today: today, calendar: calendar) == "18.10.2025")
    }

    @Test("Запись типа, которого больше нет, в ленту не попадает")
    func unknownTypeIsHidden() {
        let days = Feed.group([
            event("a", dateTime: "2026-10-18 09:00"),
            event("b", dateTime: "2026-10-18 10:00", type: "удалённый_тип")
        ], knownTypes: ["weight"])

        #expect(days.count == 1)
        #expect(days.first?.events.map(\.id) == ["a"])
    }

    @Test("Удалённая запись не показывается")
    func deletedRecordIsHidden() {
        let days = Feed.group([
            event("a", dateTime: "2026-10-18 09:00"),
            event("b", dateTime: "2026-10-18 10:00", isDeleted: true)
        ], knownTypes: ["weight"])

        #expect(days.first?.events.map(\.id) == ["a"])
    }

    @Test("День и время достаются из date_time")
    func splitsDateAndTime() {
        let one = event("a", dateTime: "2026-10-18 14:30")

        #expect(one.day == "2026-10-18")
        #expect(one.time == "14:30")
    }

    @Test("Значение поля показывается и числом, и текстом")
    func fieldValuesRender() throws {
        #expect(try FieldValue.number(29.3).display == "29,3")
        #expect(try FieldValue.text("Монж Лабрадор").display == "Монж Лабрадор")
        // Хвост дробной части не показываем: вес 29,30 это тот же вес, что 29,3
        #expect(try FieldValue.number(29.30).display == "29,3")
    }
}

/// Значок типа приходит именем из набора веба, а не SF Symbol. На неизвестном
/// имени `Image(systemName:)` не рисует ничего и не сообщает об ошибке, поэтому
/// каждый перевод проверяем на существование: это единственный способ узнать
/// про пустоту, не глядя на экран.
@Suite("Значки типов записи")
struct EventIconTests {
    /// Все имена, которые сервер может прислать сейчас. Обновляется вместе с
    /// переводом в EventIcon.
    private let lucideNames = [
        "bone", "droplet", "ear", "eye", "gift", "heart", "paw", "scale",
        "shovel", "smile", "star", "sun", "thermometer", "toilet",
        "toothbrush", "utensils", "wind", "zap"
    ]

    @Test("Каждое переведённое имя есть в SF Symbols")
    func everyMappedSymbolExists() {
        for name in lucideNames {
            let symbol = EventIcon.symbol(for: name)
            #expect(UIImage(systemName: symbol) != nil, "в SF Symbols нет «\(symbol)» для «\(name)»")
        }
    }

    @Test("Неизвестное имя рисует значок-заглушку, а не пустоту")
    func unknownNameFallsBack() {
        let symbol = EventIcon.symbol(for: "выдуманный_значок")

        #expect(UIImage(systemName: symbol) != nil)
        #expect(EventIcon.symbol(for: nil) == symbol)
    }
}
