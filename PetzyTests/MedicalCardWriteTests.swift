import Foundation
@testable import Petzy
import Testing

/// Запись медкарты и файл для врача. Проверяется тело запроса: сервер чистит
/// поля по своему виду записи сам, и если форма пришлёт чужое поле, ошибку
/// человек увидит только на сервере, а не в проверке.
@Suite("Медкарта: запись")
struct MedicalCardWriteTests {
    @Test("Новая запись уходит одним объектом с видом и датой")
    func createSendsFlatBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "r9"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicalCardAPI.create(client, draft: Self.draft(.parasite, target: "fleas_ticks"))

        #expect(StubURLProtocol.requestedPaths == ["/api/medical-records"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["pet_id"] as? String == "p1")
        #expect(body["kind"] as? String == "parasite")
        #expect(body["title"] as? String == "Бравекто")
        #expect(body["date"] as? String == "2026-07-12")
        #expect(body["target"] as? String == "fleas_ticks")
    }

    @Test("У прививки уходит защита, у обработки цель, а лишнего не уходит вовсе")
    func kindFieldsGoToTheirKind() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "r9"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicalCardAPI.create(client, draft: Self.draft(.vaccination, protects: "rabies"))
        var body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["protects"] as? String == "rabies")
        #expect(body["target"] == nil)

        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "r9"])
        try await MedicalCardAPI.create(client, draft: Self.draft(.visit, complaint: "Кашель"))
        body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["complaint"] as? String == "Кашель")
        #expect(body["protects"] == nil)
    }

    @Test("Правка шлёт запись целиком: сервер заменяет, а не дополняет")
    func updateSendsWholeRecord() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicalCardAPI.update(client, id: "r1", draft: Self.draft(.parasite, target: "worms"))

        #expect(StubURLProtocol.requestedPaths == ["/api/medical-records/r1"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["target"] as? String == "worms")
        #expect(body["kind"] as? String == "parasite")
    }

    @Test("Удаление записи уходит отдельным методом")
    func deleteCallsDelete() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicalCardAPI.delete(client, id: "r1")

        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
    }

    @Test("Записи раздела приходят по виду и разбираются")
    func recordsAreFilteredByKind() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["records": [
            [
                "_id": "r1", "kind": "parasite", "title": "Бравекто", "date": "2026-07-12",
                "next_due": "2026-10-07", "days_left": -11, "status": "overdue", "target": "fleas_ticks"
            ]
        ]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let records = try await MedicalCardAPI.records(client, petID: "p1", kind: .parasite)

        #expect(records.count == 1)
        #expect(records.first?.title == "Бравекто")
        #expect(records.first?.statusText == "Просрочено 11 дней")
        #expect(records.first?.isOverdue == true)
    }

    @Test("PDF приходит файлом с именем питомца, а не разобранным ответом")
    func pdfIsDownloadedWithName() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, data: Data("%PDF-1.7".utf8), headers: [
            "Content-Disposition": "attachment; filename*=UTF-8''медкарта_Рекс.pdf",
            "Content-Type": "application/pdf"
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let file = try await MedicalCardAPI.pdf(client, petID: "p1")

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/medical-card/pdf"])
        #expect(file.fileName == "медкарта_Рекс.pdf")
        #expect(String(data: file.data, encoding: .utf8) == "%PDF-1.7")
    }

    @Test("Обработка без цели не уходит на сервер: сервер всё равно её не примет")
    func parasiteWithoutTargetIsRejectedLocally() {
        StubURLProtocol.reset()
        let draft = Self.draft(.parasite, target: nil)

        let problem = MedicalRecordDraft.problem(draft)

        #expect(problem != nil)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("Прививка и приём без своих полей проходят проверку")
    func otherKindsNeedNothingExtra() {
        #expect(MedicalRecordDraft.problem(Self.draft(.vaccination, protects: nil)) == nil)
        #expect(MedicalRecordDraft.problem(Self.draft(.visit, complaint: nil)) == nil)
    }

    @Test("Пустое название не уходит на сервер")
    func emptyTitleIsRejected() {
        var draft = Self.draft(.procedure)
        draft.title = "   "

        #expect(MedicalRecordDraft.problem(draft) != nil)
    }

    static func draft(
        _ kind: MedicalKind,
        target: String? = nil,
        protects: String? = nil,
        complaint: String? = nil
    ) -> MedicalRecordDraft {
        MedicalRecordDraft(
            petID: "p1",
            kind: kind,
            date: "2026-07-12",
            title: "Бравекто",
            nextDue: "2026-10-07",
            clinic: "Ортовет",
            vet: "Каримов Д.",
            note: nil,
            batch: "A-12",
            target: target,
            protects: protects,
            complaint: complaint
        )
    }
}
