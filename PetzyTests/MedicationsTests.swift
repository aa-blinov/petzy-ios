import Foundation
@testable import Petzy
import Testing

/// Лекарства. Здесь две разные вещи: разбор ответа сервера в доменные значения
/// и правила показа, которые считаются на них. Второе проверяется без сети и
/// ловит ошибку раньше, чем человек увидит её на карточке.
@Suite("Лекарства")
struct MedicationsTests {
    // MARK: - Разбор ответа

    @Test("Список лекарств разбирается из ответа сервера")
    func listIsMappedFromServer() async throws {
        StubURLProtocol.reset()
        let session = StubURLProtocol.makeSession()
        StubURLProtocol.stub(status: 200, json: ["medications": [Self.drontalJSON]])
        let client = await Self.client(session: session)

        let meds = try await MedicationsAPI.list(client, petID: "p1", zone: "Asia/Almaty")

        #expect(meds.count == 1)
        let med = try #require(meds.first)
        #expect(med.id == "m1")
        #expect(med.name == "Дронтал Плюс")
        #expect(med.kind == "Таблетка")
        #expect(med.schedule.days == [0, 1, 2, 3, 4, 5, 6])
        #expect(med.schedule.times == ["09:00"])
        #expect(med.asNeeded == false)
        #expect(med.courseStatus == .active)
        #expect(med.openSlotsToday == ["09:00"])
        #expect(med.stock?.current == 0)
        #expect(med.stock?.total == 10)
        #expect(med.stock?.isLow == true)
        #expect(med.strength == "150 мг")
    }

    @Test("Пустой ответ даёт пустой список, а не ошибку")
    func emptyListIsNotAnError() async throws {
        StubURLProtocol.reset()
        let session = StubURLProtocol.makeSession()
        StubURLProtocol.stub(status: 200, json: ["medications": []])
        let client = await Self.client(session: session)

        let meds = try await MedicationsAPI.list(client, petID: "p1", zone: "Asia/Almaty")

        #expect(meds.isEmpty)
    }

    @Test("Ближайшие приёмы разбираются вместе с просрочкой")
    func upcomingIsMapped() async throws {
        StubURLProtocol.reset()
        let session = StubURLProtocol.makeSession()
        StubURLProtocol.stub(status: 200, json: ["doses": [
            [
                "medication_id": "m1", "name": "Дронтал Плюс", "type": "Таблетка",
                "time": "08:00", "date": "2026-10-18", "is_overdue": true,
                "inventory_warning": true, "carried_over": true
            ],
            [
                "medication_id": "m2", "name": "Мелоксидил", "type": "Суспензия",
                "time": "21:00", "date": "2026-10-18", "is_overdue": false,
                "inventory_warning": false, "carried_over": false
            ]
        ]])
        let client = await Self.client(session: session)

        let doses = try await MedicationsAPI.upcoming(client, petID: "p1", zone: "Asia/Almaty")

        #expect(doses.count == 2)
        #expect(doses.first?.isOverdue == true)
        #expect(doses.first?.carriedOver == true)
        #expect(doses.first?.name == "Дронтал Плюс")
        #expect(doses.last?.isOverdue == false)
    }

    @Test("Просроченный приём виден по одному маршруту, а не обходом всех лекарств")
    func overdueDosesAreAskedOnce() async throws {
        StubURLProtocol.reset()
        let session = StubURLProtocol.makeSession()
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        let client = await Self.client(session: session)

        _ = try await MedicationsAPI.upcoming(client, petID: "p1", zone: "Asia/Almaty")

        #expect(StubURLProtocol.requestedPaths == ["/api/medications/upcoming"])
    }

    // MARK: - Правила показа

    @Test("Расписание читается по-человечески")
    func scheduleIsReadInWords() {
        #expect(Self.med(days: [0, 1, 2, 3, 4, 5, 6], times: ["09:00"]).scheduleText == "Ежедневно в 09:00")
        #expect(Self.med(days: [1, 3, 5], times: ["10:00", "22:00"]).scheduleText == "В выбранные дни в 10:00, 22:00")
        #expect(Self.med(days: [], times: []).scheduleText == "По необходимости")
    }

