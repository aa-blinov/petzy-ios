import Foundation

/// Разговор с сервером про лекарства. Единственное место, где известны пути
/// `/api/medications` и ключи ответа: экран работает с `Medication` и ничего
/// не знает про JSON, поэтому правка контракта не разойдётся по приложению.
enum MedicationsAPI {
    static func list(_ client: APIClient, petID: String, zone: String) async throws -> [Medication] {
        let path = "/api/medications?pet_id=\(AppModel.query(petID))&tz=\(AppModel.query(zone))"
        let response: ListResponse = try await client.get(path)
        return response.medications.map(\.domain)
    }

    /// Ближайшие приёмы по всем курсам питомца, с флагом просрочки. Один
    /// запрос на вкладку, вместо обхода каждого курса.
    static func upcoming(_ client: APIClient, petID: String, zone: String) async throws -> [UpcomingDose] {
        let path = "/api/medications/upcoming?pet_id=\(AppModel.query(petID))&tz=\(AppModel.query(zone))"
        let response: UpcomingResponse = try await client.get(path)
        return response.doses.map(\.domain)
    }

    // MARK: - Запись

    @discardableResult
    static func create(_ client: APIClient, draft: MedicationDraft) async throws -> String? {
        let ack: WriteAck = try await client.post("/api/medications", body: MedicationBody(draft: draft, isNew: true))
        return ack.id
    }

    static func update(_ client: APIClient, medicationID: String, draft: MedicationDraft) async throws {
        let ack: WriteAck = try await client.put(
            "/api/medications/\(medicationID)", body: MedicationBody(draft: draft, isNew: false)
        )
        _ = ack
    }

    static func delete(_ client: APIClient, medicationID: String) async throws {
        try await client.delete("/api/medications/\(medicationID)")
    }

    /// Отметка приёма. `slot` говорит, какой приём по расписанию закрывает эта
    /// отметка: без него сервер закроет ближайший открытый, и нажатие «09:00»
    /// могло бы закрыть «21:00». Ответ сообщает, кончился ли остаток: об этом
    /// человек должен узнать сразу, а не путая пустую упаковку.
    /// Отметка приёма. `slot` внутри отметки говорит, какой приём по расписанию
    /// она закрывает: без него сервер закроет ближайший открытый, и нажатие
    /// «09:00» могло бы закрыть «21:00». Ответ сообщает, кончился ли остаток:
    /// об этом человек должен узнать сразу, а не путая пустую упаковку.
    @discardableResult
    static func logIntake(_ client: APIClient, mark: IntakeMark) async throws -> IntakeResult {
        let ack: WriteAck = try await client.post(
            "/api/medications/\(mark.medicationID)/log",
            body: IntakeBody(mark: mark)
        )
        return IntakeResult(id: ack.id, ranOut: ack.ranOut ?? false)
    }

    /// Завершить или возобновить курс. Отдельным методом, а не полной правкой:
    /// сервер принимает частичное обновление, и отправлять сюда весь курс
    /// означало бы затереть чужую правку, сделанную с телефона в это же время.
    static func setCourseActive(
        _ client: APIClient,
        medicationID: String,
        isActive: Bool,
        endedOn: String
    ) async throws {
        let ack: WriteAck = try await client.put(
            "/api/medications/\(medicationID)",
            body: CourseBody(isActive: isActive, endedOn: endedOn)
        )
        _ = ack
    }

    static func restock(_ client: APIClient, medicationID: String, amount: Double) async throws {
        let ack: WriteAck = try await client.post(
            "/api/medications/\(medicationID)/restock",
            body: RestockBody(amount: amount)
        )
        _ = ack
    }

    static func intakes(_ client: APIClient, petID: String) async throws -> [MedicationIntake] {
        let path = "/api/medications/intakes?pet_id=\(AppModel.query(petID))&page=1&page_size=100"
        let response: IntakesResponse = try await client.get(path)
        return response.intakes.map(\.domain)
    }
}

// MARK: - Тела запросов

