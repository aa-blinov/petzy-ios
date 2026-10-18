import Foundation
@testable import Petzy
import Testing

/// Модель раздела «Лекарства»: что показывается, в каком порядке и что
/// происходит после действия. Проверяется без экрана, потому что экран только
/// рисует состояние, а решение принимает здесь.
@Suite("Лекарства: модель")
@MainActor
struct MedicationsModelTests {
    @Test("Порядок: сначала ближайший приём, потом сделанные, потом будущие, архив в конце")
    func orderPutsUrgentFirst() {
        let urgent = MedicationsTests.med(id: "urgent", days: [0], times: ["08:00"],
                                          scheduledToday: true, openSlots: ["08:00"])
        let later = MedicationsTests.med(id: "later", days: [0], times: ["21:00"],
                                         scheduledToday: true, openSlots: ["21:00"])
        let doneToday = MedicationsTests.med(id: "done", days: [0], times: ["09:00"],
                                             scheduledToday: true, openSlots: [])
        let ended = MedicationsTests.med(id: "ended", days: [], times: [], status: .ended)
        let planned = MedicationsTests.med(id: "planned", days: [], times: [],
                                           status: .planned, startedOn: "2026-12-01")

        let ordered = [ended, planned, doneToday, later, urgent].sorted(by: Medication.byUrgency)

        #expect(ordered.map(\.id) == ["urgent", "later", "done", "planned", "ended"])
    }

    @Test("Два курса с приёмом в разное время идут по времени приёма")
    func orderBySlotTime() {
        let early = MedicationsTests.med(id: "early", days: [0], times: ["07:00"],
                                         scheduledToday: true, openSlots: ["07:00"])
        let late = MedicationsTests.med(id: "late", days: [0], times: ["09:00"],
                                        scheduledToday: true, openSlots: ["09:00"])

        let ordered = [late, early].sorted(by: Medication.byUrgency)

        #expect(ordered.map(\.id) == ["early", "late"])
    }

    @Test("Загрузка берёт список и ближайшие приёмы одним заходом")
    func loadAsksListAndUpcoming() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let model = try await makeModel()

        await model.load()

        #expect(StubURLProtocol.requestedPaths == ["/api/medications", "/api/medications/upcoming"])
        #expect(model.medications.count == 1)
        #expect(model.isLoading == false)
    }

    @Test("Просроченный приём поднимает точку на вкладке")
    func overdueShowsBadge() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": []])
        StubURLProtocol.stub(status: 200, json: ["doses": [
            [
                "medication_id": "m1", "name": "Дронтал Плюс", "type": "Таблетка",
                "time": "08:00", "date": "2026-10-18", "is_overdue": true,
                "inventory_warning": false, "carried_over": false
            ]
        ]])
        let model = try await makeModel()

        await model.load()

        #expect(model.hasOverdueDose)
    }

    @Test("Значок на вкладке считает просроченные приёмы, а не просто горит")
    func badgeCountsOverdue() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": []])
        StubURLProtocol.stub(status: 200, json: ["doses": [
            [
                "medication_id": "m1", "name": "Дронтал Плюс", "type": "Таблетка",
                "time": "08:00", "date": "2026-10-18", "is_overdue": true,
                "inventory_warning": false, "carried_over": false
            ],
            [
                "medication_id": "m2", "name": "Мелоксидил", "type": "Суспензия",
                "time": "21:00", "date": "2026-10-18", "is_overdue": true,
                "inventory_warning": false, "carried_over": false
            ]
        ]])
        let model = try await makeModel()

        await model.load()

        #expect(model.overdueCount == 2)
        #expect(model.overdueDose?.name == "Дронтал Плюс")
    }

    @Test("Без просроченных приёмов точки нет")
    func noBadgeWithoutOverdue() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": []])
        StubURLProtocol.stub(status: 200, json: ["doses": [
            [
                "medication_id": "m1", "name": "Дронтал Плюс", "type": "Таблетка",
                "time": "21:00", "date": "2026-10-18", "is_overdue": false,
                "inventory_warning": false, "carried_over": false
            ]
        ]])
        let model = try await makeModel()

        await model.load()

        #expect(model.hasOverdueDose == false)
    }

    @Test("Отметка приёма перечитывает список и просрочку, а не верит в ответ")
    func markDoseReloadsState() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        // отметка, затем повторные список и просрочка
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "i1", "ran_out": false])
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let model = try await makeModel()
        await model.load()

        await model.markDose(MedicationsTests.med(days: [], times: []), dose: 1)

        #expect(StubURLProtocol.requestedPaths == [
            "/api/medications",
            "/api/medications/upcoming",
            "/api/medications/m1/log",
            "/api/medications",
            "/api/medications/upcoming"
        ])
    }

    @Test("Кончившийся остаток говорится человеку, а не прячется")
    func ranOutIsReported() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "i1", "ran_out": true])
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let model = try await makeModel()
        await model.load()

        await model.markDose(MedicationsTests.med(days: [], times: []), dose: 1)

        #expect(model.notice == "Остаток кончился, пополните его")
    }

    @Test("Ошибка отметки остаётся на экране и не стирает список")
    func errorIsKeptAndListStays() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        StubURLProtocol.stub(
            status: 422,
            json: ["success": false, "error": "Дата не дальше 8 дней вперёд", "code": "validation_error"]
        )
        let model = try await makeModel()
        await model.load()

        await model.markDose(MedicationsTests.med(days: [], times: []), dose: 1)

        #expect(model.errorText == "Дата не дальше 8 дней вперёд")
        #expect(model.medications.count == 1)
    }

    @Test("Завершённые курсы спрятаны, пока их не попросили")
    func endedCoursesHiddenByDefault() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [
            MedicationsTests.drontalJSON,
            MedicationsTests.drontalJSON
                .merging(["_id": "m2", "course_status": "ended", "is_active": false]) { _, new in new }
        ]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let model = try await makeModel()

        await model.load()

        #expect(model.visibleMedications.count == 1)
        #expect(model.endedCount == 1)

        model.showsEnded = true
        #expect(model.visibleMedications.count == 2)
    }

    @Test("Поиск идёт по названию курса")
    func searchFiltersByName() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [
            MedicationsTests.drontalJSON,
            MedicationsTests.drontalJSON.merging(["_id": "m2", "name": "Мелоксидил"]) { _, new in new }
        ]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let model = try await makeModel()
        await model.load()

        model.search = "мелокс"

        #expect(model.visibleMedications.map(\.name) == ["Мелоксидил"])
    }

    private func makeModel() async throws -> MedicationsModel {
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let tokens = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: tokens)
        await auth.restore()
        return MedicationsModel(client: APIClient(baseURL: baseURL, urlSession: session, auth: auth), petID: "p1")
    }
}
