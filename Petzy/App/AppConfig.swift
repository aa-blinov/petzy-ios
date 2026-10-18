import Foundation

enum AppConfig {
    /// Адрес API. По умолчанию локальный стек petzy, он поднимается в `petzy/`.
    /// Продакшен: `-petzyBaseURL https://petzy.duckdns.org` при запуске.
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "petzyBaseURL"),
           let url = URL(string: override) {
            return url
        }
        let fallback = Bundle.main.object(forInfoDictionaryKey: "PETZY_API_BASE_URL") as? String ?? ""
        precondition(!fallback.isEmpty, "PETZY_API_BASE_URL не задан в Info.plist")
        // swiftlint:disable:next force_unwrapping
        return URL(string: fallback)!
    }

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        // Не ждём сети дольше пользователя: при выключенном Wi-Fi лучше ошибка.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}
