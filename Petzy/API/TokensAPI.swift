import Foundation

/// Разговор с сервером о персональных доступах `/api/me/tokens`. Единственное
/// место, где известны пути и ключи ответа: экран держит в руках `AccessToken`
/// и про JSON не знает.
enum TokensAPI {
    /// Все доступы, включая отозванные и истёкшие: они остаются в списке
    /// человека, и без них он не поймёт, куда делся прежний токен.
    static func list(_ client: APIClient) async throws -> [AccessToken] {
        let response: ListResponse = try await client.get("/api/me/tokens")
        return response.tokens.map(\.domain)
    }

    /// Создать доступ. Секрет приходит в ответе и больше нигде не хранится,
    /// поэтому вернуть его наружу и показать сразу: второй раз его не спросят.
    static func create(
        _ client: APIClient,
        name: String,
        scopes: [String],
        days: Int
    ) async throws -> CreatedToken {
        let response: CreateResponse = try await client.post(
            "/api/me/tokens",
            body: CreateBody(name: name, scopes: scopes, expiresInDays: days)
        )
        return CreatedToken(id: response.id, secret: response.token)
    }

    static func revoke(_ client: APIClient, id: String) async throws {
        try await client.delete("/api/me/tokens/" + AppModel.query(id))
    }
}

// MARK: - Тела запросов

private struct CreateBody: Encodable {
    let name: String
    let scopes: [String]
    let expiresInDays: Int

    enum CodingKeys: String, CodingKey {
        case name, scopes
        case expiresInDays = "expires_in_days"
    }
}

// MARK: - Разобранный ответ

private struct ListResponse: Decodable {
    let tokens: [TokenDTO]
}

private struct CreateResponse: Decodable {
    let id: String
    let token: String
}

private struct TokenDTO: Decodable {
    let id: String
    let name: String
    let scopes: [String]
    let prefix: String?
    let expiresAt: String?
    let revokedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, scopes, prefix
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
    }

    var domain: AccessToken {
        AccessToken(
            id: id,
            name: name,
            scopes: scopes,
            prefix: prefix,
            expiresAt: expiresAt,
            revokedAt: revokedAt
        )
    }
}
