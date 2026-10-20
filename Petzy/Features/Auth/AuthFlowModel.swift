import Foundation
import Observation

/// Состояние входа и регистрации: что человек набирает, что сервер ответил и
/// куда попали токены. Один на все экраны входа, потому что речь у них об одном.
@MainActor
@Observable
final class AuthFlowModel {
    /// То, что человек набирает в форме регистрации.
    var draft = RegistrationDraft()
    /// Подсказки под полями формы: человек должен видеть, что именно
    /// заполнить, а не читать об этом над формой.
    private(set) var problems: [RegistrationField] = []
    /// Новая почта по ссылке из письма.
    var password = ""
    var errorText: String?
    var notice: String?
    private(set) var policy: LegalInfo?
    /// Открыта ли регистрация. Пока ответ не пришёл, кнопки нет: показать её
    /// и убрать через секунду хуже, чем не показать вовсе.
    private(set) var registrationIsOpen = false
    /// Ссылка из письма оказалась мёртвой: сказать сразу и не спрашивать пароль.
    private(set) var isResetLinkDead = false

    private let client: APIClient
    private let auth: AuthSession
    let app: AppModel

    init(client: APIClient, auth: AuthSession, app: AppModel) {
        self.client = client
        self.auth = auth
        self.app = app
    }

    func loadRegistrationStatus() async {
        do {
            registrationIsOpen = try await AuthAPI.registrationStatus(client).isOpen
        } catch {
            registrationIsOpen = false
        }
    }

    func loadPolicy() async {
        do {
            policy = try await AuthAPI.legalInfo(client)
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Регистрация. Сервер сразу выдаёт токены, поэтому после успеха человек
    /// оказывается внутри приложения, а не снова на экране входа.
    @discardableResult
    func register() async -> Bool {
        let found = RegistrationDraft.problems(draft)
        guard found.isEmpty else {
            problems = found
            errorText = nil
            return false
        }
        problems = []
        errorText = nil
        do {
            let username = draft.username
            let tokens = try await AuthAPI.register(client, draft: draft)
            try await auth.replaceTokens(tokens)
            draft = RegistrationDraft()
            await app.acceptSession(username: username)
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Проверка ссылки из письма. Спрашивается при открытии экрана: истёкшая
    /// ссылка должна сказать об этом до того, как человек наберёт пароль.
    func checkResetLink(_ token: String) async {
        isResetLinkDead = false
        errorText = nil
        do {
            isResetLinkDead = try await AuthAPI.resetLinkIsLive(client, token: token) == false
            if isResetLinkDead {
                errorText = "Ссылка больше не работает, попросите новую в письме"
            }
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Новый пароль по ссылке. Токены кладутся на устройство, и человек сразу
    /// оказывается в приложении.
    @discardableResult
    func resetPassword(token: String) async -> Bool {
        if password.isEmpty {
            errorText = "Придумайте пароль"
            return false
        }
        errorText = nil
        do {
            let tokens = try await AuthAPI.resetPassword(client, token: token, password: password)
            try await auth.replaceTokens(tokens)
            password = ""
            // Логина здесь нет: его узнает сервер, когда модель спросит сессию.
            await app.acceptSession()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    func forgotPassword(login: String) async {
        do {
            try await AuthAPI.forgotPassword(client, login: login)
            // Текст сервера одинаковый для любого логина: он и не должен
            // отвечать, есть такой аккаунт или нет.
            notice = "Если такой аккаунт есть, письмо с ссылкой уже отправлено"
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    @discardableResult
    func verifyEmail(token: String) async -> Bool {
        do {
            try await AuthAPI.verifyEmail(client, token: token)
            notice = "Почта подтверждена"
            errorText = nil
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Согласие с текущей редакцией политики. Редакцию отправляем ту, которую
    /// человек прочитал: пока политику не поменяли, сервер её примет.
    @discardableResult
    func acceptPolicy() async -> Bool {
        guard let version = policy?.version else {
            errorText = "Политика не загрузилась, попробуйте ещё раз"
            return false
        }
        do {
            try await AuthAPI.acceptPolicy(client, version: version)
            errorText = nil
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
