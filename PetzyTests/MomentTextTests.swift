import Foundation
@testable import Petzy
import Testing

/// Даты приходят с сервера двумя видами: днём `2026-10-03` и полным моментом
/// `2026-10-03T07:52:47Z`. Разбор дня терпит оба: иначе на экран уезжает
/// «03T07:52:47Z.10.2026», и это уже случалось.
@Suite("Даты словами")
struct MomentTextTests {
    @Test("День приводится к русскому виду")
    func dayIsRussian() {
        #expect(MomentText.russianDay("2026-10-03") == "03.10.2026")
    }

    @Test("Полный момент тоже даёт день")
    func momentGivesDay() {
        #expect(MomentText.russianDay("2026-10-03T07:52:47Z") == "03.10.2026")
        #expect(MomentText.russianDay("2026-10-03 07:52") == "03.10.2026")
    }

    @Test("Человеческий день не путается на моменте")
    func humanDayAcceptsMoment() {
        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3)) ?? .now

        #expect(MomentText.humanDay("2026-10-03T07:52:47Z", today: today, calendar: calendar) == "Сегодня")
    }

    /// Время остаётся тем, что записал человек: перевод в пояс телефона увёл бы
    /// кормление с 11 утра на 6.
    @Test("Время не переводится в другой пояс")
    func timeKeepsItsOffset() {
        #expect(MomentText.time(of: "2026-10-18T14:13:00+05:00") == "14:13")
        #expect(MomentText.time(of: "2026-10-04 11:00") == "11:00")
    }
}
