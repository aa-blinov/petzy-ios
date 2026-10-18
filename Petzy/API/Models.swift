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
enum FieldValue: Decodable, Sendable {
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
}

/// Запись дневника. `date_time` приходит как «2026-10-04 11:00»: время человека,
/// а не сервера, поэтому разбираем его строкой и не переводим в Date.
struct PetEvent: Decodable, Sendable, Identifiable {
    let id: String
    let type: String
    let dateTime: String
    let comment: String
    let fields: [String: FieldValue]
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, comment, fields
        case dateTime = "date_time"
        case isDeleted = "is_deleted"
    }

    /// `is_deleted` приходит только у надгробий: у живой записи этого поля нет
    /// вовсе. Без decodeIfPresent любая запись ленты не распарсилась бы.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        dateTime = try container.decode(String.self, forKey: .dateTime)
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        fields = try container.decodeIfPresent([String: FieldValue].self, forKey: .fields) ?? [:]
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
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
        String(dateTime.prefix { $0 != " " })
    }

    var time: String {
        dateTime.split(separator: " ").last.map(String.init) ?? ""
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

/// Поле типа записи: как оно называется в записи и как подписано для человека.
/// Подпись нужна для показа: ключ `weight` в ленте читаться не должен.
struct EventFieldInfo: Decodable, Sendable {
    let name: String
    let label: String
}

/// Тип записи: как она называется, каким значком рисуется и какие у неё поля.
struct EventTypeInfo: Decodable, Sendable {
    let key: String
    let label: String
    let icon: String?
    let fields: [EventFieldInfo]
}

struct EventTypesResponse: Decodable, Sendable {
    let eventTypes: [EventTypeInfo]

    enum CodingKeys: String, CodingKey {
        case eventTypes = "event_types"
    }
}
