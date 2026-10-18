import Foundation
@testable import Petzy
import Testing

/// Оболочка приложения: список питомцев и выбор того, чей дневник открыт.
/// Выбор должен переживать перезапуск, а если питомца удалили на другом
/// устройстве, приложение обязано открыться на первом, а не на пустом экране.
@MainActor
@Suite("Выбранный питомец")
struct AppModelTests {
    /// Настройки с отдельным именем, чтобы тест не затирал то, что на симуляторе.
    private func makeDefaults() -> UserDefaults {
        let suite = "AppModelTests.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        return UserDefaults(suiteName: suite)!
    }

    /// Модель с залогиненной сессией. Без токенов APIClient отвечает `.signedOut`
    /// и в сеть не ходит вовсе: тест проходил бы, ни разу не проверив запрос.
    private func makeModel(defaults: UserDefaults) async -> AppModel {
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let auth = AuthSession(
            baseURL: URL(string: "http://localhost:5002")!,
            urlSession: session,
            storage: InMemoryTokenStorage(
                tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
            )
        )
        await auth.restore()
        // Тот же заглушечный сеанс отдаём и клиенту: иначе запросы уйдут
        // в настоящий стенд, а тест будет зелёным, не проверив ничего.
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        return AppModel(auth: auth, baseURL: baseURL, urlSession: session, defaults: defaults)
    }

    private func loaded(_ state: PetsState) -> Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    private func stubPets(_ pets: [[String: Any]]) {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["pets": pets])
    }

    @Test("Выбор питомца переживает перезапуск")
    func selectionSurvivesRestart() async {
        StubURLProtocol.reset()
        let defaults = makeDefaults()
        let before = await makeModel(defaults: defaults)

        await before.select(petID: "pet-2")

        // Те же настройки, новый экземпляр модели. Это и есть перезапуск.
        let afterRestart = await makeModel(defaults: defaults)
        #expect(afterRestart.selectedPetID == "pet-2")
    }

    @Test("Без сохранённого выбора открывается первый питомец")
    func firstPetIsSelectedByDefault() async {
        stubPets([
            ["_id": "pet-1", "name": "Барсик", "species": "cat"],
            ["_id": "pet-2", "name": "Шарик", "species": "dog"]
        ])
        let model = await makeModel(defaults: makeDefaults())

        await model.loadPets()

        #expect(model.pets.map(\.id) == ["pet-1", "pet-2"])
        #expect(model.selectedPetID == "pet-1")
        #expect(loaded(model.petsState))
        #expect(StubURLProtocol.requestedPaths == ["/api/pets"])
    }

    @Test("Выбранного питомца удалили на другом устройстве, открывается первый")
    func fallsBackWhenSelectedPetIsGone() async {
        stubPets([["_id": "pet-1", "name": "Барсик", "species": "cat"]])
        let defaults = makeDefaults()
        let before = await makeModel(defaults: defaults)
        await before.select(petID: "pet-gone")

        let afterRestart = await makeModel(defaults: defaults)
        await afterRestart.loadPets()

        #expect(afterRestart.selectedPetID == "pet-1")
    }

    @Test("Питомцев нет, выбирать нечего")
    func noPetsMeansNoSelection() async {
        stubPets([])
        let model = await makeModel(defaults: makeDefaults())

        await model.loadPets()

        #expect(model.selectedPetID == nil)
        #expect(model.pets.isEmpty)
        #expect(loaded(model.petsState))
    }

    /// Сессия умерла, пока список грузился. Молча показывать ошибку нельзя:
    /// пользователь будет думать, что сломался бэкенд, и ломиться в поддержку.
    @Test("Сессия закончилась, приложение возвращает экран входа")
    func deadSessionGoesBackToLogin() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Сессия закончилась"])
        StubURLProtocol.stub(status: 401, json: ["error": "refresh-токен недействителен"])
        let model = await makeModel(defaults: makeDefaults())

        await model.loadPets()

        #expect(StubURLProtocol.requestedPaths == ["/api/pets", "/api/auth/refresh"])
        #expect(model.state == .signedOut)
    }
}
