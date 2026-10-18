import Foundation

/// Токены на устройстве. Access живёт 15 минут, refresh неделю.
struct StoredTokens: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
}

/// Где лежат токены. Отдельный протокол, а не Keychain внутри AuthSession:
/// в тестах Keychain на симуляторе без entitlements не работает, а подменять
/// хранилище нужно в половине тестов.
protocol TokenStorage: Sendable {
    func read() throws -> StoredTokens?
    func write(_ tokens: StoredTokens) throws
    func clear() throws
}

/// Хранилище в памяти процесса. Для тестов и превью.
final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: StoredTokens?

    init(tokens: StoredTokens? = nil) {
        self.tokens = tokens
    }

    func read() throws -> StoredTokens? {
        lock.withLock { tokens }
    }

    func write(_ tokens: StoredTokens) throws {
        lock.withLock { self.tokens = tokens }
    }

    func clear() throws {
        lock.withLock { tokens = nil }
    }
}
