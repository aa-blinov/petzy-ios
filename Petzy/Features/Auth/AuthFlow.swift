import Foundation

/// Открыта ли регистрация на этом сервере. Если закрыта, кнопки «Создать
/// аккаунт» на экране входа быть не должно.
struct RegistrationStatus: Sendable, Equatable {
    let isOpen: Bool
    /// Настроена ли отправка писем. Без неё восстановление пароля и
    /// подтверждение почты не работают, и просить их незачем.
    let mailEnabled: Bool
}

/// Форма регистрации в том виде, как её заполняет человек.
struct RegistrationDraft: Sendable {
    var username = ""
    var fullName = ""
    var password = ""
    var email = ""
    /// Согласие с политикой. Без него сервер отвечает 422, и форма обязана
    /// спросить сама: показывать отказ сервера вместо галочки значит
    /// оставить человека в тупике.
    var consent = false

    /// Что человек должен поправить до запроса, своими словами. `nil` — можно
    /// отправлять. Правила пароля проверяет сервер: список частых паролей
    /// никогда не должен ехать в приложение.
    static func problem(_ draft: RegistrationDraft) -> String? {
        if draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите логин"
        }
        if draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите имя"
        }
        if draft.password.isEmpty {
            return "Придумайте пароль"
        }
        if !draft.consent {
            return "Отметьте согласие с политикой"
        }
        return nil
    }
}

/// Политика обработки данных в том виде, как её показывает экран.
struct LegalInfo: Sendable, Equatable {
    /// Редакция: её сравнивают с тем, на что человек соглашался, поэтому она
    /// уходит обратно на сервер без изменений.
    let version: String
    /// Готовые строки о том, кто обрабатывает данные. Пустых нет: сервер их
    /// не заполняет, и строка «Кто обрабатывает данные: » ничего не говорит.
    let facts: [String]
    let backupsKeptDays: Int
}

/// Ссылка из письма. Приложение ловит её по своей схеме `petzy://`; по
/// обычной веб-ссылке без подписи разработчика письмо откроет сайт.
enum AppLink: Equatable {
    case resetPassword(token: String)
    case verifyEmail(token: String)

    /// Токен из письма. Без него ссылка бесполезна, и молча открывать
    /// нерабочий экран хуже, чем не открыть ничего.
    static func parse(_ url: URL) -> AppLink? {
        guard url.scheme == "petzy",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty
        else { return nil }
        switch url.host {
        case "reset-password": return .resetPassword(token: token)
        case "verify-email": return .verifyEmail(token: token)
        default: return nil
        }
    }
}
