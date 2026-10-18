import Foundation
@testable import Petzy
import Testing

/// Модель аккаунта: что показывает, что заменяет токены и когда учётная запись
/// удалена.
@Suite("Аккаунт: модель")
@MainActor
struct AccountModelTests {
    @Test("Аккаунт читается и показывается")
    func loadReadsAccount() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: AccountTests.accountResponse())
        let model = await makeModel()

        await model.load()

        #expect(StubURLProtocol.requestedPaths == ["/api/me/account"])
        #expect(model.info?.username == "demo")
        #expect(model.errorText == nil)
    }

    @Test("Неверный пароль показывается текстом сервера, а не «что-то пошло не так»")
    func wrongPasswordIsSaidByServer() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: AccountTests.accountResponse())
        StubURLProtocol.stub(status: 422, json: [
            "error": "Неверный пароль", "code": "account_wrong_password"
        ])
        let model = await makeModel()
        await model.load()
        model.email = "anna@example.com"
        model.emailPassword = "не тот"

        let saved = await model.saveEmail()

        #expect(saved == false)
        #expect(model.errorText == "Неверный пароль")
        // Пароль из формы стирается: он больше не сработает, и держать его в
        // поле после отказа незачем.
        #expect(model.emailPassword.isEmpty)
    }

    @Test("Смена пароля кладёт новую пару токенов и чистит форму")
    func passwordChangeReplacesTokens() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: AccountTests.accountResponse())
        StubURLProtocol.stub(status: 200, json: [
            "message": "Пароль изменён", "access_token": "access-2", "refresh_token": "refresh-2"
        ])
        let storage = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let model = await makeModel(storage: storage)
        await model.load()
        model.currentPassword = "старый"
        model.newPassword = "НовыйПароль123"

        let saved = await model.changePassword()

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == ["/api/me/account", "/api/me/password"])
        // Старая пара на сервере больше не работает: оставить её в Keychain
        // значит выкинуть человека из приложения через 15 минут.
        #expect(try storage.read() == StoredTokens(accessToken: "access-2", refreshToken: "refresh-2"))
        #expect(model.currentPassword.isEmpty)
        #expect(model.newPassword.isEmpty)
    }

    @Test("Новый пароль короче восьми символов уходит на сервер: правила у него свои")
    func shortPasswordGoesToServer() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: AccountTests.accountResponse())
        StubURLProtocol.stub(status: 422, json: [
            "error": "Пароль слишком короткий", "code": "register_password_short"
        ])
        let model = await makeModel()
        await model.load()
        model.currentPassword = "старый"
        model.newPassword = "коротк"

        let saved = await model.changePassword()

        #expect(saved == false)
        #expect(StubURLProtocol.requestedPaths == ["/api/me/account", "/api/me/password"])
        #expect(model.errorText == "Пароль слишком короткий")
    }

    @Test("Без текущего пароля смена пароля не уходит: сервер всё равно её не примет")
    func emptyPasswordNeverGoes() async {
        StubURLProtocol.reset()
        let model = await makeModel()

        let saved = await model.changePassword()

        #expect(saved == false)
        #expect(model.errorText == "Введите текущий пароль")
        #expect(StubURLProtocol.requestedPaths.isEmpty)
    }

    @Test("Удаление аккаунта спрашивает, что с питомцами, и только потом удаляет")
    func deleteAsksBeforeItDeletes() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: AccountTests.accountResponse())
        StubURLProtocol.stub(status: 200, json: AccountTests.deletionResponse())
        StubURLProtocol.stub(status: 200, json: ["message": "Аккаунт удалён"])
        let model = await makeModel()
        await model.load()

        await model.prepareDeletion()
        #expect(StubURLProtocol.requestedPaths == ["/api/me/account", "/api/me/account/deletion"])
        #expect(model.plan?.transferred.map(\.name) == ["Рекс"])

        model.deletePassword = "пароль"
        await model.deleteAccount()

        #expect(StubURLProtocol.requestedPaths == [
            "/api/me/account",
            "/api/me/account/deletion",
            "/api/me/account"
        ])
        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
        // Удалённого аккаунта на устройстве быть не должно: приложение
        // возвращается на экран входа, иначе следующий запрос был бы 401.
        #expect(model.app.state == .signedOut)
    }

    @Test("Без пароля аккаунт не удаляется: это подтверждение, а не кнопка")
    func deleteWithoutPasswordDoesNothing() async {
        StubURLProtocol.reset()
        let model = await makeModel()

        await model.deleteAccount()

        #expect(model.app.state != .signedOut)
        #expect(model.errorText == "Введите пароль")
        #expect(StubURLProtocol.requestedPaths.isEmpty)
    }

    private func makeModel(
        storage: InMemoryTokenStorage = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
    ) async -> AccountModel {
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: storage)
        await auth.restore()
        return AccountModel(
            client: APIClient(baseURL: baseURL, urlSession: session, auth: auth),
            auth: auth,
            app: AppModel(auth: auth, baseURL: baseURL, urlSession: session, defaults: TestSupport.makeDefaults())
        )
    }
}