    @Test("Курс без признака, но с пустым расписанием, читается как по необходимости")
    func legacyCourseWithoutFlagIsAsNeeded() async throws {
        // Старые курсы хранились без признака, а режим записывался пустым
        // расписанием. Если это не учесть, такой курс показался бы вовсе без
        // расписания и без единой кнопки приёма.
        StubURLProtocol.reset()
        let session = StubURLProtocol.makeSession()
        StubURLProtocol.stub(status: 200, json: ["medications": [
            Self.drontalJSON.merging(["as_needed": NSNull(), "schedule": ["days": [], "times": []]]) { _, new in new }
        ]])
        let client = await Self.client(session: session)

        let meds = try await MedicationsAPI.list(client, petID: "p1", zone: "Asia/Almaty")

        #expect(meds.first?.asNeeded == true)
        #expect(meds.first?.scheduleText == "По необходимости")
    }

    @Test("Все приёмы дня закрыты, и на сегодня всё")
    func doneToday() {
        let closed = Self.med(days: [0, 1, 2, 3, 4, 5, 6], times: ["09:00", "21:00"],
                              scheduledToday: true, openSlots: [])
        #expect(closed.isDoneToday)

        let open = Self.med(days: [0, 1, 2, 3, 4, 5, 6], times: ["09:00", "21:00"],
                            scheduledToday: true, openSlots: ["21:00"])
        #expect(open.isDoneToday == false)
    }

    @Test("Курс по необходимости не считается сделанным за день")
    func asNeededIsNeverDoneToday() {
        // У такого курса нет расписания, к которому можно отнести приём:
        // «на сегодня всё» здесь было бы враньём, а не утешением.
        let med = Self.med(days: [], times: [], asNeeded: true, scheduledToday: false, openSlots: [])
        #expect(med.isDoneToday == false)
    }

    @Test("Прогресс дня говорит, сколько отмечено, что просрочено и что дальше")
    func todayProgress() {
        let both = Self.med(days: [0, 1, 2, 3, 4, 5, 6], times: ["08:00", "21:00"],
                            scheduledToday: true, openSlots: ["08:00", "21:00"])
        #expect(both.todayProgress(at: "10:00") == "Сегодня 0 из 2, не отмечено в 08:00, дальше в 21:00")

        let one = Self.med(days: [0, 1, 2, 3, 4, 5, 6], times: ["08:00", "21:00"],
                           scheduledToday: true, openSlots: ["21:00"])
        #expect(one.todayProgress(at: "22:00") == "Сегодня 1 из 2, не отмечено в 21:00")
    }

    @Test("Метка курса: архив и «Начнётся»")
    func courseTag() {
        let ended = Self.med(days: [], times: [], status: .ended)
        #expect(ended.courseTag == "Архив")

        let planned = Self.med(days: [], times: [], status: .planned, startedOn: "2026-12-01")
        #expect(planned.courseTag == "Начнётся 01.12.2026")

        let active = Self.med(days: [], times: [])
        #expect(active.courseTag == nil)
    }

    @Test("Период курса читается по датам, которые у курса есть")
    func coursePeriod() {
        let both = Self.med(days: [], times: [], startedOn: "2026-05-12", endedOn: "2026-05-26")
        #expect(both.coursePeriod == "С 12.05.2026 по 26.05.2026 включительно")

        let until = Self.med(days: [], times: [], endedOn: "2026-05-26")
        #expect(until.coursePeriod == "До 26.05.2026 включительно")

        let since = Self.med(days: [], times: [], startedOn: "2026-05-12")
        #expect(since.coursePeriod == "С 12.05.2026")

        // Курс, который ещё не начался, начальной датой не подписывается:
        // «С 12.05.2026» рядом с меткой «Начнётся 12.05.2026» повторяет её.
        let planned = Self.med(days: [], times: [], status: .planned, startedOn: "2026-05-12")
        #expect(planned.coursePeriod == nil)
    }

    @Test("Остаток: сколько и на сколько дней хватит")
    func stockText() {
        let empty = Self.med(days: [], times: [],
                             stock: Stock(current: 0, total: 10, daysLeft: 0, isLow: true, warningDays: 3))
        #expect(empty.stockText == "0 из 10")
        #expect(empty.stockSubtext == "хватит на 0 дней, запас заканчивается")

        let enough = Self.med(days: [], times: [],
                              stock: Stock(current: 8, total: 10, daysLeft: 6, isLow: false, warningDays: 3))
        #expect(enough.stockText == "8 из 10")
        #expect(enough.stockSubtext == "хватит на 6 дней")
    }

