import Foundation
@testable import Petzy
import Testing

/// Страница другого человека: кто он и какие питомцы у вас общие. Видно только
/// то, что сервер отдаёт соседу по питомцу: ни почты, ни прав.
@Suite("Страница другого человека")
struct UserProfileTests {
    @Test("Профиль читается логином в пути")
    func profileUsesUsernameInPath() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "username": "family",
            "full_name": "Анна",
            "created_at": "2026-10-03T07:52:47Z",
            "shared_pets": [["id": "p1", "name": "Рекс"]]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let profile = try await UsersAPI.profile(client, username: "family")

        #expect(StubURLProtocol.requestedPaths == ["/api/users/family/profile"])
        #expect(profile.username == "family")
        #expect(profile.fullName == "Анна")
        #expect(profile.sharedPets.map(\.name) == ["Рекс"])
    }

    /// Логин может быть с точкой и подчёркиванием: в пути он должен остаться
    /// собой, а не превратиться в другой адрес.
    @Test("Логин экранируется в пути")
    func usernameIsEscaped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "username": "a b", "created_at": "2026-01-01T00:00:00Z", "shared_pets": []
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await UsersAPI.profile(client, username: "a b")

        #expect(StubURLProtocol.requestedPaths == ["/api/users/a%20b/profile"])
    }

    /// Имени может не быть, и тогда в заголовке стоит логин: пустая строка
    /// выглядела бы поломкой.
    @Test("Без имени показывается логин")
    func missingNameFallsBackToLogin() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "username": "family", "created_at": "2026-10-03T07:52:47Z", "shared_pets": []
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let profile = try await UsersAPI.profile(client, username: "family")

        #expect(profile.title == "family")
    }
}
