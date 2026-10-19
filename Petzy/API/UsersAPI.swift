import Foundation

/// Разговор с сервером об админке `/api/users*`. Отвечает только
/// администратору, остальным приходит `forbidden_admin_only`, поэтому
/// приложение и не показывает этот экран никому другому.
enum UsersAPI {
    static func list(_ client: APIClient, page: Int, query: String) async throws -> UsersPage {
        var path = "/api/users?page=\(max(1, page))"
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            path += "&q=" + AppModel.query(trimmed)
        }
        let response: UsersPageDTO = try await client.get(path)
        return response.domain
    }

    static func create(_ client: APIClient, draft: UserDraft) async throws -> UserInfo {
        let response: UserEnvelope = try await client.post("/api/users", body: CreateBody(draft: draft))
        return response.user.domain
    }

    static func update(_ client: APIClient, username: String, draft: UserDraft) async throws {
        let _: MessageAck = try await client.put(
            "/api/users/" + AppModel.query(username),
            body: EditBody(draft: draft)
        )
    }

    static func resetPassword(_ client: APIClient, username: String, to password: String) async throws {
        let _: MessageAck = try await client.post(
            "/api/users/" + AppModel.query(username) + "/reset-password",
            body: PasswordBody(password: password)
        )
    }

    /// Отключение, а не удаление: человек пропадает из входа, но его записи и
    /// история остаются на месте.
    static func disable(_ client: APIClient, username: String) async throws {
        let _: MessageAck = try await client.delete("/api/users/" + AppModel.query(username))
    }
}

// MARK: - Тела запросов

private struct CreateBody: Encodable {
    let username: String
    let fullName: String
    let email: String
    let password: String

    init(draft: UserDraft) {
        username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        fullName = draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        password = draft.password
    }

    enum CodingKeys: String, CodingKey {
        case username, email, password
        case fullName = "full_name"
    }
}

/// Пароля здесь нет намеренно: он меняется только через сброс, и молча
/// менялся бы при каждой правке имени.
private struct EditBody: Encodable {
    let fullName: String
    let email: String

    init(draft: UserDraft) {
        fullName = draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case email
        case fullName = "full_name"
    }
}

private struct PasswordBody: Encodable {
    let password: String
}

/// Ответы сервера на эти вызовы отличаются только текстом сообщения, которое
/// приложение показывает само, когда что-то пошло не так.
private struct MessageAck: Decodable {
    let message: String?
}

// MARK: - Разобранный ответ

private struct UsersPageDTO: Decodable {
    let total: Int
    let users: [UserDTO]

    var domain: UsersPage {
        UsersPage(users: users.map(\.domain), total: total)
    }
}

private struct UserEnvelope: Decodable {
    let user: UserDTO
}

private struct UserDTO: Decodable {
    let id: String
    let username: String
    let fullName: String
    let email: String?
    let isActive: Bool
    /// Признака администратора у обычного человека в списке нет вовсе, а у
    /// администратора он есть, и отсутствие ключа — это «не админ».
    let isAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username, email
        case fullName = "full_name"
        case isActive = "is_active"
        case isAdmin = "is_admin"
    }

    var domain: UserInfo {
        UserInfo(
            id: id,
            username: username,
            fullName: fullName,
            email: email ?? "",
            isActive: isActive,
            isAdmin: isAdmin ?? false
        )
    }
}
