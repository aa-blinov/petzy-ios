import Foundation

/// Отмеченный приём лекарства: что дали, когда и сколько. Это факт дневника
/// наравне с записью, поэтому он и живёт в домене: его показывает и раздел
/// лекарств, и общая лента.
struct MedicationIntake: Identifiable, Sendable, Equatable, Codable {
    let id: String
    let medicationID: String
    let medicationName: String
    let day: String
    let time: String
    let dose: Double
    /// Единица измерения курса: «мл», «таб». У старых приёмов её нет, и строка
    /// тогда показывает одно число.
    let unit: String?
    /// Приём пропущен: слот закрыт, а из остатка ничего не вычтено. Путать его
    /// с данным нельзя, поэтому и в строке он называется иначе.
    let skipped: Bool
    let author: String?
    let comment: String?

    /// «2,5 мл» или «2,5», если единицы нет.
    var doseText: String {
        guard let unit, !unit.isEmpty else { return Amount.text(dose) }
        return "\(Amount.text(dose)) \(unit)"
    }

    /// Строка приёма разбирается из того же ответа, что и запись дневника:
    /// сервер называет день `date_time`, а приложение держит день и время
    /// раздельно, чтобы сортировать их строками одного формата.
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case medicationID = "medication_id"
        case medicationName = "medication_name"
        case dateTime = "date_time"
        case dose = "dose_taken"
        case unit = "dose_unit"
        case skipped, username, comment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        medicationID = try container.decodeIfPresent(String.self, forKey: .medicationID) ?? ""
        medicationName = try container.decodeIfPresent(String.self, forKey: .medicationName) ?? "Лекарство"
        let moment = try container.decode(String.self, forKey: .dateTime)
        day = MomentText.day(of: moment)
        time = MomentText.time(of: moment)
        dose = try container.decodeIfPresent(Double.self, forKey: .dose) ?? 0
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        skipped = try container.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        author = try container.decodeIfPresent(String.self, forKey: .username)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }

    /// Своя запись в копию: `date_time` — это то, что сервер отдал, а держим мы
    /// день и время. Обратный ход собирает их снова.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(medicationID, forKey: .medicationID)
        try container.encode(medicationName, forKey: .medicationName)
        try container.encode("\(day)T\(time):00", forKey: .dateTime)
        try container.encode(dose, forKey: .dose)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encode(skipped, forKey: .skipped)
        try container.encodeIfPresent(author, forKey: .username)
        try container.encodeIfPresent(comment, forKey: .comment)
    }

    init(
        id: String,
        medicationID: String,
        medicationName: String,
        day: String,
        time: String,
        dose: Double,
        unit: String? = nil,
        skipped: Bool = false,
        author: String? = nil,
        comment: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.day = day
        self.time = time
        self.dose = dose
        self.unit = unit
        self.skipped = skipped
        self.author = author
        self.comment = comment
    }
}
