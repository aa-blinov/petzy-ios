import Foundation

struct PetsResponse: Decodable, Sendable {
    let pets: [Pet]
}

/// Питомец. Набор полей пока неполный: `/api/pets` отдаёт ещё `look`,
/// `tiles_settings`, `health_notes` и другие. Добавляем поле по мере надобности.
struct Pet: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let species: String?
    let breed: String?
    let birthDate: String?
    let gender: String?
    /// Подписанный адрес фотографии питомца. Список питомцев отдаёт его
    /// вместе с остальным, и телефон ходит по нему сам, без токена: подпись
    /// в самой ссылке.
    ///
    /// Ограничение: адрес живёт час-два, и когда он протухает, фото в карточке
    /// надо перезапросить. Пока это незаметно: список питомцев перечитывается
    /// при запуске приложения, а загруженная картинка остаётся в памяти.
    let photoURL: URL?
    /// Версия питомца: когда его меняли в последний раз. Её приложение
    /// отправляет при правке, и сервер отвечает отказом, если питомца поменяли
    /// с тех пор.
    let updatedAt: String?
    /// Этот питомец мой: сервер отвечает `current_user_is_owner`. От флага
    /// зависит, что предлагать: пригласить или выйти.
    let isOwner: Bool
    /// С кем питомец поделён. Не-владельцу сервер это поле не отдаёт, и тогда
    /// список пуст.
    let sharedWith: [String]
    /// Кого пригласили, но кто ещё не ответил. Видит только владелец.
    let shareInvites: [String]
    /// Что на «+» у этого питомца и в каком порядке. Приходит с сервера; без
    /// ключа — умолчание, и «+» показывает восемь изначальных типов.
    let tiles: TileSettings

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, species, breed, gender
        case birthDate = "birth_date"
        case photoURL = "photo_url"
        case updatedAt = "updated_at"
        case isOwner = "current_user_is_owner"
        case sharedWith = "shared_with"
        case shareInvites = "share_invites"
        case tiles = "tiles_settings"
    }

    /// Обычный инициализатор нужен тестам и копии для офлайна: свой
    /// `init(from:)` забирает у структуры memberwise-инициализатор.
    init(
        id: String,
        name: String,
        species: String?,
        breed: String?,
        birthDate: String?,
        gender: String?,
        photoURL: URL?,
        updatedAt: String?,
        isOwner: Bool = true,
        sharedWith: [String] = [],
        shareInvites: [String] = [],
        tiles: TileSettings = TileSettings()
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.breed = breed
        self.birthDate = birthDate
        self.gender = gender
        self.photoURL = photoURL
        self.updatedAt = updatedAt
        self.isOwner = isOwner
        self.sharedWith = sharedWith
        self.shareInvites = shareInvites
        self.tiles = tiles
    }

    /// Разбор руками: ключа владения может не быть вовсе (старый ответ или
    /// копия из ленты), и тогда питомец считается своим.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        species = try container.decodeIfPresent(String.self, forKey: .species)
        breed = try container.decodeIfPresent(String.self, forKey: .breed)
        birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) ?? true
        sharedWith = try container.decodeIfPresent([String].self, forKey: .sharedWith) ?? []
        shareInvites = try container.decodeIfPresent([String].self, forKey: .shareInvites) ?? []
        tiles = try container.decodeIfPresent(TileSettings.self, forKey: .tiles) ?? TileSettings()
    }
}
