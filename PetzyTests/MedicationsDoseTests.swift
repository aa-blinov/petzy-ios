import Foundation
@testable import Petzy
import Testing

/// Отметка приёма: время, которое выбрал человек, должно уйти на сервер.
/// Раньше лист спрашивал «Когда» и «Во сколько», а отметка уходила «сейчас».
@MainActor
@Suite("Лекарства: время отметки")
struct MedicationsDoseTests {
    /// Человек сам выбирает, когда дал лекарство. Если это время проигнорировать,
    /// приём запишется «сейчас», и отметка в ленте будет врать.
    @Test("Отметка приёма уходит с тем временем, которое выбрал человек")
    func markDoseUsesChosenMoment() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "i1", "ran_out": false])
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let model = try await TestSupport.makeMedicationsModel()
        await model.load()

        await model.markDose(
            MedicationsTests.med(days: [], times: []),
            dose: 1,
            moment: Moment(day: "2026-10-20", time: "21:30")
        )

        let log = StubURLProtocol.requests.first { $0.url?.path == "/api/medications/m1/log" }
        let body = TestSupport.body(of: log)
        #expect(body["date"] as? String == "2026-10-20")
        #expect(body["time"] as? String == "21:30")
    }

    /// Форма спрашивает день и время двумя полями, а отметка ждёт один момент.
    @Test("День и время из формы собираются в один момент")
    func momentTakesDayAndTime() throws {
        let calendar = Calendar.current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        let time = try #require(calendar.date(from: DateComponents(hour: 21, minute: 30)))

        #expect(Moment(day: day, time: time) == Moment(day: "2026-10-20", time: "21:30"))
    }
}
