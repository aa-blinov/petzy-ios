import Foundation
@testable import Petzy
import Testing

/// Доступы для ассистентов: персональные токены вместо пароля. Секрет
/// сервер отдаёт один раз, поэтому в списке его нет и быть не может.
@MainActor
@Suite("Доступы для ассистентов: контракт")
struct TokensAPITests {
    private func token(
        id: String,
        name: String,
        revoked: Bool = false,
        expires: String = "2026-11-17T23:27:32Z"
    ) -> [String: Any] {
        [
            "id": id, "name": name, "prefix": "ptz_23E1", "scopes": ["pets:read", "events:write"],
            "created_at": "2026-10-18T23:27:32Z", "expires_at": expires,
            "last_used_at": "2026-10-19T09:12:00Z", "revoked_at": revoked ? "2026-10-19T10:00:00Z" : NSNull()
        ]
    }

    /// Отозванный и истёкший остаются в списке, и оба должны быть видны как
    /// нерабочие: иначе человек увидит «доступ есть» и будет им пользоваться.
    @Test("Список доступов разбирается, отозванные и истёкшие помечены")
    func listMarksDeadTokens() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["tokens": [
            token(id: "t1", name: "Домофон"),
            token(id: "t2", name: "Старый", revoked: true),
            token(id: "t3", name: "Истёкший", expires: "2026-10-17T23:27:32Z")
        ]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let tokens = try await TokensAPI.list(client)

        #expect(tokens.map(\.id) == ["t1", "t2", "t3"])
        // Через optional, а не по индексу: при пустом ответе падение на
        // индексе убивает весь прогон, а должно красным сделать проверку.
        #expect(tokens.first?.name == "Домофон")
        #expect(tokens.first?.scopes == ["pets:read", "events:write"])
        #expect(tokens.first?.prefix == "ptz_23E1")
        #expect(tokens.first?.isRevoked == false)
        #expect(tokens.first?.isExpired == false)
        #expect(tokens.first?.expiresText == "Действует до 17.11.2026")
        #expect(tokens.last?.isExpired == true, "истёкший доступ выглядит рабочим")
        #expect(tokens.last?.expiresText == "Срок истёк")
        #expect(StubURLProtocol.requestedPaths == ["/api/me/tokens"])
    }

    /// Тело запроса проверяется целиком: без срока сервер подставит свой, а
    /// без областей токен бесполезен, и сервер это отвергнет.
    @Test("Новый доступ уходит с именем, областями и сроком")
    func createSendsEverything() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "id": "t9", "name": "Домофон", "prefix": "ptz_23E1", "scopes": ["pets:read"],
            "expires_at": "2026-11-17T23:27:32Z", "token": "ptz_23E1JK4PgzxQVU8Ox0Bk35GrBstmlowxLLWMvh2vdak"
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let created = try await TokensAPI.create(
            client,
            name: "Домофон",
            scopes: ["pets:read"],
            days: 90
        )

        let body = TestSupport.body(of: StubURLProtocol.requests.first)
        #expect(body["name"] as? String == "Домофон")
        #expect(body["scopes"] as? [String] == ["pets:read"])
        #expect(body["expires_in_days"] as? Int == 90)
        #expect(created.secret == "ptz_23E1JK4PgzxQVU8Ox0Bk35GrBstmlowxLLWMvh2vdak", "секрет не дошёл до человека")
        #expect(created.id == "t9")
    }

    @Test("Отзыв удаляет доступ отдельным запросом")
    func revokeDeletesOneToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Доступ отозван"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await TokensAPI.revoke(client, id: "6ad555e4246d9b37ad852877")

        #expect(StubURLProtocol.requestedPaths == ["/api/me/tokens/6ad555e4246d9b37ad852877"])
        #expect(StubURLProtocol.requests.first?.httpMethod == "DELETE")
    }
}
