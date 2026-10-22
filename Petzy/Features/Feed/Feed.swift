import Foundation

/// Один день ленты: заголовок и всё, что в нём есть, — записи и приёмы.
struct FeedDay: Identifiable {
    let date: String
    let items: [FeedItem]

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
    static func group(_ items: [FeedItem], knownTypes: Set<String> = []) -> [FeedDay] {
        var order: [String] = []
        var buckets: [String: [FeedItem]] = [:]
        for item in items {
            // Приём — факт дневника, а не запись типа: справочник типов его не
            // касается, и фильтр «типы, которые ещё есть» его не выбрасывает.
            if let event = item.event {
                guard !event.isDeleted else { continue }
                if !knownTypes.isEmpty, !knownTypes.contains(event.type) {
                    continue
                }
            }
            if buckets[item.day] == nil {
                order.append(item.day)
            }
            buckets[item.day, default: []].append(item)
        }
        return order.map { FeedDay(date: $0, items: buckets[$0] ?? []) }
    }

    /// Подпись дня: «Сегодня», «Вчера» или дата. Словами только два ближайших
    /// дня, дальше дата в привычном виде «15.10.2026».
    static func dayHeader(_ date: String, today: Date, calendar: Calendar) -> String {
        MomentText.humanDay(date, today: today, calendar: calendar)
    }

    // Дата в том же виде, в каком её присылает сервер, чтобы сравнение строк
    // не зависело от локали устройства.
}
