import Foundation

/// «К приёму»: что беспокоит и что изменилось.
struct VisitPrep: Sendable {
    /// Версия заметки: своя, не та же, что у профиля для врача.
    let baseVersion: String?
    let complaint: String?
    let checks: [VisitCheck]
}

struct VisitCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
}

/// «К приёму» в том виде, как его заполняет форма. На экране отметки читаются
/// словами, а уходят ключами `normal` и `changed`: их сервер и хранит, свои
/// слова он не поймёт.
struct VisitPrepDraft {
    var complaint: String
    /// Что отмечено по каждому пункту, пустая строка — не отмечено.
    var picks: [String: String]
    /// Версия заметки, с которой открыли форму.
    var baseVersion: String?

    static let values = ["normal", "changed"]

    init(complaint: String, picks: [String: String], baseVersion: String?) {
        self.complaint = complaint
        self.picks = picks
        self.baseVersion = baseVersion
    }

    init(prep: VisitPrep?, baseVersion: String?) {
        complaint = prep?.complaint ?? ""
        picks = prep?.checks.reduce(into: [:]) { result, check in
            result[check.id] = check.value
        } ?? [:]
        self.baseVersion = baseVersion
    }

    /// Собирает тело запроса из жалобы и отметок. Пустая жалоба уходит как
    /// `nil`, а не как пустая строка: для сервера это «нечего писать».
    init(body complaint: String?, checks: [String: String]) {
        let text = (complaint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.complaint = text
        picks = checks
        baseVersion = nil
    }

    /// Тело запроса для модели.
    var body: (complaint: String?, checks: [String: String]) {
        let text = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text.isEmpty ? nil : text, Self.checks(from: picks))
    }

    /// Ни жалобы, ни отметок: сервер на такой запрос убирает заметку, и это
    /// ровно то, что человек хочет, нажав «Очистить».
    var isEmpty: Bool {
        let current = body
        return current.complaint == nil && current.checks.isEmpty
    }

    /// Только отмеченное и только теми словами, которые сервер понимает.
    /// Неотмеченный пункт иначе сохранился бы как «кашель: как обычно» у того,
    /// кто про кашель не думал.
    static func checks(from picks: [String: String]) -> [String: String] {
        picks.filter { values.contains($0.value) }
    }
}
