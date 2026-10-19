import Foundation

/// Пользователь в том виде, как его видит администратор: логин, имя, почта и
/// два флака, из которых важны оба — отключённый человек не может войти, а
/// администратора отключать нельзя.
struct UserInfo: Identifiable, Sendable, Equatable {
    let id: String
    let username: String
    let fullName: String
    let email: String
    let isActive: Bool
    let isAdmin: Bool

    /// «Анна», «demo» — кем человек подписан, а не как его завели.
    var title: String {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? username : "\(name), \(username)"
    }
}

/// Страница списка: сервер отдаёт постранично, и «дальше» без числа
/// пользователей не узнать.
struct UsersPage: Sendable, Equatable {
    let users: [UserInfo]
    let total: Int
}

/// Форма пользователя. У нового есть пароль, у правки его нет: смена пароля —
/// отдельное действие, о котором человек должен знать, а не получить молча.
struct UserDraft: Sendable {
    var username = ""
    var fullName = ""
    var email = ""
    var password = ""

    /// Что поправить до запроса. `nil` — можно отправлять.
    static func problem(_ draft: UserDraft, isNew: Bool) -> String? {
        if draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите логин"
        }
        guard isNew else { return nil }
        if draft.password.count < 6 {
            return "Пароль от 6 символов"
        }
        return nil
    }
}
