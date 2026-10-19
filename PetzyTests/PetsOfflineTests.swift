import Foundation
@testable import Petzy
import Testing

/// Питомец без связи. Форма питомца уходит multipart'ом, и очередь должна
/// держать такое тело: иначе питомец, заведённый в метро, до сервера не
/// дойдёт, а потеряется молча.
@Suite("Питомцы: без связи")
@MainActor
struct PetsOfflineTests {
    @Test("Новый питомец без связи встаёт в очередь под своим именем")
    func newPetWaitsInQueue() async {
        StubURLProtocol.reset()
        StubURLProtocol.stubOffline()
        let offline = makeOffline()
        let model = await makeModel(petID: nil, offline: offline)
        model.draft.name = "Рекс"

        let saved = await model.save(photo: nil, removePhoto: false)

        #expect(saved)
        #expect(offline.pendingPets.count == 1)
        let write = offline.pendingPets.first
        #expect(write?.title == "Рекс")
        #expect(write?.method == "POST")
        #expect(write?.path == "/api/pets")
        #expect(write?.contentType?.contains("multipart/form-data") == true)
        let body = bodyText(write?.payload)
        #expect(body.contains("name=\"local_id\""))
        #expect(body.contains("name=\"name\""))
        #expect(body.contains("Рекс"))
    }

    @Test("Питомец из очереди уходит на сервер multipart'ом")
    func queuedPetReachesServer() async {
        StubURLProtocol.reset()
        StubURLProtocol.stubOffline()
        let offline = makeOffline()
        let model = await makeModel(petID: nil, offline: offline)
        model.draft.name = "Рекс"
        _ = await model.save(photo: nil, removePhoto: false)
        #expect(offline.pendingCount == 1)

        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: PetProfileTests.cardResponse())
        let refused = await offline.flush(using: client())

        #expect(refused.isEmpty)
        #expect(offline.pendingCount == 0)
        #expect(StubURLProtocol.requestedPaths == ["/api/pets"])
        #expect(StubURLProtocol.requests.first?.httpMethod == "POST")
        let type = StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Content-Type")
        #expect(type?.contains("multipart/form-data") == true)
    }

    @Test("Правка карточки без связи встаёт в очередь с той версией, что видел человек")
    func petEditWaitsInQueue() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        StubURLProtocol.stubOffline()
        let offline = makeOffline()
        let model = await makeModel(petID: "p1", offline: offline)
        await model.load()
        model.draft.breed = "Овчарка"

        let saved = await model.save(photo: nil, removePhoto: false)

        #expect(saved)
        #expect(offline.pendingPets.count == 1)
        let write = offline.pendingPets.first
        #expect(write?.method == "PUT")
        #expect(write?.path == "/api/pets/p1")
        let body = bodyText(write?.payload)
        #expect(body.contains("name=\"breed\""))
        #expect(body.contains("Овчарка"))
    }

    @Test("Вторая правка заменяет первую: два запроса с одной версией сочлись бы отказом")
    func secondEditReplacesFirst() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        StubURLProtocol.stubOffline()
        StubURLProtocol.stubOffline()
        let offline = makeOffline()
        let model = await makeModel(petID: "p1", offline: offline)
        await model.load()
        model.draft.breed = "Овчарка"
        _ = await model.save(photo: nil, removePhoto: false)
        model.draft.breed = "Ладонь"
        _ = await model.save(photo: nil, removePhoto: false)

        #expect(offline.pendingPets.count == 1)
        let body = bodyText(offline.pendingPets.first?.payload)
        #expect(body.contains("Ладонь"))
    }

    private func makeOffline() -> OfflineState {
        OfflineState(store: LocalStore(url: TestSupport.tempStoreURL()))
    }

    private func makeModel(petID: String?, offline: OfflineState) async -> PetProfileModel {
        await PetProfileModel(client: client(), petID: petID, offline: offline)
    }

    private func client() async -> APIClient {
        await MedicationsTests.client(session: StubURLProtocol.makeSession())
    }

    private func bodyText(_ payload: Data?) -> String {
        String(data: payload ?? Data(), encoding: .utf8) ?? ""
    }
}
