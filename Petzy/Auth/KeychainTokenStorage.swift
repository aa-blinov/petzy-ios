import Foundation
import Security

/// Keychain, generic password. Refresh-токен лежит здесь неделю, в UserDefaults
/// ему не место.
struct KeychainTokenStorage: TokenStorage {
    private let service: String
    private let account: String

    init(service: String = "ru.petzy.app.tokens", account: String = "session") {
        self.service = service
        self.account = account
    }

    func read() throws -> StoredTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return try JSONDecoder().decode(StoredTokens.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func write(_ tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)

        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = baseQuery
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainError: Error, CustomStringConvertible {
    let status: OSStatus

    var description: String {
        "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "ошибка \(status)")"
    }
}
