import Foundation
@testable import Petzy
import Testing

/// Копия дневника принадлежит тому, кто её положил. На общем устройстве
/// следующий вошедший не должен видеть чожой дневник: человек вошёл под
/// своим именем, а на экране вдруг чужой Рекс и чужие записи.
@MainActor
@Suite("Офлайн: чужой дневник")
struct OfflineOwnerTests {
    /// Два человека на одном устройстве: первый оставил копию, второй вошёл
    /// под своим именем и без связи не должен увидеть чужой дневник.
    @Test("Чужой дневник из копии не показывается")
    func foreignDiaryIsNotShown() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: Self.tempURL())
        // Первый человек работал с приложением: копия его.
        let first = await Self.model(store: store)
        first.select(petID: "p1")
        StubURLProtocol.stub(status: 200, json: [
            "message": "Вы вошли", "access_token": "access-1", "refresh_token": "refresh-1"
        ])
        StubURLProtocol.stub(status: 200, json: ["is_admin": false, "username": "petr"])
        await first.signIn(username: "petr", password: "secret")
        StubURLProtocol.stub(status: 200, json: ["pets": [Self.pet]])
        await first.loadPets()
        #expect(
            store.load().pets.count == 1,
            "копия не записалась: \(StubURLProtocol.requestedPaths)"
        )

        // Второй человек вошёл на том же устройстве, а сети нет.
        let second = await Self.model(store: store)
        second.select(petID: "p1")
        StubURLProtocol.stub(status: 200, json: [
            "message": "Вы вошли", "access_token": "access-2", "refresh_token": "refresh-2"
        ])
        StubURLProtocol.stub(status: 200, json: ["is_admin": false, "username": "anna"])
        await second.signIn(username: "anna", password: "secret")
        StubURLProtocol.stubOffline()

        await second.loadPets()
        await second.loadFeed()

        #expect(second.pets.isEmpty, "чужой питомец показан из копии")
        #expect(second.feedItems.isEmpty, "чужие записи показаны из копии")
    }

    /// Свой дневник из копии показывается: без связи человек должен видеть то,
    /// что видел.
    @Test("Свой дневник из копии показывается")
    func ownDiaryIsShown() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: Self.tempURL())
        let model = await Self.model(store: store)
        model.select(petID: "p1")
        StubURLProtocol.stub(status: 200, json: [
            "message": "Вы вошли", "access_token": "access-1", "refresh_token": "refresh-1"
        ])
        StubURLProtocol.stub(status: 200, json: ["is_admin": false, "username": "anna"])
        await model.signIn(username: "anna", password: "secret")
        // Связь была: копия обновилась и стала его.
        StubURLProtocol.stub(status: 200, json: ["pets": [Self.pet]])
        await model.loadPets()
        // Связи нет.
        StubURLProtocol.stubOffline()

        await model.loadPets()

        #expect(model.pets.map(\.name) == ["Рекс"], "свой питомец не показан из копии")
    }

    /// Выход из аккаунта уносит дневник с устройства: на общем телефоне
    /// чужой дневник видеть не должен никто.
    @Test("Выход стирает копию дневника")
    func signOutClearsDiary() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: Self.tempURL())
        let model = await Self.model(store: store)
        model.select(petID: "p1")
        StubURLProtocol.stub(status: 200, json: [
            "message": "Вы вошли", "access_token": "access-1", "refresh_token": "refresh-1"
        ])
        StubURLProtocol.stub(status: 200, json: ["is_admin": false, "username": "anna"])
        await model.signIn(username: "anna", password: "secret")
        StubURLProtocol.stub(status: 200, json: ["pets": [Self.pet]])
        await model.loadPets()
        #expect(
            store.load().pets.count == 1,
            "копия не записалась: \(StubURLProtocol.requestedPaths)"
        )

        model.signOut()

        #expect(store.load().pets.isEmpty, "после выхода дневник остался на устройстве")
        #expect(store.load().feed.isEmpty, "после выхода записи остались на устройстве")
    }

    // MARK: - Образцы

    static let pet: [String: Any] = [
        "_id": "p1", "name": "Рекс", "species": "dog", "breed": "", "gender": ""
    ]

    static func model(store: LocalStore) async -> AppModel {
        await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
    }

    static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("petzy-offline-owner-\(UUID().uuidString).json")
    }
}
