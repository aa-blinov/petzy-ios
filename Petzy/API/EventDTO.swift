import Foundation

/// Запросы и ответы ленты: запись в том виде, в каком её принимает и отдаёт
/// сервер. Домен (`PetEvent`) лежит отдельно: у него нет ключей ответа.
///
struct EventRequest: Encodable, Sendable {
    let petID: String?
    let date: String
    let time: String
    let comment: String
    let fields: [String: FieldValue]
    let type: String?
    /// Часовой пояс телефона: время в записи остаётся тем, что человек ввёл
    /// у себя, а не пересчитанным по серверу. На сервере поле называется `tz`,
    /// а такое короткое имя swiftlint в Swift не пропускает, поэтому здесь
    /// длиннее, а ключ остаётся серверным.
    let timeZone: String
    /// Имя, которым устройство назвало запись, если её создавали без сети.
    /// С ним повтор запроса не создаёт вторую запись, а обновляет первую.
    let localID: String?
    /// Версия записи, которую человек правил. Сервер отвечает отказом, если
    /// запись поменяли с тех пор: версия сервера остаётся, а человек узнаёт.
    let baseVersion: String?

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case date, time, comment, fields, type
        case timeZone = "tz"
        case localID = "local_id"
        case baseVersion = "base_version"
    }

    init(
        petID: String?,
        date: String,
        time: String,
        comment: String,
        fields: [String: FieldValue],
        type: String?,
        timeZone: String,
        localID: String? = nil,
        baseVersion: String? = nil
    ) {
        self.petID = petID
        self.date = date
        self.time = time
        self.comment = comment
        self.fields = fields
        self.type = type
        self.timeZone = timeZone
        self.localID = localID
        self.baseVersion = baseVersion
    }

    static func create(_ draft: EventDraft, petID: String, localID: String? = nil) -> EventRequest {
        EventRequest(
            petID: petID,
            date: draft.date,
            time: draft.time,
            comment: draft.comment,
            fields: draft.encodedFields,
            type: draft.type.key,
            timeZone: TimeZone.current.identifier,
            localID: localID
        )
    }

    /// Тело запроса как байты: очередь офлайн-записей хранит его, чтобы
    /// отправить ровно то же, что ушло бы в сеть.
    static func payload(_ draft: EventDraft, petID: String, localID: String) -> Data? {
        let request = EventRequest.create(draft, petID: petID, localID: localID)
        return try? JSONEncoder().encode(request)
    }

    /// Тело правки как байты: очередь офлайн-правок хранит его вместе с
    /// версией, которую человек видел, иначе сервер не заметил бы, что
    /// запись поменяли.
    static func updatePayload(_ draft: EventDraft, baseVersion: String?) -> Data? {
        try? JSONEncoder().encode(EventRequest.update(draft, baseVersion: baseVersion))
    }

    static func update(_ draft: EventDraft, baseVersion: String? = nil) -> EventRequest {
        EventRequest(
            petID: nil,
            date: draft.date,
            time: draft.time,
            comment: draft.comment,
            fields: draft.encodedFields,
            type: nil,
            timeZone: TimeZone.current.identifier,
            baseVersion: baseVersion
        )
    }
}

// Ответ на сохранение записи. Текст показываем как есть, он от бэкенда.

struct EventSavedResponse: Decodable, Sendable {
    let message: String
    let id: String?
}

// Запись дневника. `date_time` приходит двумя форматами: у записей, у
// которых приложение отправило часовой пояс, это ISO с ним
// («2026-10-18T14:13:00+05:00»), у старых — без пояса («2026-10-04 11:00»).
// Оба разбираются, и время остаётся тем, что человек ввёл у себя: смещение
// не переводится в часовой пояс телефона.

struct EventsPage: Decodable, Sendable {
    let items: [PetEvent]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}
