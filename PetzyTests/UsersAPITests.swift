import Foundation
@testable import Petzy
import Testing

/// Админка пользователей. Живёт только у администратора: сервер отвечает
/// «Доступ только для администратора», а список с поиском и постраничный.
@MainActor
@Suite("Админка: контракт")
struct UsersAPITests {
    private func client() async -> APIClient {
        await MedicationsTests.client(session: StubURLProtocol.makeSession())
    }

    private func page(_ users: [[String: Any]]) -> [String: Any] {
        ["page": 1, "per_page": 20, "total": users.count, "users": users]
    }

    private func stubUser(username: String, active: Bool = true, admin: Bool = false) -> [String: Any] {
        [
            "_id": "6ad0000000000000000000aa", "username": username, "full_name": "Анна",
            "email": "", "is_active": active, "is_admin": admin,
            "created_at": "2026-10-03T07:52:47Z", "created_by": "self"
        ]
    }

    /// Поиск уходит на сервер: 49 пользователей локально, а на телефоне их
    /// может быть и девяносто, и пролистывать их вручную незачем. Пробел и
    /// кириллица должны уйти закодированными, иначе сервер получит мусор.
    @Test("Список уходит с поиском и страницей")
    func listSendsQuery() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: page([stubUser(username: "demo")]))
        let client = await client()

        let result = try await UsersAPI.list(client, page: 2, query: "Анна Иванова")

        let request = StubURLProtocol.requests.first
        #expect(request?.url?.path == "/api/users")
        #expect(request?.url?.query?.contains("page=2") == true)
        #expect(request?.url?.query?.contains("q=%D0%90%D0%BD%D0%BD%D0%B0%20") == true)
        #expect(request?.url?.absoluteString.contains(" ") == false, "пробел ушёл в адрес как есть")
        #expect(result.users.map(\.username) == ["demo"])
        #expect(result.total == 1)
        #expect(result.users.first?.isActive == true)
    }

    /// Пустой поиск не отправляется вовсе: сервер и так вернёт всё, а лишний
    /// параметр только мешает.
    @Test("Пустой поиск не уходит на сервер")
    func emptyQueryIsNotSent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: page([]))
        let client = await client()

        _ = try await UsersAPI.list(client, page: 1, query: "  ")

        #expect(StubURLProtocol.requests.first?.url?.query?.contains("q=") == false)
    }

    /// Логин не переводят и не чистят: им человек входит, и он должен остаться
    /// таким же, каким был заведён.
    @Test("Логин уходит как есть")
    func usernameGoesAsIs() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(
            status: 200,
            json: ["success": true, "message": "Пользователь создан", "user": stubUser(username: "Anna-1")]
        )
        let client = await client()
        var draft = UserDraft()
        draft.username = "Anna-1"
        draft.password = "probepass"

        _ = try await UsersAPI.create(client, draft: draft)

        let body = TestSupport.body(of: StubURLProtocol.requests.first)
        #expect(body["username"] as? String == "Anna-1")
        #expect(body["password"] as? String == "probepass")
        #expect(StubURLProtocol.requests.first?.httpMethod == "POST")
    }

    /// Пустое имя или короткий пароль сервер отвергнет: человек увидит отказ
    /// вместо вопроса, что именно не так.
    @Test("Пустое имя и короткий пароль не уходят")
    func emptyDraftIsRejected() {
        var draft = UserDraft()

        #expect(UserDraft.problem(draft, isNew: true) == "Введите логин")
        draft.username = "anna"
        #expect(UserDraft.problem(draft, isNew: true) == "Пароль от 6 символов")
        draft.password = "probepass"
        #expect(UserDraft.problem(draft, isNew: true) == nil)
        #expect(UserDraft.problem(draft, isNew: false) == nil, "у правки пароля нет")
    }

    /// Правка не трогает пароль: смена пароля — отдельное действие со своим
    /// подтверждением, и в общем списке её быть не должно.
    @Test("Правка не ходит в пароль")
    func updateLeavesPasswordAlone() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Пользователь обновлён"])
        let client = await client()
        var draft = UserDraft()
        draft.username = "anna"
        draft.password = "probepass"

        try await UsersAPI.update(client, username: "anna", draft: draft)

        let body = TestSupport.body(of: StubURLProtocol.requests.first)
        #expect(body["password"] == nil, "пароль меняется только сбросом")
        #expect(StubURLProtocol.requestedPaths == ["/api/users/anna"])
        #expect(StubURLProtocol.requests.first?.httpMethod == "PUT")
    }

    /// Отключение и сброс пароля идут своими путями и по одному разу: две
    /// отправки означали бы двойную смену пароля и пару лишних записей.
    @Test("Отключение и сброс пароля идут по своим путям")
    func disableAndReset() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Пароль изменён"])
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Пользователь деактивирован"])
        let client = await client()

        try await UsersAPI.resetPassword(client, username: "anna", to: "newprobepass")
        try await UsersAPI.disable(client, username: "anna")

        #expect(StubURLProtocol.requestedPaths == [
            "/api/users/anna/reset-password",
            "/api/users/anna"
        ])
        #expect(TestSupport.body(of: StubURLProtocol.requests.first)["password"] as? String == "newprobepass")
        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
    }

    /// Ключ `is_admin` есть не у всех: в списке его нет у обычных людей, и
    /// без этого весь список не разбирался и экран оставался пустым.
    @Test("Человек без признака администратора читается как обычный")
    func missingAdminFlagIsNotAdmin() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: page([[
            "_id": "6ad0000000000000000000aa", "username": "anna", "full_name": "Анна",
            "email": "", "is_active": true, "created_at": "2026-10-03T07:52:47Z", "created_by": "self"
        ]]))
        let client = await client()

        let result = try await UsersAPI.list(client, page: 1, query: "")

        #expect(result.users.first?.username == "anna")
        #expect(result.users.first?.isAdmin == false)
    }

    /// Отказ сервера приходит по-русски: «Такой логин уже есть» человек должен
    /// прочитать, а не догадываться по пустому экрану.
    @Test("Отказ сервера показывается по-русски")
    func serverErrorIsShown() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 422, json: [
            "success": false, "code": "user_exists", "error": "Пользователь с таким именем уже существует"
        ])
        let client = await client()

        do {
            _ = try await UsersAPI.disable(client, username: "anna")
            Issue.record("ожидался отказ сервера")
        } catch let error as APIError {
            #expect(error.errorDescription == "Пользователь с таким именем уже существует")
        }
    }
}
