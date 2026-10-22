import Foundation

/// Пол питомца. Ключи сервера — `male` и `female`, но в старых записях лежит
/// написанное словами («Мужской»), и без перевода такое значение показывалось
/// бы прямо в карточке.
enum PetGender: CaseIterable, Sendable, Equatable {
    case unknown
    case male
    case female

    var title: String {
        switch self {
        case .unknown: "Не указан"
        case .male: "Мальчик"
        case .female: "Девочка"
        }
    }

    /// Ключ для сервера. `nil` означает «не указан», и сервер такие пустые
    /// значения чистит, а не отвергает.
    var key: String? {
        switch self {
        case .unknown: nil
        case .male: "male"
        case .female: "female"
        }
    }

    static func known(_ raw: String?) -> PetGender {
        switch raw {
        case "male", "Мужской": .male
        case "female", "Женский": .female
        default: .unknown
        }
    }
}

/// Кастрация или стерилизация. «Не указано» — третье состояние, а не
/// отсутствие ответа: сервер различает «не кастрирован» и «не сказано».
enum Neutering: CaseIterable, Sendable, Equatable {
    case unknown
    case notYet
    case done

    var title: String {
        switch self {
        case .unknown: "Не указано"
        case .notYet: "Нет"
        case .done: "Да"
        }
    }

    /// Что уходит на сервер. `nil` — поле не отправляется вовсе: пустую строку
    /// сервер не понимает и отвечает 422.
    var flag: String? {
        switch self {
        case .unknown: nil
        case .notYet: "false"
        case .done: "true"
        }
    }
}

/// Карточка питомца целиком: то, что человек видит на экране «О питомце».
/// Оформление (`look`) сюда не вносится: рамки и шрифт — украшение веба, а не
/// данные о питомце.
struct PetProfile: Sendable, Equatable {
    let id: String
    let name: String
    let species: String?
    let breed: String
    let birthDate: String?
    let gender: PetGender
    let neutering: Neutering
    let healthNotes: String
    /// Подписанный адрес фотографии. Живёт 1–2 часа и открыт без входа:
    /// подпись в самой ссылке, токен в заголовке не нужен.
    let photoURL: URL?
    /// Питомцем, к которому дали доступ, нельзя управлять, и форма без этого
    /// поля обещала бы то, что сервер не даст сделать.
    let currentUserIsOwner: Bool
    /// С кем питомец поделён: эти люди видят его и ведут записи. Пусто у
    /// питомца, к которому дали доступ, — сервер им список не отдаёт.
    let sharedWith: [String]
    /// Кого пригласили, но кто ещё не ответил. Видит только владелец.
    let shareInvites: [String]
    /// Что на «+» у этого питомца и в каком порядке.
    let tiles: TileSettings
    /// Версия питомца, которую человек видел. Её приложение отправляет при
    /// правке: сервер отвечает отказом, если питомца поменяли с тех пор.
    let updatedAt: String?

    var speciesTitle: String? {
        PetSpecies.label(for: species)
    }
}

/// Питомец в том виде, как его заполняет форма. Экран отдаёт черновик, а
/// названия полей сервера здесь не встречаются.
struct PetDraft: Sendable {
    var name = ""
    var species: String?
    var breed = ""
    /// Дата рождения. `nil` — её не называли.
    var birthDate: Date?
    var gender: PetGender = .unknown
    var neutering: Neutering = .unknown
    var healthNotes = ""
    /// Что на «+» у питомца. Хранится здесь, потому что сохраняется вместе с
    /// питомцем: отдельного запроса у сервера нет.
    var tiles = TileSettings()

    /// Что человек должен поправить до запроса, своими словами. `nil` — можно
    /// отправлять.
    static func problem(_ draft: PetDraft) -> String? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите имя питомца"
        }
        return nil
    }
}

extension PetDraft {
    /// Черновик из карточки: так форма наполняется при открытии, и так же
    /// собирается тело записи, когда набор типов правят не из формы.
    ///
    /// Фабрика, а не инициализатор: собственный `init` забрал бы у структуры
    /// memberwise, и все, кто собирает черновик по полям, перестали бы
    /// компилироваться.
    static func from(profile: PetProfile) -> PetDraft {
        var draft = PetDraft()
        draft.name = profile.name
        draft.species = profile.species
        draft.breed = profile.breed
        draft.birthDate = profile.birthDate.flatMap(MomentText.date(from:))
        draft.gender = profile.gender
        draft.neutering = profile.neutering
        draft.healthNotes = profile.healthNotes
        draft.tiles = profile.tiles
        return draft
    }
}

/// Что пропадёт вместе с питомцем. Числа приходят с сервера, а словами
/// читаются здесь: человек должен видеть цену удаления до того, как нажал.
struct PetDeletionImpact: Sendable, Equatable {
    let events: Int
    let medications: Int
    let documents: Int
    let medicalRecords: Int

    /// «264 записи в ленте, 3 лекарства, 3 документа, 8 записей медкарты».
    /// Пусто, когда пропадать нечего: тогда и предупреждать не о чем.
    var summary: String {
        var parts: [String] = []
        if events > 0 {
            parts.append("\(events) \(Words.pick(events, one: "запись", few: "записи", many: "записей")) в ленте")
        }
        if medications > 0 {
            parts.append(Words.text(medications, one: "лекарство", few: "лекарства", many: "лекарств"))
        }
        if documents > 0 {
            parts.append(Words.text(documents, one: "документ", few: "документа", many: "документов"))
        }
        if medicalRecords > 0 {
            let word = Words.pick(medicalRecords, one: "запись", few: "записи", many: "записей")
            parts.append("\(medicalRecords) \(word) медкарты")
        }
        return parts.joined(separator: ", ")
    }
}
