import Foundation
@testable import Petzy
import Testing

/// Отмеченный приём можно поправить: он не форма, а факт, и ошибка в нём —
/// обычное дело («отметил сейчас», а дали утром). Время переносится, приём
/// удаляется вместе с возвратом остатка: иначе ошибочная отметка списывала бы
/// дозу навсегда.
@MainActor
@Suite("Приёмы лекарств: правка")
struct IntakeEditTests {
    @Test("Время приёма переносится своим маршрутом")
    func moveUsesIntakeRoute() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Приём обновлён"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicationsAPI.moveIntake(
            client,
            intakeID: "i1",
            date: "2026-10-21",
            time: "08:00",
            zone: "Asia/Almaty"
        )

        #expect(StubURLProtocol.requestedPaths == ["/api/medications/intakes/i1"])
        #expect(StubURLProtocol.requests.last?.httpMethod == "PUT")
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["date"] as? String == "2026-10-21")
        #expect(body["time"] as? String == "08:00")
        #expect(body["tz"] as? String == "Asia/Almaty")
    }

    @Test("Приём удаляется своим маршрутом")
    func deleteUsesIntakeRoute() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Приём удалён"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicationsAPI.deleteIntake(client, intakeID: "i1")

        #expect(StubURLProtocol.requestedPaths == ["/api/medications/intakes/i1"])
        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
    }

    @Test("После отмены раздел перечитывает курсы и приёмы")
    func editReloads() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Приём удалён"])
        StubURLProtocol.stub(status: 200, json: ["medications": []])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let model = try await TestSupport.makeMedicationsModel()

        await model.deleteIntake(id: "i1")

        #expect(StubURLProtocol.requestedPaths.first == "/api/medications/intakes/i1")
        #expect(StubURLProtocol.requestedPaths.contains("/api/medications"))
        #expect(model.notice == "Приём отменён")
    }
}
