import Foundation
@testable import Petzy
import Testing

/// Сохранение карточки питомца. Форма отправляется multipart'ом всегда, даже
/// когда фото не менялось: так пустая порода значит «убери», а не «не трогай».
/// Проверено на живом стенде: `breed=` чистит поле, а `is_neutered=` с пустой
/// строкой сервер отклоняет с 422.
@Suite("Питомцы: сохранение")
struct PetProfileWriteTests {
    @Test("Карточка уходит одним запросом multipart с полями и файлом")
    func saveSendsOneMultipartRequest() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var draft = PetDraft(name: "Рекс")
        draft.species = "dog"
        draft.breed = "Лабрадор"
        draft.gender = .male
        draft.neutering = .done
        draft.healthNotes = "Аллергия на курицу"

        _ = try await PetsAPI.update(
            client,
            id: "p1",
            draft: draft,
            photo: UploadFile(name: "фото.png", contentType: "image/png", data: Data("%PNG".utf8)),
            removePhoto: false
        )

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1"])
        let body = bodyText(StubURLProtocol.requests.last)
        #expect(body.contains("name=\"name\""))
        #expect(body.contains("Рекс"))
        #expect(body.contains("name=\"species\""))
        #expect(body.contains("Лабрадор"))
        #expect(body.contains("name=\"is_neutered\""))
        #expect(body.contains("true"))
        #expect(body.contains("name=\"photo_file\""))
        #expect(body.contains("filename=\"фото.png\""))
    }

    @Test("Новый питомец идёт в POST, правка в PUT")
    func createAndUpdateUseDifferentMethods() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: PetProfileTests.cardResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await PetsAPI.create(client, draft: PetDraft(name: "Рекс"), photo: nil)

        #expect(StubURLProtocol.requests.first?.httpMethod == "POST")
        #expect(StubURLProtocol.requestedPaths == ["/api/pets"])
    }

    @Test("«Не указано» про кастрацию не уходит: сервер такую строку не понимает")
    func unknownNeuteringIsNotSent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await PetsAPI.update(client, id: "p1", draft: PetDraft(name: "Рекс"), photo: nil, removePhoto: false)

        let body = bodyText(StubURLProtocol.requests.last)
        #expect(body.contains("is_neutered") == false)
    }

    @Test("Пустая порода уходит пустой строкой, иначе сервер её не уберёт")
    func clearedBreedIsSentAsEmpty() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var draft = PetDraft(name: "Рекс")
        draft.breed = ""

        _ = try await PetsAPI.update(client, id: "p1", draft: draft, photo: nil, removePhoto: false)

        let body = bodyText(StubURLProtocol.requests.last)
        #expect(body.contains("name=\"breed\""))
    }

    @Test("Удаление фото идёт отдельным полем, а не пустым файлом")
    func removePhotoIsItsOwnField() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await PetsAPI.update(client, id: "p1", draft: PetDraft(name: "Рекс"), photo: nil, removePhoto: true)

        let body = bodyText(StubURLProtocol.requests.last)
        #expect(body.contains("name=\"remove_photo\""))
        #expect(body.contains("photo_file") == false)
    }

    @Test("Дата рождения уходит только когда её выбрали")
    func birthDateIsSentOnlyWhenPicked() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        StubURLProtocol.stub(status: 200, json: PetProfileTests.cardResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var draft = PetDraft(name: "Рекс")
        // Полдень: сдвиг на любой часовой пояс не переносит дату на соседний
        // день, и проверка не зависит от того, где запущен тест.
        draft.birthDate = Calendar.current.date(from: DateComponents(year: 2001, month: 6, day: 15, hour: 12))

        _ = try await PetsAPI.update(client, id: "p1", draft: draft, photo: nil, removePhoto: false)
        let withDate = bodyText(StubURLProtocol.requests.first)
        draft.birthDate = nil
        _ = try await PetsAPI.update(client, id: "p1", draft: draft, photo: nil, removePhoto: false)
        let without = bodyText(StubURLProtocol.requests.last)

        #expect(withDate.contains("2001-06-15"))
        #expect(without.contains("birth_date") == false)
    }

    private func bodyText(_ request: URLRequest?) -> String {
        String(data: TestSupport.rawBody(of: request), encoding: .utf8) ?? ""
    }
}
