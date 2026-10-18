import Foundation
@testable import Petzy
import Testing

/// Вход, регистрация, восстановление пароля, согласие. Фикстуры сняты с
/// живого стенда.
@Suite("Вход и регистрация: разбор ответа")
struct AuthFlowTests {
    @Test("Регистрация открыта или закрыта, и это известно заранее")
    func registrationStatusIsRead() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["open": true, "mail_enabled": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let status = try await AuthAPI.registrationStatus(client)

        #expect(StubURLProtocol.requestedPaths == ["/api/auth/registration"])
        #expect(status.isOpen)
        #expect(status.mailEnabled)
        // Регистрация идёт до сессии: заголовка `Authorization` в ней быть
        // не должно, иначе бэкенд примет запрос за чужой.
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Новый аккаунт сразу даёт токены: отдельный вход не нужен")
    func registrationReturnsTokens() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "message": "Аккаунт создан",
            "access_token": "access-9",
            "refresh_token": "refresh-9"
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var draft = RegistrationDraft()
        draft.username = "anna"
        draft.fullName = "Анна"
        draft.password = "Пароль1234"
        draft.email = "anna@example.com"
        draft.consent = true

        let tokens = try await AuthAPI.register(client, draft: draft)

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(StubURLProtocol.requestedPaths == ["/api/auth/register"])
        #expect(body["username"] as? String == "anna")
        #expect(body["full_name"] as? String == "Анна")
        #expect(body["privacy_consent"] as? Bool == true)
        #expect(tokens.accessToken == "access-9")
        #expect(tokens.refreshToken == "refresh-9")
    }

    @Test("Пустая форма и несогласие не уходят: сервер всё равно их не примет")
    func emptyFormNeverGoes() {
        #expect(RegistrationDraft.problem(RegistrationDraft()) == "Введите логин")
        var draft = RegistrationDraft()
        draft.username = "anna"
        #expect(RegistrationDraft.problem(draft) == "Введите имя")
        draft.fullName = "Анна"
        #expect(RegistrationDraft.problem(draft) == "Придумайте пароль")
        draft.password = "Пароль1234"
        #expect(RegistrationDraft.problem(draft) == "Отметьте согласие с политикой")
        draft.consent = true
        #expect(RegistrationDraft.problem(draft) == nil)
    }

    @Test("Просьба о ссылке уходит с тем, что человек назвал")
    func forgotPasswordSendsLogin() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "message": "Если такой аккаунт есть, письмо с ссылкой уже отправлено", "success": true
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await AuthAPI.forgotPassword(client, login: "anna@example.com")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(StubURLProtocol.requestedPaths == ["/api/auth/password/forgot"])
        #expect(body["login"] as? String == "anna@example.com")
    }

    @Test("Ссылка сброса проверяется до того, как человек набрал пароль")
    func resetLinkIsChecked() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["valid": false])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let live = try await AuthAPI.resetLinkIsLive(client, token: "истёкшая")

        #expect(StubURLProtocol.requestedPaths == ["/api/auth/password/reset/check"])
        // Токен уходит закодированным. Сравниваем по смыслу, а не по таблице
        // кодирования: важно, что токен доехал целым.
        let query = StubURLProtocol.requests.last?.url?.query ?? ""
        #expect(query.removingPercentEncoding == "token=истёкшая")
        #expect(live == false)
    }

    @Test("Новый пароль по ссылке входит в аккаунт сразу")
    func resetPasswordReturnsTokens() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "message": "Пароль обновлён", "access_token": "access-7", "refresh_token": "refresh-7"
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let tokens = try await AuthAPI.resetPassword(client, token: "токен", password: "НовыйПароль123")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(StubURLProtocol.requestedPaths == ["/api/auth/password/reset"])
        #expect(body["token"] as? String == "токен")
        #expect(tokens.accessToken == "access-7")
    }

    @Test("Подтверждение почты говорит, что всё сошлось")
    func emailIsVerified() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["message": "Почта подтверждена", "success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await AuthAPI.verifyEmail(client, token: "токен")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(StubURLProtocol.requestedPaths == ["/api/auth/email/verify"])
        #expect(body["token"] as? String == "токен")
    }

    @Test("Политика приходит с сервера вместе с редакцией")
    func legalInfoIsRead() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "policy_version": "2026-09-28.3",
            "operator": "",
            "contact_email": "",
            "server_location": "",
            "backups_kept_days": 3
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let legal = try await AuthAPI.legalInfo(client)

        #expect(StubURLProtocol.requestedPaths == ["/api/legal"])
        #expect(legal.version == "2026-09-28.3")
        #expect(legal.backupsKeptDays == 3)
        // Сервер эти поля не заполняет, и строки «Кто обрабатывает данные: »
        // на экране быть не должно. Срок копий есть всегда.
        #expect(legal.facts == ["Резервные копии хранятся 3 дня"])
    }

    @Test("Согласие уходит с той редакцией, которую человек прочитал")
    func consentSendsVersion() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["message": "Согласие сохранено", "success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await AuthAPI.acceptPolicy(client, version: "2026-09-28.3")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(StubURLProtocol.requestedPaths == ["/api/me/privacy-consent"])
        #expect(body["version"] as? String == "2026-09-28.3")
    }

    /// Ссылка из письма открывает нужный экран. Пока у приложения нет подписи,
    /// письмо ведёт на веб-версию, но код разбора уже на месте и включится сам.
    @Test("Ссылка из письма разбирается в нужный экран")
    func linkFromLetterIsParsed() {
        func link(_ text: String) -> AppLink? {
            AppLink.parse(URL(string: text) ?? URL(fileURLWithPath: "/"))
        }

        #expect(link("petzy://reset-password?token=abc123") == .resetPassword(token: "abc123"))
        #expect(link("petzy://verify-email?token=xyz") == .verifyEmail(token: "xyz"))
        // Обычная веб-ссылка из письма открывает сайт, а не приложение.
        #expect(link("https://petzy.duckdns.org/reset-password?token=abc123") == nil)
        #expect(link("petzy://reset-password") == nil)
        #expect(link("petzy://about") == nil)
    }
}
