import Foundation
@testable import Petzy
import Testing

/// Ссылка для врача открывается в браузере, значит её адрес — адрес веба, а не
/// API. На стенде это разные порты (5002 и 3000), и ссылка от API отвечает 404:
/// человек отправлял врачу битый адрес.
@Suite("Ссылка на медкарту")
struct ShareLinkTests {
    @Test("Адрес ссылки берётся от веба, а не от API")
    func linkUsesWebBase() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "path": "/share/medical/tok",
            "token": "tok",
            "share": ["id": "s1", "expires_at": "2026-10-28T16:29:22Z"]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let share = try await MedicalCardAPI.createShare(
            client,
            petID: "p1",
            days: 7,
            webBase: #require(URL(string: "http://localhost:3000"))
        )

        #expect(share.url?.absoluteString == "http://localhost:3000/share/medical/tok")
    }

    /// В проде API и сайт живут на одном адресе, поэтому по умолчанию веб это
    /// он и есть: ничего не настроено — ссылка всё равно правильная.
    @Test("Без своего адреса веб совпадает с API")
    func webDefaultsToAPI() throws {
        let api = try #require(URL(string: "https://petzy.duckdns.org"))

        #expect(AppConfig.resolveWebBase(api: api, configured: nil) == api)
    }

    @Test("Настроенный адрес веба сильнее адреса API")
    func configuredWebWins() throws {
        let api = try #require(URL(string: "http://localhost:5002"))
        let site = try #require(URL(string: "http://localhost:3000"))

        #expect(AppConfig.resolveWebBase(api: api, configured: site.absoluteString) == site)
    }
}
