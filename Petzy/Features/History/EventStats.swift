import Foundation

/// Одна точка графика: когда и сколько. Дата приходит тем же форматом, что и
/// в ленте: у записей с часовым поясом ISO с ним, у старых без него.
struct EventStatsPoint: Decodable, Sendable, Equatable {
    let date: String
    let value: Double

    /// Дата без времени, как её присылает сервер: `yyyy-MM-dd`.
    var day: String {
        MomentText.day(of: date)
    }

    var time: String {
        MomentText.time(of: date)
    }
}

struct EventStatsResponse: Decodable, Sendable {
    let data: [EventStatsPoint]
}

/// Корзина графика: несколько записей, сведённых в одну точку.
struct EventStatsBucket: Identifiable, Equatable {
    /// Начало корзины в виде `yyyy-MM-dd`: сортировать и сравнивать удобнее
    /// датами, а не подписями.
    let start: String
    let label: String
    let value: Double

    var id: String {
        start
    }
}

/// Границы шкалы величины, подогнанные под сами значения.
struct ValueScale: Equatable {
    let lower: Double
    let upper: Double
}

/// Разбор статистики для графика.
enum EventStats {
    /// Шкала по величине под самые значения. От нуля тренд не читается: кот,
    /// который поправился с 4,2 до 4,5 кг, на шкале 0–5 рисуется прямой
    /// линией у самого верха, и изменение, ради которого и смотрят график,
    /// это несколько пикселей. Границы круглые, с воздухом вокруг данных, и
    /// не ниже нуля: вес и температура отрицательными не бывают.
    static func valueScale(_ values: [Double]) -> ValueScale? {
        guard let low = values.min(), let high = values.max() else { return nil }
        let span = high - low
        let pad = span > 0 ? span * 0.15 : max(abs(high) * 0.05, 0.5)
        let step = niceStep(span + 2 * pad)
        var bottom = ((low - pad) / step).rounded(.down) * step
        if low >= 0, bottom < 0 {
            bottom = 0
        }
        let top = ((high + pad) / step).rounded(.up) * step
        return ValueScale(lower: bottom, upper: top)
    }

    /// Шаг около четырёх промежутков: 1, 2 или 5 умноженные на степень десяти,
    /// чтобы границы и деления были круглыми числами, а не 28,4371.
    private static func niceStep(_ span: Double) -> Double {
        let raw = span / 4
        guard raw > 0 else { return 1 }
        let power = pow(10, log10(raw).rounded(.down))
        let scaled = raw / power
        let nice = scaled <= 1 ? 1.0 : scaled <= 2 ? 2.0 : scaled <= 5 ? 5.0 : 10.0
        return nice * power
    }

    enum Granularity: Equatable {
        case day
        case week
        case month
    }

    /// На месяц показывают по дню, на год по неделе, дальше по месяцу: три
    /// сотни столбиков на телефоне не читаются, а одна точка на весь год не
    /// говорит ни о чём.
    static func granularity(days: Int) -> Granularity {
        if days <= 60 {
            return .day
        }
        if days <= 366 {
            return .week
        }
        return .month
    }

    /// Точки, сведённые в корзины по времени. Для типа, у которого есть
    /// величина, корзина усредняет: два взвешивания утром и вечером не должны
    /// читаться как «за день набрали два килограмма». Для счётного типа, у
    /// которого величины нет, корзина складывает: сколько раз за неделю
    /// мерили температуру.
    static func buckets(
        _ points: [EventStatsPoint],
        granularity: Granularity,
        averaged: Bool
    ) -> [EventStatsBucket] {
        var order: [String] = []
        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var starts: [String: String] = [:]

        for point in points {
            guard let key = key(point.day, granularity: granularity) else { continue }
            if sums[key] == nil {
                order.append(key)
                starts[key] = point.day
            }
            sums[key, default: 0] += point.value
            counts[key, default: 0] += 1
        }

        return order.sorted().map { key in
            let total = sums[key] ?? 0
            let count = counts[key] ?? 1
            return EventStatsBucket(
                start: starts[key] ?? key,
                label: label(for: starts[key] ?? key, granularity: granularity),
                value: averaged ? (total / Double(count) * 10).rounded() / 10 : total
            )
        }
    }

    /// Ключ корзины. Для недели это понедельник недели: так неделя одна и та же
    /// с обеих сторон, а не «первые семь дней от начала периода».
    private static func key(_ day: String, granularity: Granularity) -> String? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let calendar = Calendar.current
        switch granularity {
        case .day:
            return day
        case .week:
            // Неделя в России начинается с понедельника.
            let weekday = calendar.component(.weekday, from: date)
            let monday = calendar.date(byAdding: .day, value: 1 - weekday, to: date) ?? date
            return MomentText.isoDay(monday, calendar: calendar)
        case .month:
            return String(format: "%04d-%02d", parts[0], parts[1])
        }
    }

    private static func label(for day: String, granularity: Granularity) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        switch granularity {
        case .day:
            return String(format: "%02d.%02d", parts[2], parts[1])
        case .week:
            return String(format: "%02d.%02d", parts[2], parts[1])
        case .month:
            return monthNames[min(max(parts[1] - 1, 0), monthNames.count - 1)]
        }
    }

    /// Названия месяцев пишутся руками: `DateFormatter` на устройстве без
    /// русского языка вернёт «October», а интерфейс у приложения русский.
    private static let monthNames = [
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"
    ]

    /// «3 записи», «5 записей»: число само по себе не читается по-русски.
    static func pluralRecords(_ count: Int) -> String {
        let tail = abs(count) % 100
        if (11 ... 14).contains(tail) {
            return "записей"
        }
        switch abs(count) % 10 {
        case 1: return "запись"
        case 2 ... 4: return "записи"
        default: return "записей"
        }
    }

    /// Словами о том, что график вообще говорит: картинка тренда не читается
    /// как чтение, а «с 28,4 до 29,3, плюс 0,9» читается.
    static func trendSummary(_ buckets: [EventStatsBucket], isValued: Bool) -> String {
        guard let first = buckets.first, let last = buckets.last else { return "" }
        guard isValued else {
            let total = buckets.reduce(0) { $0 + $1.value }
            return "За период: \(Int(total)) \(pluralRecords(Int(total)))"
        }
        let change = last.value - first.value
        // Ровно ноль изменений: «плюс 0,00» не говорит ничего, а человек
        // решил бы, что график сломан.
        if abs(change) < 0.005 {
            return "За период: без изменений"
        }
        let word = change >= 0 ? "плюс" : "минус"
        // Знаков столько, сколько в самом изменении: округлённое до одного
        // «плюс 0» не объясняет ничего.
        let decimals = max(1, min(3, -Int(floor(log10(max(abs(change), 0.01))))))
        let changeFormat = "%.\(decimals)f"
        // Уровни — с одним знаком, как на оси: «250,0» и «250,00» рядом с
        // подписью читаются как разные числа.
        return String(
            format: "За период: с %.1f до %.1f, " + word + " " + changeFormat,
            first.value, last.value, abs(change)
        ).replacingOccurrences(of: ".", with: ",")
    }
}
