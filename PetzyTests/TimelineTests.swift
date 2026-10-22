import Foundation
@testable import Petzy
import Testing

/// Лента — это записи дневника и отмеченные приёмы лекарств одним списком, как
/// на вебе. Сервер отдаёт их одним ответом, поэтому и приложение разбирает их
/// вместе: два источника разошлись бы в порядке и в страницах.
@Suite("Лента: записи и приёмы")
struct TimelineTests {
    private func page(_ json: String) throws -> TimelinePage {
        try JSONDecoder().decode(TimelinePage.self, from: Data(json.utf8))
    }

    @Test("Запись и приём разбираются из одной страницы")
    func mixedPageDecodes() throws {
        let decoded = try page("""
        {"items": [
          {"_id": "a1", "record_type": "medications", "date_time": "2026-10-19T19:21:00+05:00",
           "medication_id": "m1", "medication_name": "Мелоксидил", "dose_taken": 2.5, "dose_unit": "мл",
           "skipped": false, "username": "demo", "comment": ""},
          {"_id": "e1", "record_type": "appetite", "date_time": "2026-10-18T13:01:00+05:00",
           "fields": {"level": "Сниженный"}, "comment": ""}
        ], "next_cursor": "2026-10-05T18:05:00,6ac3", "total": 342}
        """)

        #expect(decoded.items.count == 2)
        #expect(decoded.nextCursor == "2026-10-05T18:05:00,6ac3")

        let dose = try #require(decoded.items.first?.intake)
        #expect(dose.medicationName == "Мелоксидил")
        #expect(dose.dose == 2.5)
        #expect(dose.unit == "мл")
        #expect(dose.day == "2026-10-19")
        #expect(dose.time == "19:21")
        #expect(!dose.skipped)

        let record = try #require(decoded.items.last?.event)
        #expect(record.type == "appetite")
        #expect(record.day == "2026-10-18")
    }

    /// Пропущенный приём — не данный: путать их нельзя, и в ленте он подписан.
    @Test("Пропущенный приём виден")
    func skippedDoseIsMarked() throws {
        let decoded = try page("""
        {"items": [
          {"_id": "a1", "record_type": "medications", "date_time": "2026-10-19T19:21:00",
           "medication_id": "m1", "medication_name": "Дронтал", "dose_taken": 1, "skipped": true}
        ], "next_cursor": null}
        """)

        #expect(decoded.items.first?.intake?.skipped == true)
        #expect(decoded.nextCursor == nil)
    }

    /// У курса может не остаться единицы измерения, а доза останется: строка
    /// тогда показывает одно число, а не «2,5 » с пустотой.
    @Test("Без единицы измерения остаётся число")
    func doseWithoutUnit() throws {
        let decoded = try page("""
        {"items": [
          {"_id": "a1", "record_type": "medications", "date_time": "2026-10-19T19:21:00",
           "medication_id": "m1", "medication_name": "Дронтал", "dose_taken": 1}
        ]}
        """)

        let dose = try #require(decoded.items.first?.intake)
        #expect(dose.unit == nil)
        #expect(dose.doseText == "1")
    }

    /// Идентификаторы записи и приёма приходят из разных коллекций, и списку
    /// нужны разные: одинаковый id в `ForEach` путает строки.
    @Test("Идентификаторы видов различаются")
    func identifiersAreNamespaced() throws {
        let decoded = try page("""
        {"items": [
          {"_id": "same", "record_type": "medications", "date_time": "2026-10-19T19:21:00",
           "medication_id": "m1", "medication_name": "Мелоксидил", "dose_taken": 1},
          {"_id": "same", "record_type": "appetite", "date_time": "2026-10-19T13:00:00", "fields": {}}
        ]}
        """)

        let ids = decoded.items.map(\.id)
        #expect(Set(ids).count == 2)
    }

    @Test("Дни собираются из обоих видов и хранят порядок сервера")
    func daysMixBothKinds() throws {
        let decoded = try page("""
        {"items": [
          {"_id": "a1", "record_type": "medications", "date_time": "2026-10-19T19:21:00",
           "medication_id": "m1", "medication_name": "Мелоксидил", "dose_taken": 2.5},
          {"_id": "e1", "record_type": "appetite", "date_time": "2026-10-19T13:01:00", "fields": {}},
          {"_id": "e2", "record_type": "weight", "date_time": "2026-10-18T11:00:00", "fields": {}}
        ]}
        """)

        let days = Feed.group(decoded.items)
        #expect(days.map(\.date) == ["2026-10-19", "2026-10-18"])
        #expect(days.first?.items.count == 2)
        #expect(days.first?.items.first?.intake?.medicationName == "Мелоксидил")
    }
}
