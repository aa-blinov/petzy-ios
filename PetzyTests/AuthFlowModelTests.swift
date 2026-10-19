import Foundation
@testable import Petzy
import Testing

/// Модель входа: что происходит после нажатия и куда попадают токены.
@Suite("Вход: модель")
@MainActor
struct AuthFlowModelTests {
    @Test("Регистрация кладёт токены и возвращает человека в приложение")
    func registerSignsIn() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "message": "Аккаунт создан", "access_token": "access-9", "refresh_token": "refresh-9"
        ])
        let storage = InMemoryTokenStorage(tokens: nil)
        let model = await makeModel(storage: storage)
        var draft = RegistrationDraft()
        draft.username = "anna"
        draft.fullName = "Анна"
        draft.password = "Пароль1234"
        draft.consent = true
        model.draft = draft

        let registered = await model.register()

        #expect(registered)
        #expect(StubURLProtocol.requestedPaths == ["/api/auth/register"])
        #expect(try storage.read() == StoredTokens(accessToken: "access-9", refreshToken: "refresh-9"))
        #expect(model.app.state == .signedIn)
    }

    /// Подсказка стоит под полем, а не над формой: человек должен видеть,
    /// что именно заполнить, и серверу такая форма не идёт.
    @Test("Пустая форма называет проблему под полем и никуда не идёт")
    func emptyFormNamesFieldProblems() async {
        StubURLProtocol.reset()
        let model = await makeModel()

        let registered = await model.register()

        #expect(registered == false)
        #expect(model.problems == [.username, .fullName, .password, .consent])
        #expect(model.errorText == nil)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("Отказ регистрации показывает текст сервера и никого не пускает")
    func registerFailureKeepsSignedOut() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 422, json: [
            "error": "Этот логин уже занят", "code": "register_username_taken"
        ])
        let model = await makeModel()
        var draft = RegistrationDraft()
        draft.username = "anna"
        draft.fullName = "Анна"
        draft.password = "Пароль1234"
        draft.consent = true
        model.draft = draft

        let registered = await model.register()

        #expect(registered == false)
        #expect(model.errorText == "Этот логин уже занят")
        #expect(model.app.state != .signedIn)
    }

    @Test("Истёкшая ссылка сброса говорит об этом до ввода пароля")
    func deadResetLinkIsSaidFirst() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["valid": false])
        let model = await makeModel()

        await model.checkResetLink("истёкшая")

        #expect(StubURLProtocol.requestedPaths == ["/api/auth/password/reset/check"])
        #expect(model.errorText == "Ссылка больше не работает, попросите новую в письме")
    }

    @Test("Живая ссылка сброса входит в аккаунт с новым паролем")
    func resetPasswordSignsIn() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["valid": true])
        StubURLProtocol.stub(status: 200, json: [
            "message": "Пароль обновлён", "access_token": "access-7", "refresh_token": "refresh-7"
        ])
        let storage = InMemoryTokenStorage(tokens: nil)
        let model = await makeModel(storage: storage)

        await model.checkResetLink("живая")
        model.password = "НовыйПароль123"
        let done = await model.resetPassword(token: "живая")

        #expect(done)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/auth/password/reset/check",
            "/api/auth/password/reset"
        ])
        #expect(try storage.read() == StoredTokens(accessToken: "access-7", refreshToken: "refresh-7"))
        #expect(model.app.state == .signedIn)
    }

    @Test("Просьба о ссылке всегда отвечает одинаково: иначе по ней можно проверить, кто записан")
    func forgotPasswordKeepsQuiet() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "message": "Если такой аккаунт есть, письмо с ссылкой уже отправлено", "success": true
        ])
        let model = await makeModel()

        await model.forgotPassword(login: "demo")

        #expect(StubURLProtocol.requestedPaths == ["/api/auth/password/forgot"])
        #expect(model.notice == "Если такой аккаунт есть, письмо с ссылкой уже отправлено")
        #expect(model.errorText == nil)
    }

    @Test("Согласие снимает требование и обновляет аккаунт")
    func consentClearsTheQuestion() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "policy_version": "2026-09-28.3", "operator": "", "contact_email": "",
            "server_location": "", "backups_kept_days": 3
        ])
        StubURLProtocol.stub(status: 200, json: ["message": "Согласие сохранено", "success": true])
        // Согласие спрашивают у человека, который уже вошёл: маршрут требует
        // сессии, и без токена запрос не уйдёт вовсе.
        let model = await makeModel(storage: InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        ))

        await model.loadPolicy()
        let agreed = await model.acceptPolicy()

        #expect(StubURLProtocol.requestedPaths == ["/api/legal", "/api/me/privacy-consent"])
        #expect(agreed)
        #expect(model.policy?.version == "2026-09-28.3")
    }

    private func makeModel(
        storage: InMemoryTokenStorage = InMemoryTokenStorage(tokens: nil)
    ) async -> AuthFlowModel {
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: storage)
        await auth.restore()
        let app = AppModel(auth: auth, baseURL: baseURL, urlSession: session, defaults: TestSupport.makeDefaults())
        return AuthFlowModel(client: APIClient(baseURL: baseURL, urlSession: session, auth: auth), auth: auth, app: app)
    }
}