/// Тела запросов тоже на уровне файла: наружу они не выходят, наружу уходит
/// `MedicationDraft` и `IntakeMark`.
private struct MedicationBody: Encodable {
    let petID: String?
    let name: String
    let type: String
    let strength: String?
    let doseUnit: String?
    let defaultDose: Double?
    let schedule: DoseSchedule
    let asNeeded: Bool
    let inventoryEnabled: Bool
    let inventoryCurrent: Double?
    let inventoryTotal: Double?
    let inventoryWarningDays: Double?
    let comment: String?
    let startedOn: String?
    let endedOn: String?
    let purpose: String?
    let prescribedBy: String?

    /// `pet_id` уходит только при создании: у курса питомца не меняют.
    init(draft: MedicationDraft, isNew: Bool) {
        petID = isNew ? draft.petID : nil
        name = draft.name
        type = draft.kind
        strength = draft.strength
        doseUnit = draft.doseUnit
        defaultDose = draft.defaultDose
        schedule = draft.schedule
        asNeeded = draft.asNeeded
        inventoryEnabled = draft.inventoryEnabled
        // Остаток без «считать» бессмыслен: сервер рисует остаток только
        // когда его включили, и нулевой остаток при этом настоящий.
        inventoryCurrent = draft.inventoryEnabled ? draft.inventoryCurrent : nil
        inventoryTotal = draft.inventoryEnabled ? draft.inventoryTotal : nil
        inventoryWarningDays = draft.inventoryEnabled ? draft.inventoryWarningDays : nil
        comment = draft.comment
        startedOn = draft.startedOn
        endedOn = draft.endedOn
        purpose = draft.purpose
        prescribedBy = draft.prescribedBy
    }

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case name, type, strength, schedule
        case doseUnit = "dose_unit"
        case defaultDose = "default_dose"
        case asNeeded = "as_needed"
        case inventoryEnabled = "inventory_enabled"
        case inventoryCurrent = "inventory_current"
        case inventoryTotal = "inventory_total"
        case inventoryWarningDays = "inventory_warning_days"
        case comment
        case startedOn = "started_on"
        case endedOn = "ended_on"
        case purpose
        case prescribedBy = "prescribed_by"
    }
}

private struct IntakeBody: Encodable {
    let date: String
    let time: String
    /// Ключ на стороне сервера короткий, `tz`. Имя в Swift длинное, потому что
    /// трёхбуквенное ловит линтер, а «zone» ещё и читается рядом с датой.
    let zone: String
    let doseTaken: Double?
    let skipped: Bool
    let slotDate: String?
    let slotTime: String?

    init(mark: IntakeMark) {
        date = mark.moment.day
        time = mark.moment.time
        zone = mark.zone
        doseTaken = mark.skipped ? nil : mark.dose
        skipped = mark.skipped
        slotDate = mark.slot?.date
        slotTime = mark.slot?.time
    }

    enum CodingKeys: String, CodingKey {
        case date, time
        case zone = "tz"
        case doseTaken = "dose_taken"
        case skipped
        case slotDate = "slot_date"
        case slotTime = "slot_time"
    }
}

/// Что сервер сказал об отмеченном приёме.
struct IntakeResult: Sendable {
    let id: String?
    /// Остаток кончился прямо на этой отметке.
    let ranOut: Bool
}

/// Завершение курса: два поля и ничего больше. Пустая `ended_on` на сервере
/// значит «убери дату окончания», а `null` значит «не трогай».
private struct CourseBody: Encodable {
    let isActive: Bool
    let endedOn: String

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case endedOn = "ended_on"
    }
}

private struct RestockBody: Encodable {
    let amount: Double
}

/// Ответ на запись: у разных маршрутов свой набор, лишние ключи игнорируются.
private struct WriteAck: Decodable {
    let id: String?
    let ranOut: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case ranOut = "ran_out"
    }
}

/// DTO лежат на уровне файла, а не внутри `MedicationsAPI`: вложенные в тип
/// типы дают два уровня вложенности и раздувают тело до отказа линтера, а
/// наружу всё равно не выходят — наружу доменные значения.
private struct ListResponse: Decodable {
    let medications: [MedicationDTO]
}

private struct UpcomingResponse: Decodable {
    let doses: [UpcomingDoseDTO]
}

private struct IntakesResponse: Decodable {
    let intakes: [IntakeDTO]
}

