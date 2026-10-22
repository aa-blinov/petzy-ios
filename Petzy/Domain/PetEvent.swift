import Foundation

struct PetEvent: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let type: String
    let dateTime: String
    let comment: String
    let fields: [String: FieldValue]
    let isDeleted: Bool
    /// Когда запись меняли в последний раз, как отдал сервер. Это версия:
    /// приложение отправляет её при правке, и сервер отвечает отказом, если
    /// запись поменяли с тех пор.
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        /// `type` у ленты, `record_type` у таймлайна истории. Обе схемы
        /// отдают один и тот же список записей, а называют тип по-разному,
        /// и без второго имени записи истории выглядели бы записью
        /// неизвестного типа и молча пропали бы из списка.
        case type
        case recordType = "record_type"
        case comment, fields
        case dateTime = "date_time"
        case isDeleted = "is_deleted"
        case updatedAt = "updated_at"
    }

    /// `is_deleted` приходит только у надгробий: у живой записи этого поля нет
    /// вовсе. Без decodeIfPresent любая запись ленты не распарсилась бы.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dateTime = try container.decode(String.self, forKey: .dateTime)
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        fields = try container.decodeIfPresent([String: FieldValue].self, forKey: .fields) ?? [:]
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        guard let type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decodeIfPresent(String.self, forKey: .recordType)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.type,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "у записи нет ни type, ни record_type"
                )
            )
        }
        self.type = type
    }

    /// Запись пишется в локальную копию под ключом `type`: второго ключа у
    /// копии нет, а синтезировать запись не выходит из-за `recordType`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(dateTime, forKey: .dateTime)
        try container.encode(comment, forKey: .comment)
        try container.encode(fields, forKey: .fields)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    init(
        id: String,
        type: String,
        dateTime: String,
        comment: String,
        fields: [String: FieldValue],
        isDeleted: Bool,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.type = type
        self.dateTime = dateTime
        self.comment = comment
        self.fields = fields
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    var day: String {
        MomentText.day(of: dateTime)
    }

    var time: String {
        MomentText.time(of: dateTime)
    }
}

// Страница ленты. Читать надо по курсору: новая запись не сдвигает страницу,
// поэтому ни одна запись не читается дважды и ни одна не теряется.
