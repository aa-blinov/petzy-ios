import Foundation

/// Ссылка на медкарту для врача. Токен сервер показывает один раз и больше
/// не хранит, поэтому адрес надо сохранить сразу.
struct MedicalShare: Sendable {
    let id: String
    let token: String
    /// Готовый адрес: открыт без входа, поэтому поделиться им можно сразу.
    let url: URL?
    let expiresAt: String?
}

/// Уже выданная ссылка. Секрет из неё не вернуть: сервер хранит только хэш,
/// поэтому список показывает, до какого дня ссылка открывает карту, а не её
/// саму.
struct LiveShare: Identifiable, Sendable {
    let id: String
    let expiresAt: String?

    /// «Откроется до 25.10.2026». Без даты окончания сервер не отдаёт, и
    /// выдумывать срок нельзя.
    var expiresText: String? {
        guard let expiresAt else { return nil }
        return "Откроется до \(MomentText.russianDay(MomentText.day(of: expiresAt)))"
    }
}

/// Сколько дней ссылка открывает карту. Сервер принимает только эти три
/// числа, четвёртое отклонилось бы 422, поэтому список живёт здесь, а не
/// собирается на экране.
enum MedicalShareDays {
    static let all = [1, 7, 30]

    static func title(_ days: Int) -> String {
        days == 1 ? "1 день" : "\(days) \(Words.pick(days, one: "день", few: "дня", many: "дней"))"
    }
}
