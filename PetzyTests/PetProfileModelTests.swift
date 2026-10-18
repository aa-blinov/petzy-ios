import Foundation
@testable import Petzy
import Testing

/// Модель «О питомце»: что показывает, что перечитывает и куда девается
/// удалённый питомец.
@Suite("Питомцы: модель")
@MainActor
struct PetProfileModelTests {
    @Test("Карточка читается и ложится в форму")
    func loadFillsDraft() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        let model = await makeModel()

        await model.load()

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1"])
        #expect(model.profile?.name == "Рекс")
        #expect(model.draft.name == "Рекс")
        #expect(model.draft.breed == "Лабрадор")
        #expect(model.draft.gender == .male)
        #expect(model.errorText == nil)
    }

    @Test("Новый питомец открывается пустым и запроса не делает")
    func newPetStartsEmpty() async {
        StubURLProtocol.reset()
        let model = await PetProfileModel(client: client(), petID: nil)

        await model.load()

        #expect(StubURLProtocol.requestedPaths.isEmpty)
        #expect(model.profile == nil)
        #expect(model.draft.name.isEmpty)
    }

    @Test("Ошибка чтения говорит серверным текстом, а не пустой карточкой")
    func loadFailureIsSaid() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 404, json: ["error": "Питомец не найден"])
        let model = await makeModel()

        await model.load()

        #expect(model.errorText == "Питомец не найден")
        #expect(model.profile == nil)
    }

    @Test("Удаление спрашивает, что пропадёт, и только потом удаляет")
    func deleteAsksBeforeItDeletes() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        StubURLProtocol.stub(status: 200, json: [
            "events": 264, "medical_records": 8, "documents": 3, "medications": 3
        ])
        let model = await makeModel()
        await model.load()

        await model.prepareDeletion()

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1", "/api/pets/p1/deletion-impact"])
        #expect(model.impact?.summary == "264 записи в ленте, 3 лекарства, 3 документа, 8 записей медкарты")
        #expect(model.isDeleted == false)
    }

    @Test("Удалённого питомца просят перечитать список: его больше нет")
    func deletedPetAsksToReloadList() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        StubURLProtocol.stub(status: 200, json: ["message": "Питомец удалён"])
        let model = await makeModel()
        await model.load()

        await model.delete()

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1", "/api/pets/p1"])
        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
        #expect(model.isDeleted)
    }

    @Test("Отказанное удаление оставляет питомца на месте")
    func failedDeleteKeepsPet() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        StubURLProtocol.stub(status: 403, json: ["error": "Это не ваш питомец"])
        let model = await makeModel()
        await model.load()

        await model.delete()

        #expect(model.isDeleted == false)
        #expect(model.errorText == "Это не ваш питомец")
    }

    @Test("Без имени питомец не уходит на сервер")
    func blankNameNeverReachesServer() async {
        StubURLProtocol.reset()
        let model = await makeModel()

        let saved = await model.save(photo: nil, removePhoto: false)

        #expect(saved == false)
        #expect(model.errorText == "Введите имя питомца")
        #expect(StubURLProtocol.requestedPaths.isEmpty)
    }

    @Test("Правка перечитывает карточку: сервер в ответе её не отдаёт")
    func updateReloadsCard() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        StubURLProtocol.stub(status: 200, json: ["message": "Данные питомца обновлены", "success": true])
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        let model = await makeModel()
        await model.load()

        let saved = await model.save(photo: nil, removePhoto: false)

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1", "/api/pets/p1", "/api/pets/p1"])
        #expect(StubURLProtocol.requests[1].httpMethod == "PUT")
        #expect(model.profile?.name == "Рекс")
        #expect(model.errorText == nil)
    }

    @Test("Новый питомец возвращает себя: список пора перечитать, питомца выбрать")
    func createdPetAsksToBeSelected() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: PetProfileTests.cardResponse())
        let model = await PetProfileModel(client: client(), petID: nil)
        model.draft.name = "Рекс"

        let saved = await model.save(photo: nil, removePhoto: false)

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == ["/api/pets"])
        #expect(model.createdID == "6ac0b44fc775325d197b84df")
        // Перечитывать карточку незачем: сервер вернул её в ответе на создание.
        #expect(model.profile?.name == "Рекс")
    }

    private func makeModel() async -> PetProfileModel {
        await PetProfileModel(client: client(), petID: "p1")
    }

    private func client() async -> APIClient {
        await MedicationsTests.client(session: StubURLProtocol.makeSession())
    }
}
