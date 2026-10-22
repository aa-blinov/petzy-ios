import Foundation

/// Разбор `date_time` в двух форматах, которые отдаёт сервер: «2026-10-04
/// 11:00» и «2026-10-18T14:13:00+05:00». Время остаётся тем, что человек ввёл
/// у себя: перевод в часовой пояс телефона увёл бы кормление с 11 утра на 6.
///
/// Вынесено отдельно, потому что тот же разбор нужен и записи ленты, и
/// точке графика, а расходиться они не должны.
enum MomentText {
    static func day(of text: String) -> String {
        String(text.prefix { $0 != " " && $0 != "T" })
    }

    /// День по-русски: «Сегодня», «Вчера» или «04.10.2026». На входе именно
    /// день `ГГГГ-ММ-ДД`, а не полный момент: полный ISO разбирать здесь нечем,
    /// и «Сегодня» превратилось бы в мусор вида «06T08:43:00+05:00.10.2026».
    static func humanDay(_ text: String, today: Date = .now, calendar: Calendar = .current) -> String {
        // Тут тоже терпится полный момент: «Сегодня» и «Вчера» решаются по
        // дню, а не по времени.
        let day = day(of: text)
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        let start = calendar.startOfDay(for: today)
        if day == isoDay(start, calendar: calendar) {
            return "Сегодня"
        }
        // Условие в одну строку: многострочный `if let` swiftformat раскрывает
        // скобкой на новой строке, а swiftlint это запрещает.
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: start), day == isoDay(
            yesterday,
            calendar: calendar
        ) {
            return "Вчера"
        }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    /// `2026-10-01` в `01.10.2026`. Дата приходит строкой и в таком виде
    /// не переводится в Date: смена часового пояса тут ни при чём.
    ///
    /// Полный момент тоже принимается: сервер отдаёт `created_at` как
    /// `2026-10-03T07:52:47Z`, и без этого «03T07:52:47Z.10.2026» уезжало на
    /// экран. День берётся оттуда же, где его берут все остальные.
    static func russianDay(_ iso: String) -> String {
        let parts = day(of: iso).split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `2021-08-01` в Date, для ползунка даты. Обратный ход к `isoDay`; в
    /// приложении разбор даты больше не размазан по экранам.
    static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func time(of text: String) -> String {
        // Отрезаем секунды и смещение: «14:13:00+05:00» это «14:13».
        let tail = text.contains("T")
            ? String(text.split(separator: "T").last ?? "")
            : String(text.split(separator: " ").last ?? "")
        return String(tail.prefix(5))
    }
}
