import Foundation

/// Один день ленты: заголовок и записи этого дня.
struct EventDay: Identifiable {
    let date: String
    let events: [PetEvent]

    var id: String {
        date
    }
}

/// Разбор ленты: что показать и как подписать.
enum Feed {
    /// Раскладывает записи по дням, сохраняя порядок внутри дня. Порядок дней
    /// задаёт сервер, новыми группами сортировать нельзя: сервер уже отдал
    /// самое свежее сверху, и перестановка это бы сломала.
    ///
    /// Пустой `knownTypes` означает «ничего не фильтровать»: тесты разбора
    /// работают без справочника типов, а приложение всегда его передаёт.
    static func group(_ events: [PetEvent], knownTypes: Set<String> = []) -> [EventDay] {
        var order: [String] = []
        var buckets: [String: [PetEvent]] = [:]
        for event in events {
            guard !event.isDeleted else { continue }
            if !knownTypes.isEmpty, !knownTypes.contains(event.type) {
                continue
            }
            if buckets[event.day] == nil {
                order.append(event.day)
            }
            buckets[event.day, default: []].append(event)
        }
        return order.map { EventDay(date: $0, events: buckets[$0] ?? []) }
    }

    /// Подпись дня: «Сегодня», «Вчера» или дата. Словами только два ближайших
    /// дня, дальше дата в привычном виде «15.10.2026».
    static func dayHeader(_ date: String, today: Date, calendar: Calendar) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }

        let start = calendar.startOfDay(for: today)
        if date == isoDay(start, calendar: calendar) {
            return "Сегодня"
        }
        // Условие в одну строку: многострочный `if let` swiftformat раскрывает
        // скобкой на новой строке, а swiftlint это запрещает.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)
        if let yesterday, date == isoDay(yesterday, calendar: calendar) {
            return "Вчера"
        }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    /// Дата в том же виде, в каком её присылает сервер, чтобы сравнение строк
    /// не зависело от локали устройства.
    private static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
