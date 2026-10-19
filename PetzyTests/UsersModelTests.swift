import Foundation
@testable import Petzy
import Testing

/// Экран администратора: список людей, создание, правка, отключение и сброс
/// пароля. Ключевое здесь — отключённый человек не может войти, поэтому
/// список после отключения должен перечитаться, а не остаться как был.
@MainActor
@Suite("Экран администратора", .serialized)
struct UsersModelTests {
    private func model() async -> UsersModel {
        let session = StubURLProtocol.makeSession()
        return await UsersModel(client: MedicationsTests.client(session: session))
    }

    private func user(_ username: String, active: Bool = true) -> [String: Any] {
        [
            "_id": "id_\(username)", "username": username, "full_name": "Анна",
            "email": "", "is_active": active, "is_admin": false,
            "created_at": "2026-10-03T07:52:47Z", "created_by": "self"
        ]
    }

    private func page(_ users: [[String: Any]], total: Int? = nil) -> [String: Any] {
        ["page": 1, "per_page": 20, "total": total ?? users.count, "users": users]
    }

    @Test("Список приходит и показывает, кого сколько")
    func listIsLoaded() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: page([user("anna"), user("petr")], total: 49))
        let model = await model()

        await model.load()

        #expect(model.users.map(\.username) == ["anna", "petr"])
        #expect(model.total == 49)
        #expect(model.errorText == nil)
    }

    /// Пустая форма не должна уходить на сервер: он ответит 422, а человек
    /// увидит отказ вместо вопроса.
    @Test("Незаполненная форма не уходит")
    func emptyDraftIsNotSent() async {
        StubURLProtocol.reset()
        let model = await model()

        let created = await model.create(UserDraft())

        #expect(created == false)
        #expect(model.errorText == "Введите логин")
        #expect(StubURLProtocol.requests.isEmpty, "пустая форма ушла на сервер")
    }

    /// Созданный человек обязан появиться в списке сам: иначе администратор
    /// решил бы, что учётка не создалась, и завёл бы вторую.
    @Test("После создания человек появляется в списке")
    func createdUserAppears() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "success": true, "message": "Пользователь создан", "user": user("anna")
        ])
        StubURLProtocol.stub(status: 200, json: page([user("anna")]))
        let model = await model()
        var draft = UserDraft()
        draft.username = "anna"
        draft.password = "probepass"

        let created = await model.create(draft)

        #expect(created)
        #expect(model.users.map(\.username) == ["anna"])
        #expect(model.errorText == nil)
    }

    /// Отключение необратимо для входа: человек должен уйти из списка сразу,
    /// а не после ручного обновления.
    @Test("После отключения человека нет в списке")
    func disabledUserLeavesList() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: page([user("anna"), user("petr")]))
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Пользователь деактивирован"])
        StubURLProtocol.stub(status: 200, json: page([user("petr")]))
        let model = await model()
        await model.load()

        await model.disable(model.users.first)

        #expect(model.users.map(\.username) == ["petr"])
        #expect(StubURLProtocol.requestedPaths == [
            "/api/users",
            "/api/users/anna",
            "/api/users"
        ])
    }

    /// Сброс пароля человек делает не ради себя, а ради того, кому доступ
    /// забыли: новый пароль должен дойти, и в списке человек остаётся.
    @Test("Сброс пароля оставляет человека в списке")
    func resetKeepsUser() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: page([user("anna")]))
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Пароль изменён"])
        StubURLProtocol.stub(status: 200, json: page([user("anna")]))
        let model = await model()
        await model.load()

        let changed = await model.resetPassword(for: model.users.first, to: "newprobepass")

        #expect(changed)
        #expect(model.users.map(\.username) == ["anna"])
        #expect(StubURLProtocol.requestedPaths == [
            "/api/users",
            "/api/users/anna/reset-password",
            "/api/users"
        ])
    }

    /// Поиск не спрашивает сервер на каждый символ: человек печатает быстро,
    /// а сеть на каждый ввод ответит «всё равно рано».
    @Test("Поиск спрашивает сервер один раз, а не на каждый символ")
    func searchIsDebounced() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: page([]))
        let model = await model()

        model.query = "а"
        model.searchChanged()
        model.query = "ан"
        model.searchChanged()
        model.query = "анн"
        model.searchChanged()
        try? await Task.sleep(for: .milliseconds(800))

        #expect(StubURLProtocol.requests.count == 1, "поиск спрашивал сервер на каждый символ")
    }

    /// Отказ сервера показываем его словами: «Пользователь с таким именем уже
    /// существует» человек должен прочитать, а не догадываться.
    @Test("Ошибка сервера показывается по-русски")
    func serverErrorIsShown() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 422, json: [
            "success": false, "code": "user_exists", "error": "Пользователь с таким именем уже существует"
        ])
        let model = await model()
        var draft = UserDraft()
        draft.username = "anna"
        draft.password = "probepass"

        let created = await model.create(draft)

        #expect(created == false)
        #expect(model.errorText == "Пользователь с таким именем уже существует")
    }
}
