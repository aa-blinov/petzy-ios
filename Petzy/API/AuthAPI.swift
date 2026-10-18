import Foundation

/// Разговор с сервером о входе без сессии: регистрация, восстановление пароля,
/// подтверждение почты и политика. Маршруты авторизованной части живут в
/// `AuthSession`, здесь только то, что нужно до входа.
enum AuthAPI {
    static func registrationStatus(_ client: APIClient) async throws -> RegistrationStatus {
        let response: RegistrationStatusDTO = try await client.get("/api/auth/registration", anonymous: true)
        return response.domain
    }

    /// Регистрация сразу начинает сессию: ответ приходит с токенами, и
    /// отдельный вход после неё не нужен.
    static func register(_ client: APIClient, draft: RegistrationDraft) async throws -> AuthTokensResponse {
        try await client.post("/api/auth/register", body: RegistrationBody(draft: draft), anonymous: true)
    }

    /// Ответ на просьбу о ссылке всегда один и тот же: сказать «аккаунта нет»
    /// значит дать возможность проверить, кто записан на сервере.
    static func forgotPassword(_ client: APIClient, login: String) async throws {
        let ack: MessageAck = try await client.post(
            "/api/auth/password/forgot",
            body: LoginBody(login: login.trimmingCharacters(in: .whitespacesAndNewlines)),
            anonymous: true
        )
        _ = ack
    }

    /// Жива ли ещё ссылка из письма. Спрашивается при открытии экрана, чтобы
    /// истёкшая ссылка сказала о себе сразу, а не после выбора пароля.
    static func resetLinkIsLive(_ client: APIClient, token: String) async throws -> Bool {
        let response: ResetCheckDTO = try await client.get(
            "/api/auth/password/reset/check?token=\(AppModel.query(token))",
            anonymous: true
        )
        return response.valid
    }

    /// Новый пароль по ссылке. Сервер входит в аккаунт и отдаёт токены.
    static func resetPassword(
        _ client: APIClient,
        token: String,
        password: String
    ) async throws -> AuthTokensResponse {
        try await client.post(
            "/api/auth/password/reset",
            body: PasswordResetBody(token: token, password: password),
            anonymous: true
        )
    }

    static func verifyEmail(_ client: APIClient, token: String) async throws {
        let ack: MessageAck = try await client.post(
            "/api/auth/email/verify",
            body: TokenBody(token: token),
            anonymous: true
        )
        _ = ack
    }

    /// Кто обрабатывает данные и какая сейчас редакция политики. Пустые поля
    /// сервер не заполняет, и показывать их незачем.
    static func legalInfo(_ client: APIClient) async throws -> LegalInfo {
        let response: LegalDTO = try await client.get("/api/legal", anonymous: true)
        return response.domain
    }

    static func acceptPolicy(_ client: APIClient, version: String) async throws {
        let ack: MessageAck = try await client.post("/api/me/privacy-consent", body: PolicyBody(version: version))
        _ = ack
    }
}

// MARK: - Тела запросов

private struct RegistrationBody: Encodable {
    let username: String
    let password: String
    let fullName: String
    let email: String?
    let privacyConsent: Bool

    init(draft: RegistrationDraft) {
        username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        password = draft.password
        fullName = draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        email = trimmedEmail.isEmpty ? nil : trimmedEmail
        privacyConsent = draft.consent
    }

    enum CodingKeys: String, CodingKey {
        case username, password
        case fullName = "full_name"
        case email
        case privacyConsent = "privacy_consent"
    }
}

private struct LoginBody: Encodable {
    let login: String
}

private struct TokenBody: Encodable {
    let token: String
}

private struct PasswordResetBody: Encodable {
    let token: String
    let password: String
}

private struct PolicyBody: Encodable {
    let version: String
}

// MARK: - Разобранный ответ

private struct MessageAck: Decodable {
    let message: String?
}

private struct RegistrationStatusDTO: Decodable {
    let open: Bool
    let mailEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case open
        case mailEnabled = "mail_enabled"
    }

    var domain: RegistrationStatus {
        RegistrationStatus(isOpen: open, mailEnabled: mailEnabled)
    }
}

private struct ResetCheckDTO: Decodable {
    let valid: Bool
}

private struct LegalDTO: Decodable {
    let policyVersion: String
    /// `operator` — служебное слово Swift, поэтому поле называется иначе, а
    /// ключ остаётся серверным.
    let policyOperator: String
    let contactEmail: String
    let serverLocation: String
    let backupsKeptDays: Int

    enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
        case policyOperator = "operator"
        case contactEmail = "contact_email"
        case serverLocation = "server_location"
        case backupsKeptDays = "backups_kept_days"
    }

    var domain: LegalInfo {
        LegalInfo(
            version: policyVersion,
            facts: [
                ("Кто обрабатывает данные", policyOperator),
                ("Куда писать о персональных данных", contactEmail),
                ("Где стоит сервер с базой данных", serverLocation)
            ].compactMap { title, value in value.isEmpty ? nil : "\(title): \(value)" }
                + ["Резервные копии хранятся \(Words.text(backupsKeptDays, one: "день", few: "дня", many: "дней"))"],
            backupsKeptDays: backupsKeptDays
        )
    }
}
