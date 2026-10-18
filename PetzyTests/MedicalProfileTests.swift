import Foundation
@testable import Petzy
import Testing

/// Профиль для врача и «К приёму». Обе формы редактируют то, что читает
/// другой человек, поэтому сервер проверяет версию: сохранение из устаревшей
/// копии отвечает 409, и молча переписать чужое правку было бы хуже, чем
/// спросить.
@Suite("Медкарта: профиль и приём")
struct MedicalProfileTests {
    @Test("Профиль уходит с версией, с которой его открыли")
    func profileSendsBaseVersion() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "profile": ["version": "v2"]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicalCardAPI.saveProfile(client, petID: "p1", profile: Self.profile)

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/medical-profile"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["base_version"] as? String == "v1")
        #expect(body["diet"] as? String == "Сухой корм")
        #expect(body["blood_type"] as? String == "DEA 1.1+")
    }

    @Test("«Аллергий нет» уходит отдельным флагом и пустым списком")
    func allergiesNoneKnownIsExplicit() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var profile = Self.profile
        profile.allergiesNoneKnown = true

        try await MedicalCardAPI.saveProfile(client, petID: "p1", profile: profile)

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["allergies_none_known"] as? Bool == true)
        #expect(body["allergies"] != nil)
        // Отметка и список вместе сервер отклоняет 422. Список, который человек
        // набрал, при этом не теряется: он остаётся в форме и уедет, если
        // человек передумает.
        #expect((body["allergies"] as? [Any] ?? []).isEmpty)
    }

    @Test("Устаревшая копия профиля отвечает 409 с текстом сервера")
    func profileConflictIsReported() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 409, json: [
            "success": false,
            "error": "Профиль изменили, пока форма была открыта",
            "code": "version_conflict",
            "profile": ["version": "v3"]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        do {
            try await MedicalCardAPI.saveProfile(client, petID: "p1", profile: Self.profile)
            Issue.record("сохранение устаревшей копии должно было упасть")
        } catch {
            #expect((error as? APIError)?.errorDescription == "Профиль изменили, пока форма была открыта")
        }
    }

    @Test("Версия профиля и заметки доезжают из карты, иначе правка затрётся молча")
    func versionsComeFromCard() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let card = try await MedicalCardAPI.card(client, petID: "p1", zone: "Asia/Almaty")

        // Без версии форма отправила бы base_version = nil, сервер проверку
        // пропустил бы, и правка второго человека затиралась бы без слова.
        #expect(card.profile?.baseVersion == "554c0b266eda4363a8bbf560e3b1236e")
    }

    @Test("Заметка «К приёму» несёт свою версию, а не версию профиля")
    func visitPrepVersionComesToo() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["card": [
            "pet": ["name": "Рекс"], "records": [:], "record_counts": [:],
            "overdue_records": [], "medications": [], "documents": [], "past_courses": [],
            "profile": ["version": "v-profile"],
            "visit_prep": ["complaint": "Кашель", "checks": ["cough": "changed"], "version": "v-prep"],
            "generated_at": "2026-10-18", "can_edit": true
        ]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let card = try await MedicalCardAPI.card(client, petID: "p1", zone: "Asia/Almaty")

        #expect(card.visitPrep?.baseVersion == "v-prep")
        #expect(card.profile?.baseVersion == "v-profile")
    }

    @Test("«К приёму» уходит с жалобой и всеми отметками")
    func visitPrepSendsChecks() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicalCardAPI.saveVisitPrep(
            client,
            petID: "p1",
            baseVersion: "v1",
            complaint: "Кашель третьий день",
            checks: ["appetite": "Сниженный", "thirst": "Норма"]
        )

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/visit-prep"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["complaint"] as? String == "Кашель третьий день")
        #expect(body["base_version"] as? String == "v1")
        let checks = try #require(body["checks"] as? [String: String])
        #expect(checks["appetite"] == "Сниженный")
        #expect(checks["thirst"] == "Норма")
    }

    @Test("Ссылка для врача приходит с токеном один раз и превращается в адрес")
    func shareReturnsLink() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "share": ["id": "s1", "username": "demo", "expires_at": "2026-10-25T07:52:00Z"],
            "token": "abc123",
            "path": "/share/medical/abc123"
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let share = try await MedicalCardAPI.createShare(client, petID: "p1", days: 7)

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/medical-card/shares"])
        #expect(TestSupport.body(of: StubURLProtocol.requests.last)["days"] as? Int == 7)
        #expect(share.token == "abc123")
        // Ссылка открывается без входа, поэтому это адрес, а не путь внутри
        // приложения: поделиться ею можно прямо из системного меню.
        #expect(share.url?.absoluteString == "http://localhost:5002/share/medical/abc123")
    }

    @Test("Создание ссылки отдаёт дату, до которой она живёт")
    func shareCarriesExpiry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "share": ["id": "s1", "username": "demo", "expires_at": "2026-10-25T07:52:00Z"],
            "token": "abc123",
            "path": "/share/medical/abc123"
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let share = try await MedicalCardAPI.createShare(client, petID: "p1", days: 30)

        #expect(share.expiresAt == "2026-10-25T07:52:00Z")
    }

    @Test("Каталог прививок приходит группами и препаратами")
    func vaccineCatalogIsMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "groups": [
                [
                    "key": "rabies", "label": "От бешенства",
                    "detail": "Раз в год", "species": ["dog"]
                ]
            ],
            "products": [["name": "Нобивак", "species": ["dog"], "protects": "rabies"]]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let catalog = try await MedicalCardAPI.vaccineCatalog(client)

        #expect(StubURLProtocol.requestedPaths == ["/api/vaccines/catalog"])
        #expect(catalog.first?.key == "rabies")
        #expect(catalog.first?.label == "От бешенства")
        #expect(catalog.first?.detail == "Раз в год")
    }

    @Test("Пустой каталог не ошибка: прививки заводят и без справочника")
    func emptyCatalogIsNotAnError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["groups": [], "products": []])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let catalog = try await MedicalCardAPI.vaccineCatalog(client)

        #expect(catalog.isEmpty)
    }

    // MARK: - Заготовки

    static var profile: MedicalProfileDraft {
        MedicalProfileDraft(
            baseVersion: "v1",
            allergies: [Allergy(substance: "Курица", reaction: "зуд")],
            allergiesNoneKnown: false,
            bloodType: "DEA 1.1+",
            chipNumber: "643094100200311",
            clinicName: "Ортовет",
            clinicPhone: "+7 727 555 03 04",
            vetName: "Каримов Д.",
            conditions: [MedicalCondition(name: "Дисплазия", note: nil, sinceYear: 2023)],
            diet: "Сухой корм",
            living: "Квартира",
            reproduction: nil
        )
    }
}
