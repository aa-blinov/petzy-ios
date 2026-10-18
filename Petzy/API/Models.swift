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
