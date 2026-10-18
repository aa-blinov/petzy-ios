import Foundation

/// Персональный доступ для ассистента: человек или скрипт входит токеном
/// вместо пароля. Секрет сервер отдаёт один раз, поэтому в списке его нет.
struct AccessToken: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let scopes: [String]
    /// Начало секрета, по нему токен узнают в чужом списке.
    let prefix: String?
    let expiresAt: String?

    var isRevoked: Bool {
        revokedAt != nil
    }

    /// Отозванный доступ в списке остаётся, и без этой отметки он выглядел бы
    /// рабочим.
    let revokedAt: String?

    var isExpired: Bool {
        guard let day = expiresAt.map(MomentText.day(of:)) else { return false }
        return day < MomentText.isoDay(.now, calendar: .current)
    }

    /// «Действует до 17.11.2026», а у истёкшего «Срок истёк».
    var expiresText: String? {
        guard let day = expiresAt.map(MomentText.day(of:)) else { return nil }
        return isExpired ? "Срок истёк" : "Действует до \(MomentText.russianDay(day))"
    }
}

/// Созданный доступ вместе с секретом: секрет приходит один раз и больше
/// нигде не хранится.
struct CreatedToken: Sendable {
    let id: String
    let secret: String
}

/// Область доступа в том виде, в каком её выбирает человек.
enum AccessScope: Sendable, CaseIterable {
    case petsRead
    case eventsWrite
    case historyRead
    case medicalRead

    var key: String {
        switch self {
        case .petsRead: "pets:read"
        case .eventsWrite: "events:write"
        case .historyRead: "history:read"
        case .medicalRead: "medical:read"
        }
    }

    var title: String {
        switch self {
        case .petsRead: "Видеть питомцев"
        case .eventsWrite: "Добавлять записи"
        case .historyRead: "Смотреть историю"
        case .medicalRead: "Смотреть медкарту"
        }
    }

    static func title(of key: String) -> String {
        allCases.first { $0.key == key }?.title ?? key
    }
}

/// Форма нового доступа в том виде, как её заполняет человек.
struct AccessTokenDraft: Sendable {
    var name = ""
    var scopes: Set<AccessScope> = []
    var days = 90

    /// Что поправить до запроса. Правила списка и срока проверяет сервер,
    /// а вот пустое имя и пустой набор областей отвергнет и он, поэтому их
    /// спрашиваем сами: без работающего токена ассистент не сделает ничего.
    static func problem(_ draft: AccessTokenDraft) -> String? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите имя доступа"
        }
        if draft.scopes.isEmpty {
            return "Выберите, что можно ассистенту"
        }
        return nil
    }

    var scopeKeys: [String] {
        AccessScope.allCases.filter { scopes.contains($0) }.map(\.key)
    }
}
