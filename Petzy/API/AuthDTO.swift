import Foundation

/// Тела и ответы входа и обновления токенов: то, что уходит на сервер и
/// приходит с него. Дальше этого файла токены не разбираются: `AuthSession`
/// работает с ними как с парой строк.
///
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

// Ответ на вход. Токены приходят только нативному клиенту (запрос без Origin),
// веб-приложение получает вместо них httpOnly-куки.

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

// Значение поля записи. У разных типов записи поля разные, и в одном и том же
// поле встречаются и числа, и текст, поэтому единого типа здесь не будет.
// Число и текст различаем при разборе, а не догадываемся при показе.
