import Foundation

// CodingKeys написаны руками, а не через convertFromSnakeCase: ключ питомца
// `_id` при автоконвертации превращается в «Id», и опечатку в этом не поймать.

struct LoginRequest: Encodable, Sendable {
    let username: String
    let password: String
}

struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

/// Ответ на вход. Токены приходят только нативному клиенту (запрос без Origin),
/// веб-приложение получает вместо них httpOnly-куки.
struct AuthTokensResponse: Decodable, Sendable {
    let message: String
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case message
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct AuthRefreshResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct PetsResponse: Decodable, Sendable {
    let pets: [Pet]
}

/// Питомец. Набор полей пока неполный: `/api/pets` отдаёт ещё `look`,
/// `tiles_settings`, `health_notes` и другие. Добавляем поле по мере надобности.
struct Pet: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let species: String?
    let breed: String?
    let birthDate: String?
    let gender: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, species, breed, gender
        case birthDate = "birth_date"
    }
}

/// Значение поля записи. У разных типов записи поля разные, и в одном и том же
/// поле встречаются и числа, и текст, поэтому единого типа здесь не будет.
/// Число и текст различаем при разборе, а не догадываемся при показе.
enum FieldValue: Codable, Sendable, Equatable {
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = try .number(container.decode(Double.self))
    }

    /// Число без хвостовых нулей: вес 29,30 это тот же вес, что 29,3, и в ленте
    /// человек видит 29,3. Разделитель запятой, как в русской записи.
    var display: String {
        switch self {
        case let .text(text):
            return text
        case let .number(number):
            let rounded = (number * 10).rounded() / 10
            return String(format: "%g", rounded).replacingOccurrences(of: ".", with: ",")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text):
            try container.encode(text)
        case let .number(number):
            try container.encode(number)
        }
    }
}

/// Тело запроса записи. У создания есть тип и питомец, у правки их нет: тип у
/// записи не меняется, а питомца менять нельзя. Один тип на оба случая, чтобы
/// не держать два одинаковых описания.
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

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case date, time, comment, fields, type
        case timeZone = "tz"
    }

    static func create(_ draft: EventDraft, petID: String) -> EventRequest {
        EventRequest(
            petID: petID,
            date: draft.date,
            time: draft.time,
            comment: draft.comment,
            fields: draft.encodedFields,
            type: draft.type.key,
            timeZone: TimeZone.current.identifier
        )
    }

    static func update(_ draft: EventDraft) -> EventRequest {
        EventRequest(
            petID: nil,
            date: draft.date,
            time: draft.time,
            comment: draft.comment,
            fields: draft.encodedFields,
            type: nil,
            timeZone: TimeZone.current.identifier
        )
    }
}

/// Ответ на сохранение записи. Текст показываем как есть, он от бэкенда.
struct EventSavedResponse: Decodable, Sendable {
    let message: String
    let id: String?
}

/// Запись дневника. `date_time` приходит двумя форматами: у записей, у
/// которых приложение отправило часовой пояс, это ISO с ним
/// («2026-10-18T14:13:00+05:00»), у старых — без пояса («2026-10-04 11:00»).
/// Оба разбираются, и время остаётся тем, что человек ввёл у себя: смещение
/// не переводится в часовой пояс телефона.
struct PetEvent: Decodable, Sendable, Identifiable {
    let id: String
    let type: String
    let dateTime: String
    let comment: String
    let fields: [String: FieldValue]
    let isDeleted: Bool

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

    init(
        id: String,
        type: String,
        dateTime: String,
        comment: String,
        fields: [String: FieldValue],
        isDeleted: Bool
    ) {
        self.id = id
        self.type = type
        self.dateTime = dateTime
        self.comment = comment
        self.fields = fields
        self.isDeleted = isDeleted
    }

    var day: String {
        MomentText.day(of: dateTime)
    }

    var time: String {
        MomentText.time(of: dateTime)
    }
}

