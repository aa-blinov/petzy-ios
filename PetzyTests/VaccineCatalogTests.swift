import Foundation
@testable import Petzy
import Testing

/// Каталог прививок в форме записи. Он приходит с сервера, потому что именно
/// сервер знает, что за прививка чему соответствует: его же правило читает
/// смену марки как повтор. Свои семь строк в приложении были бы второй
/// копией этого правила и разошлись бы с ним при первом же изменении.
@Suite("Медкарта: каталог прививок")
@MainActor
struct VaccineCatalogTests {
    @Test("Группы прививок отбираются по виду питомца")
    func groupsAreFilteredBySpecies() {
        let groups = Self.catalog

        #expect(VaccineCatalog.forSpecies("Собака", in: groups).map(\.key) == ["rabies", "dhpp", "lepto", "kennel"])
        #expect(VaccineCatalog.forSpecies("Кот", in: groups).map(\.key) == ["rabies", "fvrcp", "felv"])
    }

    @Test("Вид, которого в каталоге нет, получает общий список, а не пустой")
    func unknownSpeciesGetsGeneralList() {
        // У попугая в справочнике нет ни одной группы, и пустой выбор означал
        // бы, что прививку выбрать нечем.
        #expect(VaccineCatalog.forSpecies("Попугай", in: Self.catalog).map(\.key) == ["rabies"])
    }

    @Test("Группа, уже выбранная в записи, остаётся в списке, даже если виду не подходит")
    func chosenGroupStaysVisible() {
        let picked = VaccineCatalog.forSpecies("Кот", in: Self.catalog, keeping: "dhpp")

        #expect(picked.map(\.key) == ["rabies", "fvrcp", "felv", "dhpp"])
    }

    @Test("Группа читается словами: название и от чего она")
    func groupReadsInWords() {
        let group = Self.catalog[1]

        #expect(group.text == "Комплексная для собак, Чума, аденовирус, парвовирус, парагрипп")
        #expect(VaccineGroup(key: "rabies", label: "Бешенство", detail: "", species: []).text == "Бешенство")
    }

    @Test("Каталог один раз читается и лежит в модели, а не в форме")
    func catalogIsInModel() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, json: ["groups": [
            ["key": "rabies", "label": "Бешенство", "detail": "", "species": ["dog", "other"]]
        ]])
        let model = try await makeModel()
        await model.load()

        await model.loadCatalog()

        #expect(model.catalog.map(\.key) == ["rabies"])
    }

    @Test("Каталог не пришёл: прививку всё равно можно завести, просто без защиты")
    func failedCatalogIsNotAnError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 500, json: ["success": false, "error": "Справочник недоступен"])
        let model = try await makeModel()
        await model.load()

        await model.loadCatalog()

        #expect(model.catalog.isEmpty)
    }

    @Test("Уже загруженный каталог второй раз не читается")
    func catalogIsReadOnce() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, json: ["groups": [
            ["key": "rabies", "label": "Бешенство", "detail": "", "species": ["dog"]]
        ]])
        let model = try await makeModel()
        await model.load()

        await model.loadCatalog()
        await model.loadCatalog()

        #expect(StubURLProtocol.requestedPaths == [
            "/api/pets/p1/medical-card",
            "/api/vaccines/catalog"
        ])
    }

    private func makeModel() async throws -> MedicalCardModel {
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let tokens = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: tokens)
        await auth.restore()
        return MedicalCardModel(client: APIClient(baseURL: baseURL, urlSession: session, auth: auth), petID: "p1")
    }

    /// Тот же список, что с живого стенда: виды животных приходят ключами
    /// (`dog`), а карта отдаёт их словами («Собака»), и это разные вещи.
    static let catalog: [VaccineGroup] = [
        VaccineGroup(key: "rabies", label: "Бешенство", detail: "", species: ["dog", "cat", "rabbit", "other"]),
        VaccineGroup(
            key: "dhpp",
            label: "Комплексная для собак",
            detail: "Чума, аденовирус, парвовирус, парагрипп",
            species: ["dog"]
        ),
        VaccineGroup(key: "lepto", label: "Лептоспироз", detail: "", species: ["dog"]),
        VaccineGroup(key: "kennel", label: "Питомниковый кашель", detail: "Бордетеллёз и парагрипп", species: ["dog"]),
        VaccineGroup(key: "fvrcp", label: "Комплексная для кошек", detail: "Панлейкопения", species: ["cat"]),
        VaccineGroup(key: "felv", label: "Лейкоз кошек", detail: "", species: ["cat"])
    ]
}