    @Test("Доза читается вместе с единицей измерения")
    func doseText() {
        #expect(Self.med(days: [], times: [], dose: 2.5, unit: "мл").doseText == "2,5 мл")
        #expect(Self.med(days: [], times: []).doseText == "1 шт.")
    }

    @Test("Последний приём читается по-русски, а не сырым ISO")
    func lastTakenIsHuman() {
        // Тот самый случай, когда в заголовок уехало «06T08:43:00+05:00»:
        // в разметку ушло не то поле.
        let med = Self.med(days: [], times: [], lastTakenAt: "2026-10-06T08:43:00+05:00")
        #expect(med.lastTakenText == "06.10.2026 в 08:43")
    }

    @Test("Курса без последнего приёма подпись не нужна")
    func noLastTakenNoText() {
        #expect(Self.med(days: [], times: []).lastTakenText == nil)
    }

    // MARK: - Заготовки

    /// Клиент с заглушкой в сети. `restore()` обязателен: без него у сессии
    /// нет access-токена, и запрос не уходит вовсе, а тест падает на
    /// «не подписан» вместо проверки разбора ответа.
    static func client(session: URLSession) async -> APIClient {
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        // swiftlint:disable:next force_unwrapping
        let tokens = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: tokens)
        await auth.restore()
        return APIClient(baseURL: baseURL, urlSession: session, auth: auth)
    }

    /// Ответ сервера для одного лекарства, снят с живого стенда.
    static var drontalJSON: [String: Any] {
        [
            "_id": "m1",
            "pet_id": "p1",
            "name": "Дронтал Плюс",
            "type": "Таблетка",
            "form_factor": "tablet",
            "strength": "150 мг",
            "dose_unit": "таб",
            "default_dose": 1.0,
            "schedule": ["days": [0, 1, 2, 3, 4, 5, 6], "times": ["09:00"]],
            "as_needed": false,
            "inventory_enabled": true,
            "inventory_current": 0.0,
            "inventory_total": 10.0,
            "inventory_days_left": 0.0,
            "inventory_low": true,
            "inventory_warning_days": 3,
            "is_active": true,
            "course_status": "active",
            "updated_at": "2026-10-19T13:03:38Z",
            "started_on": "2026-10-01",
            "ended_on": NSNull(),
            "purpose": "От глистов",
            "prescribed_by": "Вет Д.",
            "comment": NSNull(),
            "intakes_today": 0,
            "scheduled_today": true,
            "open_slots_today": ["09:00"],
            "last_taken_at": "2026-10-06T08:43:00+05:00",
            "last_taken_by": "demo",
            "last_taken_tz": "Asia/Almaty",
            "username": "demo",
            "dosage": NSNull(),
            "unit": NSNull()
        ]
    }

    static func med(
        id: String = "m1",
        days: [Int],
        times: [String],
        asNeeded: Bool = false,
        status: CourseStatus = .active,
        startedOn: String? = nil,
        endedOn: String? = nil,
        stock: Stock? = nil,
        dose: Double? = nil,
        unit: String? = nil,
        scheduledToday: Bool = false,
        openSlots: [String] = [],
        lastTakenAt: String? = nil,
        comment: String? = nil,
        purpose: String? = nil,
        prescribedBy: String? = nil
    ) -> Medication {
        Medication(
            id: id,
            petID: "p1",
            name: "Дронтал Плюс",
            kind: "Таблетка",
            strength: nil,
            doseUnit: unit,
            defaultDose: dose,
            schedule: DoseSchedule(days: days, times: times),
            asNeeded: asNeeded,
            isActive: status != .ended,
            courseStatus: status,
            startedOn: startedOn,
            endedOn: endedOn,
            stock: stock,
            openSlotsToday: openSlots,
            scheduledToday: scheduledToday,
            lastTakenAt: lastTakenAt,
            lastTakenBy: nil,
            comment: comment,
            purpose: purpose,
            prescribedBy: prescribedBy,
            updatedAt: nil
        )
    }
}
