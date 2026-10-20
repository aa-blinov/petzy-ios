import Foundation

/// Токены и вход. Единственное место, где живёт логика обновления: refresh
/// выдаёт новый refresh-токен и заменяет старый, а старый, предъявленный позже
/// 30 секунд, считается украденным и выкидывает сессию целиком.
actor AuthSession {
    private let baseURL: URL
    private let urlSession: URLSession
    private let storage: any TokenStorage
    private var tokens: StoredTokens?

    init(baseURL: URL, urlSession: URLSession = .shared, storage: any TokenStorage = KeychainTokenStorage()) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.storage = storage
    }

    var isSignedIn: Bool {
        tokens != nil
    }

    /// Поднимает сохранённые токены при старте приложения.
    func restore() {
        do {
            tokens = try storage.read()
            // Молча проглоченная ошибка Keychain выглядела бы как «человек не
            // входил» и заставляла вводить пароль при каждом запуске.
            NSLog("[auth] токены из хранилища: %@", tokens == nil ? "нет" : "есть")
        } catch {
            NSLog("[auth] хранилище недоступно: %@", String(describing: error))
        }
    }

    func accessToken() throws -> String {
        guard let access = tokens?.accessToken else { throw APIError.signedOut }
        return access
    }

    func signIn(username: String, password: String) async throws {
        let body = try JSONEncoder().encode(LoginRequest(username: username, password: password))
        let (data, response) = try await HTTP.send(
            urlSession: urlSession, baseURL: baseURL,
            path: "/api/auth/login", method: "POST", jsonBody: body
        )
        guard (200 ..< 300).contains(response.statusCode) else {
            // 401 с неверным паролем: показываем текст бэкенда, а не «сессия истекла».
            throw HTTP.apiError(data: data, response: response)
        }

        let responseTokens = try JSONDecoder().decode(AuthTokensResponse.self, from: data)
        try replaceTokens(responseTokens)
    }

    /// Новая пара токенов. После смены пароля сервер отдаёт её в ответе и
    /// рвёт старую: оставить старую в хранилище значит через 15 минут выкинуть
    /// человека на экран входа посреди работы.
    func replaceTokens(_ response: AuthTokensResponse) throws {
        guard let access = response.accessToken, let refresh = response.refreshToken else {
            throw APIError.server(code: nil, message: "Сервер не вернул токены для нативного приложения")
        }
        try store(StoredTokens(accessToken: access, refreshToken: refresh))
    }

    /// Чем закончилось обновление токена. Различать приходится, потому что
    /// обрыв сети и отказ сервера значат разное: при обрыве сессия жива, и
    /// стирать токены из-за моргнувшей сети нельзя.
    enum RefreshOutcome: Sendable, Equatable {
        /// Токен обновлён, запрос можно повторить.
        case refreshed
        /// Сети нет: сессия жива, но запрос не ушёл.
        case offline
        /// Сервер отказал: сессия кончилась, человеку нужен вход.
        case expired
    }

    /// Обновляет access-токен. Токены стираются только когда сессия правда
    /// кончилась: обрыв сети оставляет сессию живой, иначе человек в метро
    /// вылетал бы из приложения и вводил пароль заново.
    func refreshAccessToken() async -> RefreshOutcome {
        guard let current = tokens else { return .expired }
        do {
            let body = try JSONEncoder().encode(RefreshRequest(refreshToken: current.refreshToken))
            let (data, response) = try await HTTP.send(
                urlSession: urlSession, baseURL: baseURL,
                path: "/api/auth/refresh", method: "POST", jsonBody: body
            )
            guard (200 ..< 300).contains(response.statusCode) else {
                signOut()
                return .expired
            }

            let fresh = try JSONDecoder().decode(AuthRefreshResponse.self, from: data)
            try store(StoredTokens(
                accessToken: fresh.accessToken,
                refreshToken: fresh.refreshToken ?? current.refreshToken
            ))
            return .refreshed
        } catch {
            // Сети не было: refresh-токен жив ещё семь дней, и стирать его
            // из-за обрыва нельзя.
            if (error as? APIError)?.isTransport == true {
                return .offline
            }
            signOut()
            return .expired
        }
    }

    /// Локальный выход: стираем токены с устройства.
    ///
    /// `POST /api/auth/logout` намеренно не зовём: он завершает сессии
    /// пользователя на всех устройствах сразу, а «выйти» на телефоне не должен
    /// выбрасывать его с планшета. Запрос добавляем сюда, когда понадобится
    /// «выйти со всех устройств» отдельной кнопкой в настройках.
    func signOut() {
        try? storage.clear()
        tokens = nil
    }

    private func store(_ newTokens: StoredTokens) throws {
        try storage.write(newTokens)
        tokens = newTokens
    }
}
