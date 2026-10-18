import Foundation

/// Авторизованные маршруты `/api/...`. Сам разбирается с истёкшим access-токеном:
/// на 401 один раз обновляет токен и повторяет запрос. Сам повтор не зациклится,
/// потому что второй ответ с 401 уже превращается в ошибку.
struct APIClient: Sendable {
    let baseURL: URL
    let urlSession: URLSession
    let auth: AuthSession

    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try await send(APIRequest(path: path), as: type)
    }

    func post<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ path: String,
        body: Body,
        as type: T.Type = T.self
    ) async throws -> T {
        let encoded = try JSONEncoder().encode(body)
        return try await send(APIRequest(path: path, method: "POST", body: encoded), as: type)
    }

    private struct APIRequest: Sendable {
        var path: String
        var method = "GET"
        var body: Data?
    }

    private func send<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type) async throws -> T {
        let first = try await perform(request, token: try await auth.accessToken())
        if first.1.statusCode == 401, await auth.refreshAccessToken() {
            let second = try await perform(request, token: try await auth.accessToken())
            return try Self.decode(second, as: type)
        }
        return try Self.decode(first, as: type)
    }

    private func perform(_ request: APIRequest, token: String) async throws -> (Data, HTTPURLResponse) {
        try await HTTP.send(
            urlSession: urlSession, baseURL: baseURL, path: request.path,
            method: request.method, jsonBody: request.body, accessToken: token
        )
    }

    private static func decode<T: Decodable>(
        _ result: (Data, HTTPURLResponse),
        as type: T.Type
    ) throws -> T {
        guard (200..<300).contains(result.1.statusCode) else {
            // 401 здесь уже после попытки обновиться: сессии нет, нужен вход.
            if result.1.statusCode == 401 { throw APIError.unauthorized }
            throw HTTP.apiError(data: result.0, response: result.1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: result.0)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
