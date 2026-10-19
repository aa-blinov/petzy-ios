import Foundation

/// Всё, чем может не ответить бэкенд. Тексты русские: интерфейс приложения русский.
enum APIError: Error, LocalizedError, Sendable, Equatable {
    /// Ответ с кодом и сообщением от бэкенда. Текст показываем как есть.
    case server(code: String?, message: String)
    /// Сервер не ответил или соединение не прошло.
    case transport(String)
    /// Ответ пришёл, но не разобрался: обычно бэкенд поменял контракт.
    case decoding(String)
    /// Токен не действует: сервер ответил 401 и обновиться не вышло.
    /// Отличаем от `signedOut`, где токена просто нет.
    case unauthorized
    /// Токена в приложении нет: вход ещё не проходили.
    case signedOut

    var errorDescription: String? {
        switch self {
        case let .server(_, message): message
        case let .transport(text): "Сервер не отвечает (\(text))"
        case let .decoding(text): "Сервер ответил не так, как ждём (\(text))"
        case .unauthorized: "Сессия закончилась, войдите заново"
        case .signedOut: "Сначала войдите"
        }
    }

    /// Сервера не было: обрыв, нет сети, таймаут. Отличать от отказа важно
    /// везде, где решение зависит от того, дошёл ли запрос: несуществующую сеть
    /// стоит переждать, а отказ сервера — показать.
    var isTransport: Bool {
        if case .transport = self {
            return true
        }
        return false
    }

    /// Код, который вернул бэкенд: `record_deleted`, `local_id_taken` и
    /// подобные. По нему приложение узнаёт, что запись удалили на другом
    /// устройстве, а не просто что запрос не прошёл.
    var code: String? {
        if case let .server(code, _) = self {
            return code
        }
        return nil
    }

    /// Сессию надо пересоздать: экран входа.
    var isAuthProblem: Bool {
        switch self {
        case .unauthorized, .signedOut: true
        default: false
        }
    }
}
