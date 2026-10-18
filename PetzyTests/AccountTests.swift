import Foundation
@testable import Petzy
import Testing

/// Аккаунт: почта, пароль и превью удаления. Фикстура снята с живого стенда.
@Suite("Аккаунт: разбор ответа")
struct AccountTests {
    @Test("Аккаунт читается из ответа сервера")
    func accountIsMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.accountResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let info = try await AccountAPI.account(client)

        #expect(StubURLProtocol.requestedPaths == ["/api/me/account"])
        #expect(info.username == "demo")
        #expect(info.fullName == "Анна")
        #expect(info.email == "")
        #expect(info.emailVerified == false)
        #expect(info.pendingEmail == "demo@example.com")
        #expect(info.mailEnabled)
        #expect(info.privacyConsentNeeded == false)
    }

    @Test("Новая пара токенов после смены пароля кладётся на устройство")
    func newTokensReplaceOldOnes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "message": "Пароль изменён",
            "access_token": "access-2",
            "refresh_token": "refresh-2"
        ])
        let storage = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let auth = try AuthSession(
            baseURL: #require(URL(string: "http://localhost:5002")),
            urlSession: session,
            storage: storage
        )
        await auth.restore()

        let fresh = try await AccountAPI.changePassword(
            APIClient(baseURL: #require(URL(string: "http://localhost:5002")), urlSession: session, auth: auth),
            current: "старый",
            new: "НовыйПароль123"
        )
        try await auth.replaceTokens(fresh)

        #expect(try storage.read() == StoredTokens(accessToken: "access-2", refreshToken: "refresh-2"))
    }

    @Test("Пустая почта убирает адрес, а не оставляет его как есть")
    func emptyEmailRemovesAddress() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.accountResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await AccountAPI.changeEmail(client, email: "", password: "пароль")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(StubURLProtocol.requestedPaths == ["/api/me/email"])
        #expect(body["email"] as? String == "")
        #expect(body["password"] as? String == "пароль")
    }

    @Test("Смена пароля уходит с текущим и новым")
    func passwordChangeSendsBoth() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "message": "Пароль изменён", "access_token": "a", "refresh_token": "r"
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await AccountAPI.changePassword(client, current: "старый", new: "новый")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(StubURLProtocol.requests.last?.httpMethod == "PUT")
        #expect(StubURLProtocol.requestedPaths == ["/api/me/password"])
        #expect(body["current_password"] as? String == "старый")
        #expect(body["new_password"] as? String == "новый")
    }

    @Test("Превью удаления различает удалятся, перейдут и останутся")
    func deletionPlanIsRead() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.deletionResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let plan = try await AccountAPI.deletionPlan(client)

        #expect(StubURLProtocol.requestedPaths == ["/api/me/account/deletion"])
        #expect(plan.canDelete)
        #expect(plan.deleted.map(\.name) == ["Писька"])
        #expect(plan.transferred.map(\.name) == ["Рекс"])
        #expect(plan.transferred.first?.person == "family")
        #expect(plan.left.map(\.name) == ["Шарик"])
        #expect(plan.left.first?.person == "anna")
    }

    /// Администратора удалить нельзя, и превью об этом говорит само: без
    /// `can_delete` экран предлагал бы кнопку, которая всегда откажет.
    @Test("Аккаунт администратора удалить нельзя")
    func adminCannotBeDeleted() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "can_delete": false, "deleted": [], "transferred": [], "left": []
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let plan = try await AccountAPI.deletionPlan(client)

        #expect(plan.canDelete == false)
    }

    @Test("Вопрос об удалении называет питомцев и того, кому они перейдут")
    func deletionWarningIsSaidInWords() {
        let plan = AccountDeletionPlan(
            canDelete: true,
            deleted: [DeletionPet(id: "3", name: "Писька", person: nil)],
            transferred: [
                DeletionPet(id: "1", name: "Рекс", person: "family"),
                DeletionPet(id: "2", name: "Мурзик", person: "family")
            ],
            left: [DeletionPet(id: "4", name: "Шарик", person: "anna")]
        )

        // После «к» идёт человек, а питомцы за ним: «перейдут к Рекс» было бы
        // не по-русски.
        #expect(
            plan.warning
                == "Вместе с аккаунтом: удалятся Писька, перейдут к family: Рекс и Мурзик, "
                + "пропадёт доступ к Шарик"
        )
    }

    @Test("Пустое превью не молчит об удалении")
    func emptyPlanStillWarns() {
        let plan = AccountDeletionPlan(canDelete: true, deleted: [], transferred: [], left: [])

        #expect(plan.isEmpty)
        #expect(plan.warning == "Аккаунт удалится безвозвратно")
    }

    /// Настоящий ответ стенда на `GET /api/me/account`.
    static func accountResponse() -> [String: Any] {
        [
            "username": "demo",
            "full_name": "Анна",
            "email": "",
            "email_verified": false,
            "pending_email": "demo@example.com",
            "mail_enabled": true,
            "privacy_consent_needed": false
        ]
    }

    /// Настоящий ответ стенда на `GET /api/me/account/deletion`, дополненный
    /// ветками, которых у демо-аккаунта нет.
    static func deletionResponse() -> [String: Any] {
        [
            "can_delete": true,
            "deleted": [["id": "p3", "name": "Писька"]],
            "transferred": [["id": "p1", "name": "Рекс", "new_owner": "family"]],
            "left": [["id": "p2", "name": "Шарик", "owner": "anna"]]
        ]
    }
}