/// Поля, которые приложение читает. Остальные сервер присылает, и они
/// просто не разбираются: лишнее поле в ответе не должно ломать разбор.
private struct MedicationDTO: Decodable {
    let id: String
    let petID: String
    let name: String
    let type: String
    let strength: String?
    let doseUnit: String?
    let defaultDose: Double?
    let schedule: ScheduleDTO
    let asNeeded: Bool?
    let isActive: Bool
    let courseStatus: String?
    let startedOn: String?
    let endedOn: String?
    let inventoryEnabled: Bool
    let inventoryCurrent: Double?
    let inventoryTotal: Double?
    let inventoryDaysLeft: Double?
    let inventoryLow: Bool?
    let inventoryWarningDays: Double?
    let openSlotsToday: [String]?
    let scheduledToday: Bool?
    let lastTakenAt: String?
    let lastTakenBy: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case petID = "pet_id"
        case name, type, strength
        case doseUnit = "dose_unit"
        case defaultDose = "default_dose"
        case schedule
        case asNeeded = "as_needed"
        case isActive = "is_active"
        case courseStatus = "course_status"
        case startedOn = "started_on"
        case endedOn = "ended_on"
        case inventoryEnabled = "inventory_enabled"
        case inventoryCurrent = "inventory_current"
        case inventoryTotal = "inventory_total"
        case inventoryDaysLeft = "inventory_days_left"
        case inventoryLow = "inventory_low"
        case inventoryWarningDays = "inventory_warning_days"
        case openSlotsToday = "open_slots_today"
        case scheduledToday = "scheduled_today"
        case lastTakenAt = "last_taken_at"
        case lastTakenBy = "last_taken_by"
    }

    /// Курсы, заведённые до признака «по необходимости», хранили этот
    /// режим пустым расписанием. Без этой подстановки такой курс вышел
    /// бы без расписания и без кнопки приёма.
    var domain: Medication {
        Medication(
            id: id,
            petID: petID,
            name: name,
            kind: type,
            strength: strength,
            doseUnit: doseUnit,
            defaultDose: defaultDose,
            schedule: DoseSchedule(days: schedule.days, times: schedule.times),
            asNeeded: asNeeded ?? schedule.times.isEmpty,
            isActive: isActive,
            courseStatus: CourseStatus.resolve(courseStatus, isActive: isActive),
            startedOn: startedOn,
            endedOn: endedOn,
            stock: inventoryEnabled && inventoryCurrent != nil
                ? Stock(
                    current: inventoryCurrent ?? 0,
                    total: inventoryTotal,
                    daysLeft: inventoryDaysLeft,
                    isLow: inventoryLow ?? false,
                    warningDays: inventoryWarningDays
                )
                : nil,
            openSlotsToday: openSlotsToday ?? [],
            scheduledToday: scheduledToday ?? false,
            lastTakenAt: lastTakenAt,
            lastTakenBy: lastTakenBy
        )
    }
}

private struct ScheduleDTO: Decodable {
    let days: [Int]
    let times: [String]
}

private struct IntakeDTO: Decodable {
    let id: String
    let medicationID: String
    let medicationName: String
    let dateTime: String
    let doseTaken: Double
    let username: String?
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case medicationID = "medication_id"
        case medicationName = "medication_name"
        case dateTime = "date_time"
        case doseTaken = "dose_taken"
        case username, comment
    }

    var domain: MedicationIntake {
        MedicationIntake(
            id: id,
            medicationID: medicationID,
            medicationName: medicationName,
            day: MomentText.day(of: dateTime),
            time: MomentText.time(of: dateTime),
            dose: doseTaken,
            author: username,
            comment: comment
        )
    }
}

private struct UpcomingDoseDTO: Decodable {
    let medicationID: String
    let name: String
    let type: String
    let time: String
    let date: String
    let isOverdue: Bool
    let inventoryWarning: Bool
    let carriedOver: Bool?

    enum CodingKeys: String, CodingKey {
        case medicationID = "medication_id"
        case name, type, time, date
        case isOverdue = "is_overdue"
        case inventoryWarning = "inventory_warning"
        case carriedOver = "carried_over"
    }

    var domain: UpcomingDose {
        UpcomingDose(
            medicationID: medicationID,
            name: name,
            kind: type,
            time: time,
            date: date,
            isOverdue: isOverdue,
            inventoryWarning: inventoryWarning,
            carriedOver: carriedOver ?? false
        )
    }
}
