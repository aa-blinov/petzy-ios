import Foundation
@testable import Petzy
import Testing

/// Карточка питомца на главном экране: фото из ответа сервера, имя и строка
/// «возраст, порода, пол». Логика здесь, а проводка — в UI-тесте.
@Suite("Питомцы: карточка на главном")
struct PetSummaryTests {
    @Test("Возраст питомца говорится словами")
    func ageIsSaidInWords() {
        #expect(PetAge.text(birthDate: "2021-08-01", today: Self.day("2026-10-19")) == "5 лет")
        #expect(PetAge.text(birthDate: "2026-08-19", today: Self.day("2026-10-19")) == "2 месяца")
        #expect(PetAge.text(birthDate: "2026-09-19", today: Self.day("2026-10-19")) == "1 месяц")
        #expect(PetAge.text(birthDate: "2026-10-12", today: Self.day("2026-10-19")) == "1 неделя")
        #expect(PetAge.text(birthDate: "2026-10-16", today: Self.day("2026-10-19")) == "3 дня")
        // Даты рождения нет — возраста тоже нет.
        #expect(PetAge.text(birthDate: nil) == nil)
        #expect(PetAge.text(birthDate: "не дата") == nil)
        // Родившийся завтра питомец: возраст неизвестен, а не отрицательный.
        #expect(PetAge.text(birthDate: "2026-10-20", today: Self.day("2026-10-19")) == nil)
    }

    /// Строка под именем: возраст, порода и пол через запятую, как в вебе.
    /// Порода и пол в русском не имена собственные, и с заглавной они читались
    /// бы ошмёткой.
    @Test("Под именем: возраст, порода и пол")
    func metaLineIsComposed() {
        let pet = Pet(
            id: "p1",
            name: "Рекс",
            species: "dog",
            breed: "Лабрадор",
            birthDate: "2021-08-01",
            gender: "male",
            photoURL: nil,
            updatedAt: nil
        )
        let age = PetAge.text(birthDate: "2021-08-01")

        #expect(pet.metaLine == "\(age ?? ""), лабрадор, мальчик")
    }

    /// Про питомца ничего не известно: вместо пустой строки показываем вид.
    /// Пустая строка под именем выглядела бы как поломка экрана.
    @Test("Нет данных — показываем вид питомца")
    func speciesIsShownWhenNothingElseIsKnown() {
        let pet = Pet(
            id: "p1",
            name: "Щит",
            species: "dog",
            breed: nil,
            birthDate: nil,
            gender: nil,
            photoURL: nil,
            updatedAt: nil
        )

        #expect(pet.metaLine == "собака")
        #expect(pet.metaLine?.isEmpty == false)
    }

    /// Пол «не указан» в строку не попадает: «Мальчик» там не о чем.
    @Test("Неизвестный пол в строку не попадает")
    func unknownGenderIsNotShown() {
        let pet = Pet(
            id: "p1",
            name: "Щит",
            species: "cat",
            breed: "Британская",
            birthDate: nil,
            gender: "что-то своё",
            photoURL: nil,
            updatedAt: nil
        )

        #expect(pet.metaLine == "британская")
    }

    /// Фото приходит вместе со списком питомцев: отдельный запрос за карточкой
    /// не нужен, и адрес открывается без токена.
    @Test("Фото питомца читается из списка")
    func photoIsReadFromPetList() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["pets": [
            [
                "_id": "6ac0b44fc775325d197b84df",
                "name": "Рекс",
                "species": "dog",
                "breed": "Лабрадор",
                "birth_date": "2021-08-01",
                "gender": "male",
                "photo_url": "http://localhost:3000/api/pets/6ac0b44fc775325d197b84df/photo?v=1&sig=abc"
            ]
        ]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let response = try await client.get("/api/pets", as: PetsResponse.self)

        #expect(StubURLProtocol.requestedPaths == ["/api/pets"])
        #expect(response.pets.first?.photoURL?.absoluteString.contains("sig=") == true)
    }

    /// Питомец без фото: адреса нет, а не пустая строка.
    @Test("У питомца без фото адреса нет")
    func photoMayBeMissing() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["pets": [["_id": "p1", "name": "Щит"]]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let response = try await client.get("/api/pets", as: PetsResponse.self)

        #expect(response.pets.first?.photoURL == nil)
    }

    /// Значок вида: у кота и собаки свои, у кого знака нет — лапка.
    @Test("У вида питомца свой значок")
    func speciesHasItsOwnIcon() {
        #expect(PetSpecies.icon(for: "cat") == "cat.fill")
        #expect(PetSpecies.icon(for: "dog") == "dog.fill")
        #expect(PetSpecies.icon(for: "bird") == "bird.fill")
        #expect(PetSpecies.icon(for: "rabbit") == "hare.fill")
        #expect(PetSpecies.icon(for: "hamster") == "pawprint.fill")
        #expect(PetSpecies.icon(for: nil) == "pawprint.fill")
    }

    /// Дата из строки «ГГГГ-ММ-ДД» в полночь своего дня.
    private static func day(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components) ?? .now
    }
}
