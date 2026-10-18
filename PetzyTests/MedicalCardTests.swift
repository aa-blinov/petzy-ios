import Foundation
@testable import Petzy
import Testing

/// Медкарта. Сервер отдаёт её одним большим объектом и сам считает статусы,
/// поэтому проверяется не столько разбор, сколько то, как это читается
/// по-русски: «просрочено 11 дней» человек понимает, `status: overdue` — нет.
@Suite("Медкарта")
struct MedicalCardTests {
    @Test("Карта разбирается из ответа сервера вместе с плитками и сроками")
    func cardIsMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let card = try await MedicalCardAPI.card(client, petID: "p1", zone: "Asia/Almaty")

        #expect(card.pet.name == "Рекс")
        #expect(card.pet.breed == "Лабрадор")
        #expect(card.pet.species == "Собака")
        #expect(card.pet.ageText == "5 лет")
        #expect(card.count(for: .vaccination) == 3)
        #expect(card.count(for: .parasite) == 2)
        #expect(card.overdueCount == 2)
        #expect(card.weight?.value == 29.3)
        #expect(card.generatedAt == "2026-10-18")
    }

    @Test("Просроченная запись читается словами, а не кодом статуса")
    func overdueReadsInWords() {
        let record = Self.record(status: "overdue", daysLeft: -11)
        #expect(record.statusText == "Просрочено 11 дней")
    }

    @Test("Скоро и «осталось» тоже читаются по-русски")
    func soonAndLeft() {
        #expect(Self.record(status: "soon", daysLeft: 5).statusText == "Осталось 5 дней")
        #expect(Self.record(status: "ok", daysLeft: 30).statusText == "Осталось 30 дней")
        // У записи без даты повтора срока нет, и выдумывать его нельзя.
        #expect(Self.record(status: "none", daysLeft: nil).statusText == nil)
    }

    @Test("Виды записей перечислены в порядке экрана, а не как пришли")
    func kindsAreInScreenOrder() {
        #expect(MedicalKind.allCases.map(\.rawValue) == ["vaccination", "parasite", "visit", "procedure"])
        #expect(MedicalKind.vaccination.title == "Прививки")
        #expect(MedicalKind.parasite.title == "Обработка от паразитов")
        #expect(MedicalKind.visit.title == "Приёмы врача")
        #expect(MedicalKind.procedure.title == "Операции и процедуры")
    }

    @Test("Плитка показывает, что пора, а «просрочено» важнее «осталось»")
    func tilePicksTheUrgentStatus() {
        #expect(Self.tile(count: 3, overdue: 1).statusText == "1 просрочена")
        #expect(Self.tile(count: 3, overdue: 0).statusText == nil)
    }

    @Test("Вес читается с датой и изменением")
    func weightText() {
        let card = MedicalCardTests.cardFixture()
        #expect(card.weightText == "29,3 кг, последний 04.10.2026")
    }

    @Test("«К приёму» читается словами: что изменилось и что как обычно")
    func visitPrepReadsInWords() {
        let checks = ["cough": "changed", "appetite": "changed", "thirst": "normal"]

        // Ключи `cough` и `normal` врачу ничего не говорят.
        #expect(VisitChecks.changed(checks) == ["аппетит", "кашель"])
        #expect(VisitChecks.normal(checks) == ["жажда"])
        #expect(VisitChecks.title("activity") == "Активность")
    }

    @Test("Пустой ответ даёт пустую карту, а не ошибку")
    func emptyCardIsNotAnError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["card": [
            "pet": ["name": "Рекс"], "records": [:], "record_counts": [:],
            "overdue_records": [], "weight": NSNull(), "medications": [], "documents": [],
            "past_courses": [], "generated_at": "2026-10-18", "can_edit": true
        ]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let card = try await MedicalCardAPI.card(client, petID: "p1", zone: "Asia/Almaty")

        #expect(card.count(for: .vaccination) == 0)
        #expect(card.overdueCount == 0)
        #expect(card.pet.name == "Рекс")
        #expect(card.tiles.allSatisfy { $0.count == 0 })
    }

    @Test("Профиль разбирается так же, как приходит: хроническое это объект")
    func profileIsMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let card = try await MedicalCardAPI.card(client, petID: "p1", zone: "Asia/Almaty")
        let profile = try #require(card.profile)

        // Условия приходят объектами с названием, заметкой и годом. Разбор
        // строкой молча ломал бы всю медкарту на живых данных.
        #expect(profile.conditions.first?.name == "Дисплазия тазобедренных суставов")
        #expect(profile.conditions.first?.sinceYear == 2023)
        #expect(profile.allergies.first == Allergy(substance: "Курица", reaction: "зуд, покраснение ушей"))
        #expect(profile.clinicName == "Ортовет")
        #expect(profile.vetName == "Каримов Д.")
        #expect(profile.diet == "Сухой корм для крупных пород, два раза в день")
    }

    @Test("Хроническое читается одной строкой: название, год, чем обостряется")
    func conditionText() {
        let condition = MedicalCondition(
            name: "Хронический гастрит",
            note: "обострения после нагрузки",
            sinceYear: 2023
        )
        #expect(condition.text == "Хронический гастрит, с 2023, обострения после нагрузки")
    }

    @Test("Карта читается одним маршрутом, а не пятью запросами")
    func cardIsOneRequest() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await MedicalCardAPI.card(client, petID: "p1", zone: "Asia/Almaty")

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/medical-card"])
    }

    // MARK: - Заготовки

    static func record(status: String, daysLeft: Int?) -> MedicalRecord {
        MedicalRecord(
            id: "r1",
            kind: .parasite,
            title: "Бравекто",
            date: "2026-07-12",
            nextDue: "2026-10-07",
            status: MedicalStatus(rawValue: status) ?? .none,
            daysLeft: daysLeft,
            clinic: nil,
            vet: nil,
            note: nil
        )
    }

    static func tile(count: Int, overdue: Int) -> CardTile {
        CardTile(kind: .vaccination, count: count, overdue: overdue)
    }

    static func cardFixture() -> MedicalCard {
        MedicalCard(
            pet: CardPet(name: "Рекс", breed: "Лабрадор", species: "dog", ageText: "", neuteredText: ""),
            records: [:],
            counts: [:],
            overdueCount: 0,
            weight: WeightPoint(date: "2026-10-04", value: 29.3),
            medications: [],
            documents: [],
            pastCourses: [],
            profile: nil,
            visitPrep: nil,
            generatedAt: "2026-10-18",
            canEdit: true
        )
    }
}
