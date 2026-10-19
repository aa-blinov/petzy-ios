import Foundation
@testable import Petzy
import Testing

/// Запись приёма и правки курса. Здесь важно не само значение ответа, а тело
/// запроса: сервер валидирует расписание, остаток и слот, и ошибка приходит
/// текстом оттуда. Тест читает именно тело, а не то, что метод вернул.
@Suite("Лекарства: запись")
struct MedicationsWriteTests {
    @Test("Новый курс уходит с расписанием и питомцем")
    func createSendsFullBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "message": "Лекарство добавлено", "id": "m9"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await MedicationsAPI.create(client, draft: Self.draft)

        #expect(StubURLProtocol.requestedPaths == ["/api/medications"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["pet_id"] as? String == "p1")
        #expect(body["name"] as? String == "Дронтал Плюс")
        #expect(body["type"] as? String == "Таблетка")
        #expect(body["as_needed"] as? Bool == false)
        let schedule = try #require(body["schedule"] as? [String: Any])
        #expect(schedule["times"] as? [String] == ["09:00"])
        #expect((schedule["days"] as? [Int])?.count == 7)
    }

    @Test("Пустой остаток не отправляется, а нулевой уходит")
    func createSendsStockOnlyWhenAsked() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "m9"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        var withoutStock = Self.draft
        withoutStock.inventoryEnabled = false
        withoutStock.inventoryCurrent = nil
        _ = try await MedicationsAPI.create(client, draft: withoutStock)
        var body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["inventory_enabled"] as? Bool == false)
        #expect(body["inventory_current"] == nil)

        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "m9"])
        var withStock = Self.draft
        withStock.inventoryEnabled = true
        withStock.inventoryCurrent = 0
        _ = try await MedicationsAPI.create(client, draft: withStock)
        body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["inventory_enabled"] as? Bool == true)
        #expect(body["inventory_current"] as? Double == 0)
    }

    @Test("Отметка приёма закрывает именно тот слот, который нажали")
    func logIntakeClosesChosenSlot() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "i1", "ran_out": false])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let result = try await MedicationsAPI.logIntake(client, mark: IntakeMark(
            medicationID: "m1",
            moment: Moment(day: "2026-10-18", time: "14:30"),
            zone: "Asia/Almaty",
            dose: 2,
            slot: DoseSlot(date: "2026-10-18", time: "09:00")
        ))

        #expect(StubURLProtocol.requestedPaths == ["/api/medications/m1/log"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["date"] as? String == "2026-10-18")
        #expect(body["time"] as? String == "14:30")
        #expect(body["tz"] as? String == "Asia/Almaty")
        #expect(body["dose_taken"] as? Double == 2)
        #expect(body["slot_date"] as? String == "2026-10-18")
        #expect(body["slot_time"] as? String == "09:00")
        #expect(result.ranOut == false)
    }

    @Test("Пропущенный приём помечается, а доза не уходит")
    func skipSendsSkippedFlag() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "i2", "ran_out": false])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await MedicationsAPI.logIntake(client, mark: IntakeMark(
            medicationID: "m1",
            moment: Moment(day: "2026-10-18", time: "09:05"),
            zone: "Asia/Almaty",
            dose: 2,
            slot: nil,
            skipped: true
        ))

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["skipped"] as? Bool == true)
        #expect(body["dose_taken"] == nil)
    }

    @Test("Кончившийся остаток приходит отдельным флагом")
    func logIntakeReportsRanOut() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "i3", "ran_out": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let result = try await MedicationsAPI.logIntake(client, mark: IntakeMark(
            medicationID: "m1", moment: Moment(day: "2026-10-18", time: "09:00"),
            zone: "Asia/Almaty", dose: 1, slot: nil
        ))

        #expect(result.ranOut)
    }

    @Test("Пополнение остатка шлёт только количество")
    func restockSendsAmount() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Остаток пополнен"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicationsAPI.restock(client, medicationID: "m1", amount: 12)

        #expect(StubURLProtocol.requestedPaths == ["/api/medications/m1/restock"])
        #expect(TestSupport.body(of: StubURLProtocol.requests.last)["amount"] as? Double == 12)
    }

    @Test("Правка курса шлёт только то, что поменяли")
    func updateSendsOnlyChanges() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Лекарство обновлено"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicationsAPI.update(client, medicationID: "m1", draft: Self.draft)

        #expect(StubURLProtocol.requestedPaths == ["/api/medications/m1"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["name"] as? String == "Дронтал Плюс")
        // pet_id в правке не отправляется: питомца у курса не меняют.
        #expect(body["pet_id"] == nil)
    }

    @Test("Удаление курса уходит отдельным методом")
    func deleteCallsDelete() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Лекарство удалено"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicationsAPI.delete(client, medicationID: "m1")

        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
        #expect(StubURLProtocol.requestedPaths == ["/api/medications/m1"])
    }

    @Test("Завершение курса шлёт два поля, а не весь курс заново")
    func courseToggleSendsTwoFields() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Лекарство обновлено"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicationsAPI.setCourseActive(client, medicationID: "m1", isActive: false, endedOn: "2026-10-18")

        #expect(StubURLProtocol.requestedPaths == ["/api/medications/m1"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["is_active"] as? Bool == false)
        #expect(body["ended_on"] as? String == "2026-10-18")
        #expect(body["name"] == nil)
        #expect(body["schedule"] == nil)
    }

    @Test("Возобновление курса убирает дату окончания пустой строкой")
    func courseResumeClearsEndDate() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Лекарство обновлено"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await MedicationsAPI.setCourseActive(client, medicationID: "m1", isActive: true, endedOn: "")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["is_active"] as? Bool == true)
        #expect(body["ended_on"] as? String == "")
    }

    @Test("История приёмов разбирается вместе с курсом и автором")
    func intakesAreMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "intakes": [
                [
                    "_id": "i1", "medication_id": "m1", "medication_name": "Дронтал Плюс",
                    "pet_id": "p1", "date_time": "2026-10-06T08:43:00+05:00",
                    "dose_taken": 2.5, "username": "demo", "comment": "", "tz": "Asia/Almaty"
                ]
            ],
            "page": 1, "page_size": 100, "total": 1
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let intakes = try await MedicationsAPI.intakes(client, petID: "p1")

        #expect(intakes.count == 1)
        #expect(intakes.first?.medicationName == "Дронтал Плюс")
        #expect(intakes.first?.dose == 2.5)
        #expect(intakes.first?.author == "demo")
    }

    static var draft: MedicationDraft {
        MedicationDraft(
            petID: "p1",
            name: "Дронтал Плюс",
            kind: "Таблетка",
            strength: "150 мг",
            doseUnit: "таб",
            defaultDose: 1,
            schedule: DoseSchedule(days: [0, 1, 2, 3, 4, 5, 6], times: ["09:00"]),
            asNeeded: false,
            inventoryEnabled: true,
            inventoryCurrent: 10,
            inventoryTotal: 10,
            inventoryWarningDays: 3,
            comment: nil,
            startedOn: "2026-10-01",
            endedOn: nil,
            purpose: "От глистов",
            prescribedBy: "Вет Д."
        )
    }

    /// Правка курса без даты начала не должна получить сегодняшнюю при правке, а
    /// комментарий, «от чего» и «кто назначил» должны пережить её: форма
    /// показывает их, значит их и отправляет.
    @Test("Правка курса без даты начала не ставит её")
    func editWithoutStartKeepsItUnset() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var draft = MedicationsWriteTests.draft
        draft.startedOn = nil

        try await MedicationsAPI.update(client, medicationID: "m1", draft: draft)

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["started_on"] as? String == "", "дата начала должна убираться пустой строкой")
    }

    /// Снятый переключатель учёта остатка должен уйти на сервер и выключить
    /// списание, а не остаться в теле запроса как `true`.
    @Test("Правка курса гасит учёт остатка, когда переключатель снят")
    func editTurnsInventoryOff() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var draft = MedicationsWriteTests.draft
        draft.inventoryEnabled = false

        try await MedicationsAPI.update(client, medicationID: "m1", draft: draft)

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["inventory_enabled"] as? Bool == false)
        #expect(body["inventory_current"] == nil)
        #expect(body["inventory_total"] == nil)
    }
}
