import Foundation

/// Разговор с сервером об аккаунте: почта, пароль и удаление. Единственное
/// место, где известны пути `/api/me/...` и ключи ответа.
enum AccountAPI {
    /// Логин, имя и состояние почты. Читается при открытии экрана, а не
    /// хранится: почта меняется с другого устройства, и сохранённая копия
    /// показывала бы человеку чужой адрес.
    static func account(_ client: APIClient) async throws -> AccountInfo {
        let response: AccountDTO = try await client.get("/api/me/account")
        return response.domain
    }

    /// Смена почты. Пустая почта убирает адрес, а новая уходит в
    /// `pending_email` и ждёт подтверждения письмом.
    static func changeEmail(_ client: APIClient, email: String, password: String) async throws -> AccountInfo {
        let response: AccountDTO = try await client.put(
            "/api/me/email",
            body: EmailChangeBody(email: email, password: password)
        )
        return response.domain
    }

    /// Письмо с подтверждением повторно: первое могло не дойти.
    static func resendVerification(_ client: APIClient) async throws {
        let ack: MessageAck = try await client.post("/api/me/email/resend", body: EmptyBody())
        _ = ack
    }

    /// Смена пароля. Ответ — новая пара токенов, которой надо заменить старую:
    /// прежняя на сервере перестаёт работать, иначе приложение выкинет
    /// человека на экран входа через 15 минут.
    static func changePassword(
        _ client: APIClient,
        current: String,
        new: String
    ) async throws -> AuthTokensResponse {
        try await client.put(
            "/api/me/password",
            body: PasswordChangeBody(currentPassword: current, newPassword: new)
        )
    }

    /// Что случится с питомцами, если удалить аккаунт. Читается до вопроса:
    /// человек должен увидеть, кому достанутся его питомцы.
    static func deletionPlan(_ client: APIClient) async throws -> AccountDeletionPlan {
        try await client.get("/api/me/account/deletion")
    }

    static func deleteAccount(_ client: APIClient, password: String) async throws {
        let ack: MessageAck = try await client.delete(
            "/api/me/account",
            body: AccountDeleteBody(password: password)
        )
        _ = ack
    }
}

// MARK: - Тела запросов

private struct EmailChangeBody: Encodable {
    let email: String
    let password: String
}

private struct PasswordChangeBody: Encodable {
    let currentPassword: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword = "new_password"
    }
}

private struct AccountDeleteBody: Encodable {
    let password: String
}

/// Пустое тело нужно методу, который его требует: у `POST` без полей его нет.
struct EmptyBody: Encodable, Sendable {}

// MARK: - Разобранный ответ

private struct AccountDTO: Decodable {
    let username: String
    let fullName: String
    let email: String
    let emailVerified: Bool
    let pendingEmail: String
    let mailEnabled: Bool
    let privacyConsentNeeded: Bool

    enum CodingKeys: String, CodingKey {
        case username, email
        case fullName = "full_name"
        case emailVerified = "email_verified"
        case pendingEmail = "pending_email"
        case mailEnabled = "mail_enabled"
        case privacyConsentNeeded = "privacy_consent_needed"
    }

    var domain: AccountInfo {
        AccountInfo(
            username: username,
            fullName: fullName,
            email: email,
            emailVerified: emailVerified,
            pendingEmail: pendingEmail,
            mailEnabled: mailEnabled,
            privacyConsentNeeded: privacyConsentNeeded
        )
    }
}

private struct MessageAck: Decodable {
    let message: String?
}
