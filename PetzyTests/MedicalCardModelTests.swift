import Foundation
@testable import Petzy
import Testing

/// Модель медкарты: что показано, что перечитывается после записи и куда
/// кладётся файл для врача. Всё это проверяется без экрана.
@Suite("Медкарта: модель")
@MainActor
struct MedicalCardModelTests {
    @Test("Карта читается одним запросом и попадает в модель")
    func loadReadsCard() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let model = try await makeModel()

        await model.load()

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/medical-card"])
        #expect(model.card?.pet.name == "Рекс")
        #expect(model.isLoading == false)
    }

    @Test("Значок вкладки считает просроченные записи")
    func badgeCountsOverdue() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let model = try await makeModel()

        await model.load()

        #expect(model.overdueCount == 2)
        #expect(model.hasOverdue)
    }

    @Test("Без просроченных значка нет")
    func noBadgeWithoutOverdue() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["card": [
            "pet": ["name": "Рекс"], "records": [:], "record_counts": [:],
            "overdue_records": [], "medications": [], "documents": [], "past_courses": [],
            "generated_at": "2026-10-18", "can_edit": true
        ]])
        let model = try await makeModel()

        await model.load()

        #expect(model.overdueCount == 0)
        #expect(model.hasOverdue == false)
    }

    @Test("Сохранённая запись перечитывает карту, а не верит в свой ответ")
    func saveReloadsCard() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "r9"])
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let model = try await makeModel()
        await model.load()

        let saved = await model.save(MedicalCardWriteTests.draft(.parasite, target: "fleas_ticks"))

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/pets/p1/medical-card",
            "/api/medical-records",
            "/api/pets/p1/medical-card"
        ])
    }

    @Test("Ошибка сохранения остаётся на экране и не стирает карту")
    func saveErrorKeepsCard() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(
            status: 422,
            json: ["success": false, "error": "Нужен вид записи", "code": "validation_error"]
        )
        let model = try await makeModel()
        await model.load()

        let saved = await model.save(MedicalCardWriteTests.draft(.parasite, target: "fleas_ticks"))

        #expect(saved == false)
        #expect(model.errorText == "Нужен вид записи")
        #expect(model.card?.pet.name == "Рекс")
    }

    @Test("Незаполненная форма не ходит на сервер")
    func invalidDraftNeverReachesServer() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let model = try await makeModel()
        await model.load()
        var draft = MedicalCardWriteTests.draft(.parasite, target: nil)

        let saved = await model.save(draft)
        draft.title = ""

        #expect(saved == false)
        #expect(model.errorText == "Выберите, от кого обработка")
        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/medical-card"])
    }

    @Test("Удаление уходит на сервер и перечитывает карту")
    func deleteReloadsCard() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, json: ["success": true])
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let model = try await makeModel()
        await model.load()
        let record = MedicalCardTests.record(status: "overdue", daysLeft: -11)

        await model.delete(record)

        #expect(StubURLProtocol.requestedPaths == [
            "/api/pets/p1/medical-card",
            "/api/medical-records/r1",
            "/api/pets/p1/medical-card"
        ])
        #expect(StubURLProtocol.requests[1].httpMethod == "DELETE")
    }

    @Test("Сервер отказал в удалении, запись осталась на экране")
    func failedDeleteKeepsRecord() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(
            status: 404,
            json: ["success": false, "error": "Запись не найдена", "code": "record_not_found"]
        )
        let model = try await makeModel()
        await model.load()
        let record = MedicalCardTests.record(status: "overdue", daysLeft: -11)

        await model.delete(record)

        #expect(model.errorText == "Запись не найдена")
        #expect(model.card?.pet.name == "Рекс")
    }

    @Test("PDF кладётся во временный файл и его видно в системном меню")
    func pdfIsPreparedForShare() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, data: Data("%PDF-1.7".utf8), headers: [
            "Content-Disposition": "attachment; filename*=UTF-8''медкарта_Рекс.pdf",
            "Content-Type": "application/pdf"
        ])
        let model = try await makeModel()
        await model.load()

        await model.downloadPDF()

        let url = try #require(model.pdfFile)
        #expect(url.lastPathComponent == "медкарта_Рекс.pdf")
        #expect(url.deletingLastPathComponent().lastPathComponent == "tmp")
        #expect(try String(contentsOf: url, encoding: .utf8) == "%PDF-1.7")
    }

    @Test("Без файла системного меню нечего открывать")
    func noPdfNoShare() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let model = try await makeModel()

        await model.load()

        #expect(model.pdfFile == nil)
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
}
