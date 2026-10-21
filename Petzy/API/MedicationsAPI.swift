import Foundation

/// Разговор с сервером про лекарства. Единственное место, где известны пути
/// `/api/medications` и ключи ответа: экран работает с `Medication` и ничего
/// не знает про JSON, поэтому правка контракта не разойдётся по приложению.
enum MedicationsAPI {
    static func list(_ client: APIClient, petID: String, zone: String) async throws -> [Medication] {
        try await decode(raw(client, petID: petID, zone: zone))
    }

    /// Ответ списка как пришёл: его же кладут в копию для работы без сети.
    static func raw(_ client: APIClient, petID: String, zone: String) async throws -> Data {
        try await client.getRaw("/api/medications?pet_id=\(AppModel.query(petID))&tz=\(AppModel.query(zone))")
    }

    /// Разбор ответа списка. Один и тот же и для сети, и для копии: второй
    /// разбор разошёлся бы с первым при первой же правке контракта.
    static func decode(_ data: Data) throws -> [Medication] {
        try JSONDecoder().decode(ListResponse.self, from: data).medications.map(\.domain)
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

    /// Тела запросов как байты: очередь офлайн-записей хранит их, чтобы
    /// отправить ровно то же, что ушло бы в сеть.
    static func coursePayload(_ draft: MedicationDraft, localID: String) -> Data? {
        try? JSONEncoder().encode(MedicationBody(draft: draft, isNew: true, localID: localID))
    }

    static func intakePayload(_ mark: IntakeMark, localID: String) -> Data? {
        try? JSONEncoder().encode(IntakeBody(mark: mark, localID: localID))
    }

    /// Тело правки как байты: очередь офлайн-правок хранит его вместе с
    /// версией, которую человек видел, иначе сервер не заметил бы, что курс
    /// поменяли.
    static func updatePayload(_ draft: MedicationDraft, baseVersion: String?) -> Data? {
        try? JSONEncoder().encode(MedicationBody(draft: draft, isNew: false, baseVersion: baseVersion))
    }

    static func update(
        _ client: APIClient,
        medicationID: String,
        draft: MedicationDraft,
        baseVersion: String? = nil
    ) async throws {
        let ack: WriteAck = try await client.put(
            "/api/medications/\(medicationID)",
            body: MedicationBody(draft: draft, isNew: false, baseVersion: baseVersion)
        )
        _ = ack
    }

    static func delete(_ client: APIClient, medicationID: String) async throws {
        try await client.delete("/api/medications/\(medicationID)")
    }

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

    /// Перенести отмеченный приём на другое время. Доза и остаток не
    /// меняются: человек ошибся временем, а не дозой.
    static func moveIntake(
        _ client: APIClient,
        intakeID: String,
        date: String,
        time: String,
        zone: String
    ) async throws {
        let ack: WriteAck = try await client.put(
            "/api/medications/intakes/\(AppModel.query(intakeID))",
            body: IntakeTimeBody(date: date, time: time, tz: zone)
        )
        _ = ack
    }

    /// Удалить отмеченный приём: сервер возвращает в остаток то, что он
    /// списал, и слот снова становится открытым.
    static func deleteIntake(_ client: APIClient, intakeID: String) async throws {
        try await client.delete("/api/medications/intakes/\(AppModel.query(intakeID))")
    }

    static func intakes(_ client: APIClient, petID: String) async throws -> [MedicationIntake] {
        let path = "/api/medications/intakes?pet_id=\(AppModel.query(petID))&page=1&page_size=100"
        let response: IntakesResponse = try await client.get(path)
        return response.intakes.map(\.domain)
    }
}

/// Новое время отмеченного приёма. Пояс едет вместе с ним: приём переезжает
/// на часы того, кто правит.
private struct IntakeTimeBody: Encodable, Sendable {
    let date: String
    let time: String
    // Имя ключа задаёт сервер: `tz`.
    // swiftlint:disable:next identifier_name
    let tz: String
}

/// Что сервер сказал об отмеченном приёме.
struct IntakeResult: Sendable {
    let id: String?
    /// Остаток кончился прямо на этой отметке.
    let ranOut: Bool
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
    /// Комментарий, «от чего» и «кто назначил». Форма правки их показывает,
    /// а раньше они не читались, и правка затирала их молча.
    let comment: String?
    let purpose: String?
    let prescribedBy: String?
    /// Версия курса: когда его меняли в последний раз. Её приложение
    /// отправляет при правке, и сервер отвечает отказом, если курс поменяли
    /// с тех пор.
    let updatedAt: String?

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
        case comment, purpose
        case prescribedBy = "prescribed_by"
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
        case updatedAt = "updated_at"
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
            lastTakenBy: lastTakenBy,
            comment: comment,
            purpose: purpose,
            prescribedBy: prescribedBy,
            updatedAt: updatedAt
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
    let skipped: Bool?
    let username: String?
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case medicationID = "medication_id"
        case medicationName = "medication_name"
        case dateTime = "date_time"
        case doseTaken = "dose_taken"
        case skipped
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
            skipped: skipped ?? false,
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
