import Foundation
import Observation

/// Состояние экрана «Аккаунт». Знает про запросы и что после них показать, но
/// не знает про JSON: разбор лежит в `AccountAPI`.
@MainActor
@Observable
final class AccountModel {
    private(set) var info: AccountInfo?
    private(set) var plan: AccountDeletionPlan?
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски.
    var errorText: String?
    var notice: String?

    /// Почта, которую человек назвал, и пароль к ней. Пустая почта убирает
    /// адрес, поэтому поле не требует заполнения.
    var email = ""
    var emailPassword = ""
    var currentPassword = ""
    var newPassword = ""
    var deletePassword = ""

    private let client: APIClient
    private let auth: AuthSession
    let app: AppModel

    init(client: APIClient, auth: AuthSession, app: AppModel) {
        self.client = client
        self.auth = auth
        self.app = app
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await AccountAPI.account(client)
            info = loaded
            email = loaded.email
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Смена почты. Сервер проверяет пароль и шлёт письмо на новый адрес,
    /// поэтому старый продолжает работать до подтверждения.
    @discardableResult
    func saveEmail() async -> Bool {
        if emailPassword.isEmpty {
            errorText = "Введите пароль"
            return false
        }
        errorText = nil
        do {
            let updated = try await AccountAPI.changeEmail(
                client,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: emailPassword
            )
            info = updated
            email = updated.email
            emailPassword = ""
            notice = updated.pendingEmail.isEmpty
                ? "Почта сохранена"
                : "Письмо для подтверждения отправлено на \(updated.pendingEmail)"
            return true
        } catch {
            errorText = Self.text(of: error)
            emailPassword = ""
            return false
        }
    }

    /// Письмо с подтверждением повторно: первое могло затеряться.
    func resendVerification() async {
        do {
            try await AccountAPI.resendVerification(client)
            notice = "Письмо отправлено ещё раз"
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Смена пароля. Сервер отдаёт новую пару токенов и рвёт старую: без её
    /// замены приложение работает ещё 15 минут и выкидывает человека на экран
    /// входа посреди сессии.
    @discardableResult
    func changePassword() async -> Bool {
        if currentPassword.isEmpty {
            errorText = "Введите текущий пароль"
            return false
        }
        errorText = nil
        do {
            let fresh = try await AccountAPI.changePassword(
                client,
                current: currentPassword,
                new: newPassword
            )
            try await auth.replaceTokens(fresh)
            currentPassword = ""
            newPassword = ""
            notice = "Пароль изменён"
            return true
        } catch {
            errorText = Self.text(of: error)
            currentPassword = ""
            newPassword = ""
            return false
        }
    }

    /// Что случится с питомцами. Читается до вопроса об удалении.
    func prepareDeletion() async {
        do {
            plan = try await AccountAPI.deletionPlan(client)
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Удаление аккаунта. Отмены нет, поэтому пароль спрашивается и здесь:
    /// одно подтверждение «точно?» не защищает от случайного нажатия.
    func deleteAccount() async {
        if deletePassword.isEmpty {
            errorText = "Введите пароль"
            return
        }
        errorText = nil
        do {
            try await AccountAPI.deleteAccount(client, password: deletePassword)
            deletePassword = ""
            // Аккаунта больше нет, а токены на устройстве остались: без выхода
            // следующий запрос вернул бы 401 и показал пустые экраны.
            app.signOut()
        } catch {
            errorText = Self.text(of: error)
            deletePassword = ""
        }
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
