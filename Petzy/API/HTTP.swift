import Foundation

/// Тонкая обёртка над URLSession: собирает запрос к `/api/...`.
/// Общая для клиента и для входа, чтобы правила подписи и заголовков жили в одном месте.
enum HTTP {
    /// Тело ошибки от бэкенда: `{"code": ..., "error": ..., "success": false}`.
    struct ErrorBody: Decodable, Sendable {
        let code: String?
        let error: String
    }

    /// - Parameter accessToken: подставляется как `Authorization: Bearer`, если задан.
    @discardableResult
    static func send(
        urlSession: URLSession,
        baseURL: URL,
        path: String,
        method: String = "GET",
        jsonBody: Data? = nil,
        accessToken: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: Self.resolve(path, baseURL: baseURL))
        request.httpMethod = method
        request.httpBody = jsonBody
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Заголовка Origin тут нет: так бэкенд отличает нативный клиент от браузера
        // и отдаёт токены в теле ответа, а не httpOnly-кукой.
        if jsonBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("ответ не от HTTP")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    /// Собирает адрес из `путь?параметры`. `appending(path:)` считает всю строку
    /// частью пути и прячет в неё знак вопроса, поэтому параметры уезжают в путь
    /// и сервер их не видит. Делим сами: путь и запрос — разные части адреса.
    static func resolve(_ path: String, baseURL: URL) -> URL {
        guard let questionMark = path.firstIndex(of: "?") else {
            return baseURL.appending(path: path)
        }
        let withoutQuery = String(path[path.startIndex ..< questionMark])
        let query = String(path[path.index(after: questionMark)...])
        let url = baseURL.appending(path: withoutQuery)
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        // Значения в запросе приходят уже экранированными, поэтому это именно
        // percentEncodedQuery: второй раз экранировать нельзя.
        components.percentEncodedQuery = query
        return components.url ?? url
    }

    /// Текст ошибки от бэкенда, если он есть: «Неверный логин или пароль» полезнее,
    /// чем наш общий текст про статус.
    static func apiError(data: Data, response: HTTPURLResponse) -> APIError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        if let message = body?.error, !message.isEmpty {
            return .server(code: body?.code, message: message)
        }
        return .server(code: nil, message: "Ошибка сервера (\(response.statusCode))")
    }
}