/// Разбор `date_time` в двух форматах, которые отдаёт сервер: «2026-10-04
/// 11:00» и «2026-10-18T14:13:00+05:00». Время остаётся тем, что человек ввёл
/// у себя: перевод в часовой пояс телефона увёл бы кормление с 11 утра на 6.
///
/// Вынесено отдельно, потому что тот же разбор нужен и записи ленты, и
/// точке графика, а расходиться они не должны.
enum MomentText {
    static func day(of text: String) -> String {
        String(text.prefix { $0 != " " && $0 != "T" })
    }

    /// День по-русски: «Сегодня», «Вчера» или «04.10.2026». На входе именно
    /// день `ГГГГ-ММ-ДД`, а не полный момент: полный ISO разбирать здесь нечем,
    /// и «Сегодня» превратилось бы в мусор вида «06T08:43:00+05:00.10.2026».
    static func humanDay(_ day: String, today: Date = .now, calendar: Calendar = .current) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        let start = calendar.startOfDay(for: today)
        if day == isoDay(start, calendar: calendar) {
            return "Сегодня"
        }
        // Условие в одну строку: многострочный `if let` swiftformat раскрывает
        // скобкой на новой строке, а swiftlint это запрещает.
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: start), day == isoDay(
            yesterday,
            calendar: calendar
        ) {
            return "Вчера"
        }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func time(of text: String) -> String {
        // Отрезаем секунды и смещение: «14:13:00+05:00» это «14:13».
        let tail = text.contains("T")
            ? String(text.split(separator: "T").last ?? "")
            : String(text.split(separator: " ").last ?? "")
        return String(tail.prefix(5))
    }
}

/// Страница ленты. Читать надо по курсору: новая запись не сдвигает страницу,
/// поэтому ни одна запись не читается дважды и ни одна не теряется.
struct EventsPage: Decodable, Sendable {
    let items: [PetEvent]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

/// Вариант выбора в поле. Появляется у полей вида `choice`.
struct EventFieldOption: Decodable, Sendable {
    let text: String
    let value: String
}

/// Поле типа записи: как оно называется в записи и как подписано для человека.
/// Подпись нужна для показа: ключ `weight` в ленте читаться не должен. Вид,
/// обязательность и границы нужны форме добавления, чтобы собрать запись из
/// того, что человек набрал, и не отправить на сервер ерунду.
struct EventFieldInfo: Decodable, Sendable, Identifiable {
    let name: String
    let label: String
    /// `number`, `text` или `choice`.
    let type: String
    let required: Bool
    let min: Double?
    let max: Double?
    let options: [EventFieldOption]?

    /// У поля уже есть имя, оно и есть его identity в списке.
    var id: String {
        name
    }
}

/// Тип записи: как она называется, каким значком рисуется и какие у неё поля.
/// `category` приходит `null` у своих типов, их форма выбора не спрашивает.
struct EventTypeInfo: Decodable, Sendable, Identifiable {
    let key: String
    let label: String
    let icon: String?
    let category: String?
    let fields: [EventFieldInfo]
    let chart: EventChart?

    var id: String {
        key
    }
}

/// Как рисуется график типа: `value` — линия по величине записи, `count` —
/// столбцы по количеству записей. Без него график показывал бы среднее там,
/// где нужен счёт.
struct EventChart: Decodable, Sendable, Equatable {
    let kind: String
    let valueField: String?
    /// Подпись величины с единицами измерения: «Вес (кг)». Без неё на оси
    /// были бы голые числа.
    let valueLabel: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case valueField = "value_field"
        case valueLabel = "value_label"
    }
}

/// Типы, записи о которых у питомца есть. Ими заполняется фильтр истории.
struct UsedTypesResponse: Decodable, Sendable {
    let types: [String]
}

struct EventTypesResponse: Decodable, Sendable {
    let eventTypes: [EventTypeInfo]

    enum CodingKeys: String, CodingKey {
        case eventTypes = "event_types"
    }
}
