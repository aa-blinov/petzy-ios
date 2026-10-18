import Foundation
@testable import Petzy
import Testing

/// Разбор карточки питомца и домен «О питомце». Фикстура снята с живого
/// стенда: ключи там не те, что могло бы придуматься.
@Suite("Питомцы: карточка")
struct PetProfileTests {
    @Test("Карточка читается из ответа сервера")
    func cardIsMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.cardResponse())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let pet = try await PetsAPI.card(client, id: "6ac0b44fc775325d197b84df")

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/6ac0b44fc775325d197b84df"])
        #expect(pet.id == "6ac0b44fc775325d197b84df")
        #expect(pet.name == "Рекс")
        #expect(pet.healthNotes == "Аллергия на курицу")
        #expect(pet.breed == "Лабрадор")
        #expect(pet.species == "dog")
        #expect(pet.birthDate == "2021-08-01")
        #expect(pet.gender == .male)
        #expect(pet.neutering == .unknown)
        #expect(pet.currentUserIsOwner)
        // Подписанный адрес приходит целиком: телефон ходит по нему сам, без
        // токена, иначе подпись в запросе не появится.
        #expect(pet.photoURL?.absoluteString.contains("sig=") == true)
    }

    /// Заметки о здоровье приходят ключом `health_notes`, и в списке питомцев
    /// их нет. Пустая строка в фикстуре это скрывала: без `health_notes` в
    /// `CodingKeys` поле читалось как пустое, и на живом экране заметки
    /// пропадали сразу после сохранения, хотя на сервере они были.
    @Test("Заметки и вид читаются, даже когда сервер прислал пустое")
    func notesAndSpeciesAreMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "pet": [
                "_id": "p1",
                "name": "Рекс",
                "health_notes": "Аллергия на курицу",
                "species": "",
                "gender": "female",
                "is_neutered": true
            ]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let pet = try await PetsAPI.card(client, id: "p1")

        #expect(pet.healthNotes == "Аллергия на курицу")
        // Пустой вид это «не указан», а не значение, которому нету подписи:
        // в списке выбора вида пустая строка выглядела бы как ничем не
        // заполненное поле.
        #expect(pet.species == nil)
        #expect(pet.speciesTitle == nil)
        #expect(pet.gender == .female)
        #expect(pet.neutering == .done)
    }

    @Test("Питомец без фото: адреса нет, а не пустая строка")
    func photoMayBeMissing() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["pet": ["_id": "p1", "name": "Рекс"]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let pet = try await PetsAPI.card(client, id: "p1")

        #expect(pet.photoURL == nil)
        #expect(pet.species == nil)
        // Питомец, у которого доступ дали, карточку не правит: сервер и не
        // даст, а форма без этого поля обещала бы, что можно.
        #expect(pet.currentUserIsOwner == false)
    }

    @Test("Старые значения пола читаются как их нынешние названия")
    func legacyGenderIsMapped() {
        #expect(PetGender.known("Мужской") == .male)
        #expect(PetGender.known("Женский") == .female)
        #expect(PetGender.known("male") == .male)
        #expect(PetGender.known(nil) == .unknown)
        #expect(PetGender.known("") == .unknown)
        #expect(PetGender.known("что-то своё") == .unknown)
    }

    @Test("У рыбы не спрашивают про кастрацию")
    func neuteringIsAskedAboutForMammalsOnly() {
        #expect(PetSpecies.breedTitle(for: "dog") == "Порода")
        #expect(PetSpecies.breedTitle(for: "bird") == "Вид")
        #expect(PetSpecies.breedTitle(for: "ferret") == "Окрас")
        #expect(PetSpecies.asksAboutNeutering("dog"))
        #expect(PetSpecies.asksAboutNeutering("cat"))
        #expect(PetSpecies.asksAboutNeutering("fish") == false)
        #expect(PetSpecies.asksAboutNeutering("bird") == false)
        #expect(PetSpecies.asksAboutNeutering(nil) == false)
    }

    @Test("Без имени питомца форма не отправляется: сервер всё равно откажет")
    func blankNameNeverGoes() {
        #expect(PetDraft.problem(PetDraft(name: "  ")) == "Введите имя питомца")
        #expect(PetDraft.problem(PetDraft(name: "Рекс")) == nil)
    }

    @Test("Что пропадёт вместе с питомцем, читается числами")
    func deletionImpactIsSaidInWords() {
        let impact = PetDeletionImpact(events: 264, medications: 3, documents: 3, medicalRecords: 8)

        #expect(
            impact.summary
                == "264 записи в ленте, 3 лекарства, 3 документа, 8 записей медкарты"
        )
        // У питомца без записей пустой список читался бы как «ничего не
        // пропадёт», а это неправда: пропадёт сам питомец.
        #expect(PetDeletionImpact(events: 0, medications: 0, documents: 0, medicalRecords: 0).summary.isEmpty)
    }

    /// Настоящий ответ `/api/pets/<id>`, обрезанный до нужных полей.
    static func cardResponse() -> [String: Any] {
        [
            "pet": [
                "_id": "6ac0b44fc775325d197b84df",
                "birth_date": "2021-08-01",
                "breed": "Лабрадор",
                "created_at": "2026-10-03T07:52:47Z",
                "current_user_is_owner": true,
                "gender": "male",
                "health_notes": "Аллергия на курицу",
                "is_neutered": NSNull(),
                "name": "Рекс",
                "next_owner": "family",
                "photo_url": "http://localhost:3000/api/pets/6ac0b44fc775325d197b84df/photo?v=cef9&exp=1792353600&sig=3VM9",
                "share_invites": [],
                "shared_with": ["family"],
                "species": "dog"
            ]
        ]
    }
}
