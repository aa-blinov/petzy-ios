import Foundation
@testable import Petzy
import Testing

/// Экран «Доступы для ассистентов»: список, создание и отзыв. Ключевое здесь —
/// секрет показывается один раз, и форма не уходит на сервер пустой.
@MainActor
@Suite("Экран «Доступы для ассистентов»", .serialized)
struct AccessTokensModelTests {
    private func model() async -> AccessTokensModel {
        let session = StubURLProtocol.makeSession()
        return await AccessTokensModel(client: MedicationsTests.client(session: session))
    }

    private func stubToken(id: String, name: String) -> [String: Any] {
        [
            "id": id, "name": name, "prefix": "ptz_23E1", "scopes": ["pets:read"],
            "created_at": "2026-10-18T23:27:32Z", "expires_at": "2026-11-17T23:27:32Z",
            "last_used_at": NSNull(), "revoked_at": NSNull()
        ]
    }

    /// Пустая форма не должна уходить на сервер: без имени и без областей он
    /// ответит 422, а человек увидит отказ вместо вопроса.
    @Test("Без имени и без областей запрос не уходит")
    func emptyDraftIsNotSent() async {
        StubURLProtocol.reset()
        let model = await model()
        model.draft.name = "   "
        model.draft.scopes = []

        let created = await model.create()

        #expect(created == false)
        #expect(model.errorText == "Введите имя доступа")
        #expect(StubURLProtocol.requests.isEmpty, "пустая форма ушла на сервер")

        model.draft.name = "Домофон"
        #expect(await model.create() == false)
        #expect(model.errorText == "Выберите, что можно ассистенту")
        #expect(StubURLProtocol.requests.isEmpty)
    }

    /// Секрет приходит один раз: он обязан попасть на экран сразу, а список
    /// после создания перечитаться, иначе в нём не будет нового доступа.
    @Test("После создания секрет показан и список обновлён")
    func createdSecretIsShownAndListRefreshed() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "id": "t9", "name": "Домофон", "prefix": "ptz_23E1", "scopes": ["pets:read"],
            "expires_at": "2026-11-17T23:27:32Z", "token": "ptz_23E1JK4PgzxQVU8Ox0Bk35GrBst"
        ])
        StubURLProtocol.stub(status: 200, json: ["tokens": [stubToken(id: "t9", name: "Домофон")]])
        let model = await model()
        model.draft.name = "Домофон"
        model.draft.scopes = [.petsRead]

        let created = await model.create()

        #expect(created)
        #expect(model.secret == "ptz_23E1JK4PgzxQVU8Ox0Bk35GrBst")
        #expect(model.tokens.map(\.id) == ["t9"])
        #expect(model.draft.name.isEmpty, "форма осталась заполненной: доступ можно создать дважды")

        model.forgetSecret()
        #expect(model.secret == nil)
    }

    @Test("Отзыв убирает доступ из списка")
    func revokeRemovesFromList() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["tokens": [
            stubToken(id: "t1", name: "Домофон"), stubToken(id: "t2", name: "Дача")
        ]])
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Доступ отозван"])
        StubURLProtocol.stub(status: 200, json: ["tokens": [stubToken(id: "t1", name: "Домофон")]])
        let model = await model()
        await model.load()
        #expect(model.tokens.count == 2)

        await model.revoke(id: "t2")

        #expect(model.tokens.map(\.id) == ["t1"])
        #expect(StubURLProtocol.requestedPaths == ["/api/me/tokens", "/api/me/tokens/t2", "/api/me/tokens"])
    }

    /// Отказ сервера показываем его словами: «Достигнут лимит» или «неправильное
    /// имя» человек должен прочитать, а не догадываться по пустому экрану.
    @Test("Ошибка сервера показывается по-русски")
    func serverErrorIsShown() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 422, json: [
            "code": "validation_error", "error": "Заполните обязательные поля"
        ])
        let model = await model()

        await model.load()

        #expect(model.errorText == "Заполните обязательные поля")
        #expect(model.tokens.isEmpty)
    }
}
