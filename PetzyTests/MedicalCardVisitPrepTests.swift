import Foundation
@testable import Petzy
import Testing

/// Заметка «К приёму» — то, что человек хочет сказать врачу на следующем
/// приёме. После визита она должна исчезнуть: к следующему приёму её пишут
/// заново, а иначе врач слышит то, что было в прошлый раз.
@MainActor
@Suite("Медкарта: заметка «К приёму»")
struct MedicalCardVisitPrepTests {
    @Test("После визита заметка «К приёму» очищается")
    func visitClearsVisitPrep() async throws {
        var card = LiveFixtures.medicalCard
        var inner = card["card"] as? [String: Any] ?? [:]
        inner["visit_prep"] = ["version": "v1", "complaint": "Кашель", "checks": ["appetite": "норма"]]
        card["card"] = inner
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: card)
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "r9"])
        StubURLProtocol.stub(status: 200, json: card)
        StubURLProtocol.stub(status: 200, json: ["visit_prep": nil])
        StubURLProtocol.stub(status: 200, json: card)
        let model = try await TestSupport.makeMedicalCardModel()
        await model.load()

        let saved = await model.save(MedicalCardWriteTests.draft(.visit))

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/pets/p1/medical-card",
            "/api/medical-records",
            "/api/pets/p1/medical-card",
            "/api/pets/p1/visit-prep",
            "/api/pets/p1/medical-card"
        ])
    }

    /// Без заметки очищать нечего: лишний запрос ни к чему.
    @Test("Без заметки очистку не просят")
    func visitWithoutPrepDoesNotClear() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "r9"])
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        let model = try await TestSupport.makeMedicalCardModel()
        await model.load()

        await model.save(MedicalCardWriteTests.draft(.visit))

        #expect(StubURLProtocol.requestedPaths == [
            "/api/pets/p1/medical-card",
            "/api/medical-records",
            "/api/pets/p1/medical-card"
        ])
    }

    /// Заметка «К приёму» — это то, что человек хотел сказать врачу: в форме
    /// визита жалоба появляется сама, переписывать её незачем.
    @Test("Новый визит начинается с жалобы из заметки «К приёму»")
    func newVisitTakesComplaintFromPrep() {
        let prep = VisitPrep(baseVersion: "v1", complaint: "Кашель", checks: [])

        let visit = MedicalRecordDraft.new(petID: "p1", kind: .visit, date: "2026-10-20", visitPrep: prep)
        let vaccine = MedicalRecordDraft.new(petID: "p1", kind: .vaccination, date: "2026-10-20", visitPrep: prep)

        #expect(visit.complaint == "Кашель")
        #expect(vaccine.complaint == nil)
    }
}
