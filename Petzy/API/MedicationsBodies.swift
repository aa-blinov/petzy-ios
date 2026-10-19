import Foundation

// MARK: - Тела запросов

/// Тела запросов тоже на уровне файла: наружу они не выходят, наружу уходит
/// `MedicationDraft` и `IntakeMark`.
struct MedicationBody: Encodable {
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
    /// Пустая строка в датах означает «убери», а `nil` — «не трогай». На
    /// правке выключенный выключатель даты обязан убирать её, иначе человек
    /// не смог бы снять дату с курса, а пустая форма сохранила бы прежнюю.
    let isNew: Bool

    init(draft: MedicationDraft, isNew: Bool) {
        self.isNew = isNew
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
        startedOn = draft.startedOn ?? (isNew ? nil : "")
        endedOn = draft.endedOn ?? (isNew ? nil : "")
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

struct IntakeBody: Encodable {
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

/// Завершение курса: два поля и ничего больше. Пустая `ended_on` на сервере
/// значит «убери дату окончания», а `null` значит «не трогай».
struct CourseBody: Encodable {
    let isActive: Bool
    let endedOn: String

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case endedOn = "ended_on"
    }
}

struct RestockBody: Encodable {
    let amount: Double
}
