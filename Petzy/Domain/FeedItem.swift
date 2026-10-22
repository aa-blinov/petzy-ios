import Foundation

/// Строка ленты: запись дневника или отмеченный приём лекарства. На вебе это
/// один список, и сервер отдаёт его одним ответом (`/api/history/timeline`),
/// поэтому в приложении он тоже один: два списка пришлось бы сливать по дате
/// и держать в согласии страницы.
enum FeedItem: Identifiable, Sendable, Equatable {
    case event(PetEvent)
    case intake(MedicationIntake)

    /// Разные виды приходят из разных коллекций, и их id могут совпасть. В
    /// списке это путает строки, поэтому вид входит в имя.
    var id: String {
        switch self {
        case let .event(event): "event-" + event.id
        case let .intake(intake): "dose-" + intake.id
        }
    }

    /// День записи: по нему лента раскладывается на группы.
    var day: String {
        switch self {
        case let .event(event): event.day
        case let .intake(intake): intake.day
        }
    }

    var event: PetEvent? {
        if case let .event(event) = self {
            return event
        }
        return nil
    }

    var intake: MedicationIntake? {
        if case let .intake(intake) = self {
            return intake
        }
        return nil
    }
}

extension FeedItem: Decodable {
    /// Приём отличается от записи одним ключом: сервер ставит
    /// `record_type: medications` и в нём же присылает приём.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .recordType)
        if kind == "medications" {
            self = try .intake(MedicationIntake(from: decoder))
        } else {
            self = try .event(PetEvent(from: decoder))
        }
    }

    private enum Keys: String, CodingKey {
        case recordType = "record_type"
    }
}

extension FeedItem: Encodable {
    /// Копия ленты читается тем же кодом, что и сетевой ответ, значит и вид в
    /// ней должен быть: у записи он свой (`type`), а приёму его надо поставить
    /// руками. Без метки приём при чтении разбирался как запись, падал, и
    /// вместе с ним терялась вся копия.
    func encode(to encoder: Encoder) throws {
        switch self {
        case let .event(event):
            try event.encode(to: encoder)
        case let .intake(intake):
            try intake.encode(to: encoder)
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode("medications", forKey: .recordType)
        }
    }
}
