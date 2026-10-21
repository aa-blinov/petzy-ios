import Foundation

enum AppConfig {
    /// Адрес API. По умолчанию локальный стек petzy, он поднимается в `petzy/`.
    /// Продакшен: `-petzyBaseURL https://petzy.duckdns.org` при запуске.
    static var baseURL: URL {
        // Одной строкой: на несколько строк swiftformat уносит открывающую
        // скобку, а swiftlint за это ругается. Пусть будет одно условие.
        let override = UserDefaults.standard.string(forKey: "petzyBaseURL").flatMap(URL.init(string:))
        if let override {
            return override
        }
        let fallback = Bundle.main.object(forInfoDictionaryKey: "PETZY_API_BASE_URL") as? String ?? ""
        precondition(!fallback.isEmpty, "PETZY_API_BASE_URL не задан в Info.plist")
        // swiftlint:disable:next force_unwrapping
        return URL(string: fallback)!
    }

    /// Адрес сайта: по нему открывается ссылка на медкарту, которой делятся с
    /// врачом. В проде он совпадает с адресом API, а на стенде это другой порт
    /// (веб на 3000, API на 5002), и ссылка от API отвечала бы 404.
    static var webBaseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "PETZY_WEB_BASE_URL") as? String
        return resolveWebBase(api: baseURL, configured: configured)
    }

    /// Разбор адреса без чтения настроек: так его проверяет тест.
    static func resolveWebBase(api: URL, configured: String?) -> URL {
        let override = UserDefaults.standard.string(forKey: "petzyWebBaseURL").flatMap(URL.init(string:))
        if let override {
            return override
        }
        guard let configured, let url = URL(string: configured) else { return api }
        return url
    }

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        // Не ждём сети дольше пользователя: при выключенном Wi-Fi лучше ошибка.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}
