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
        MomentText.humanDay(date, today: today, calendar: calendar)
    }

    // Дата в том же виде, в каком её присылает сервер, чтобы сравнение строк
    // не зависело от локали устройства.
}
