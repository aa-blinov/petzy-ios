import Foundation

/// Авторизованные маршруты `/api/...`. Сам разбирается с истёкшим access-токеном:
/// на 401 один раз обновляет токен и повторяет запрос. Сам повтор не зациклится,
/// потому что второй ответ с 401 уже превращается в ошибку.
struct APIClient: Sendable {
    let baseURL: URL
    let urlSession: URLSession
    let auth: AuthSession

    /// `anonymous` — запрос без сессии: вход, регистрация, восстановление
    /// пароля и справка о политике идут до токенов, и заголовка
    /// `Authorization` у них быть не должно.
    func get<T: Decodable & Sendable>(
        _ path: String,
        as type: T.Type = T.self,
        anonymous: Bool = false
    ) async throws -> T {
        try await send(APIRequest(path: path, anonymous: anonymous), as: type)
    }

    /// Ответ как пришёл, без разбора. Им копируется раздел для работы без
    /// сети: сохранять проще то, что пришло, а разбирать потом тем же кодом,
    /// что и сеть, иначе копия и сеть разойдутся.
    func getRaw(_ path: String) async throws -> Data {
        try await raw(APIRequest(path: path)).0
    }

    func post<T: Decodable & Sendable>(
        _ path: String,
        body: some Encodable & Sendable,
        as type: T.Type = T.self,
        anonymous: Bool = false
    ) async throws -> T {
        let encoded = try JSONEncoder().encode(body)
        return try await send(APIRequest(path: path, method: "POST", body: encoded, anonymous: anonymous), as: type)
    }

    /// Запрос с телом, которое уже собрано: очередь офлайн-записей хранит
    /// тело как пришло и отправляет его теми же байтами. Разбирать ответ не
    /// нужно: после отправки раздел перечитывается с сервера.
    ///
    /// `contentType` нужен телу не JSON: у питомца это multipart с границей,
    /// и без заголовка сервер не поймёт, где кончается одна часть тела.
    func sendRaw(_ path: String, method: String = "POST", body: Data, contentType: String? = nil) async throws {
        let result = try await raw(APIRequest(path: path, method: method, body: body, contentType: contentType))
        guard (200 ..< 300).contains(result.1.statusCode) else {
            throw Self.failure(data: result.0, response: result.1)
        }
    }

    func put<T: Decodable & Sendable>(
        _ path: String,
        body: some Encodable & Sendable,
        as type: T.Type = T.self
    ) async throws -> T {
        let encoded = try JSONEncoder().encode(body)
        return try await send(APIRequest(path: path, method: "PUT", body: encoded), as: type)
    }

    /// Ответа может не быть вовсе: удалённая запись просто уходит.
    func delete(_ path: String) async throws {
        let result = try await raw(APIRequest(path: path, method: "DELETE"))
        guard (200 ..< 300).contains(result.1.statusCode) else {
            throw Self.failure(data: result.0, response: result.1)
        }
    }

    /// Удаление, у которого ответ важен: сервер сначала считает, сколько
    /// записей исчезнет вместе с типом, и отдаёт это число в теле.
    func delete<T: Decodable & Sendable>(
        _ path: String,
        as type: T.Type = T.self
    ) async throws -> T {
        try await send(APIRequest(path: path, method: "DELETE"), as: type)
    }

    /// Удаление с телом. Так удаляется аккаунт: пароль подтверждения идёт в
    /// теле запроса, а без него сервер откажет.
    func delete<T: Decodable & Sendable>(
        _ path: String,
        body: some Encodable & Sendable,
        as type: T.Type = T.self
    ) async throws -> T {
        let encoded = try JSONEncoder().encode(body)
        return try await send(APIRequest(path: path, method: "DELETE", body: encoded), as: type)
    }

    /// Загрузка файла: тело не JSON, а multipart с полями и файлом.
    func postMultipart<T: Decodable & Sendable>(
        _ path: String,
        body: Data,
        contentType: String?,
        as type: T.Type = T.self
    ) async throws -> T {
        try await sendMultipart(APIRequest(path: path, method: "POST"), body: body, contentType: contentType, as: type)
    }

    /// То же для правки: карточка питомца едет файлом в PUT.
    func putMultipart<T: Decodable & Sendable>(
        _ path: String,
        body: Data,
        contentType: String?,
        as type: T.Type = T.self
    ) async throws -> T {
        try await sendMultipart(APIRequest(path: path, method: "PUT"), body: body, contentType: contentType, as: type)
    }

    /// Файл целиком, а не разобранный ответ: выгрузка отдаёт CSV, и разбирать
    /// его нечем. Вместе с телом отдаётся имя файла из заголовка сервера,
    /// иначе в «Поделиться» ушёл бы `записи.csv` вместо «рекс_вес_…».
    func download(_ path: String) async throws -> (data: Data, fileName: String?) {
        let result = try await raw(APIRequest(path: path))
        guard (200 ..< 300).contains(result.1.statusCode) else {
            throw Self.failure(data: result.0, response: result.1)
        }
        return (result.0, Self.fileName(from: result.1))
    }

    /// `Content-Disposition: attachment; filename*=UTF-8''рекс_вес.csv`.
    /// Без `filename*` сервер может прислать только `filename="..."` с
    /// ASCII-именем, и тогда берём его.
    static func fileName(from response: HTTPURLResponse) -> String? {
        guard let value = response.value(forHTTPHeaderField: "Content-Disposition") else { return nil }
        // Условие в одну строку: многострочный `if let` swiftformat раскрывает
        // скобкой на новой строке, а swiftlint это запрещает.
        let parts = value.components(separatedBy: "UTF-8''")
        if parts.count > 1, let name = parts[1].removingPercentEncoding, !name.isEmpty {
            return name
        }
        guard let quoted = value.components(separatedBy: "filename=").dropFirst().first else {
            return nil
        }
        return quoted.trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
    }

    private struct APIRequest: Sendable {
        var path: String
        var method = "GET"
        var body: Data?
        /// Заголовок `Content-Type` тела, когда оно не JSON.
        var contentType: String?
        /// Запрос без сессии: токен не подставляется и обновляться нечему.
        var anonymous = false
    }

    /// Запрос с одной попыткой обновить истёкший access-токен и повторить.
    private func raw(_ request: APIRequest) async throws -> (Data, HTTPURLResponse) {
        if request.anonymous {
            return try await perform(request, token: nil)
        }
        let first = try await perform(request, token: auth.accessToken())
        guard first.1.statusCode == 401 else { return first }
        switch await auth.refreshAccessToken() {
        case .refreshed:
            return try await perform(request, token: auth.accessToken())
        case .offline:
            // Сети нет: сессия жива, но запрос не ушёл. Пусть это будет обрыв
            // связи: без связи приложение показывает сохранённые данные, а с
            // отказом выбрасывает человека на экран входа.
            throw APIError.transport("нет связи")
        case .expired:
            return first
        }
    }

    private func send<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type) async throws -> T {
        try await Self.decode(raw(request), as: type)
    }

    /// Загрузка файла повторяется после обновления токена так же, как и
    /// остальные запросы: тело уже собрано, пересобирать его не нужно.
    private func sendMultipart<T: Decodable & Sendable>(
        _ request: APIRequest,
        body: Data,
        contentType: String?,
        as type: T.Type
    ) async throws -> T {
        let first = try await performMultipart(request, body: body, contentType: contentType, token: auth.accessToken())
        guard first.1.statusCode == 401 else {
            return try Self.decode(first, as: type)
        }
        switch await auth.refreshAccessToken() {
        case .refreshed:
            return try await Self.decode(
                performMultipart(request, body: body, contentType: contentType, token: auth.accessToken()),
                as: type
            )
        case .offline:
            throw APIError.transport("нет связи")
        case .expired:
            return try Self.decode(first, as: type)
        }
    }

    private func perform(_ request: APIRequest, token: String?) async throws -> (Data, HTTPURLResponse) {
        // Тело не JSON уезжает multipart'ом: у него своя граница в заголовке,
        // и сервер без неё тело не разберёт.
        if let contentType = request.contentType {
            return try await HTTP.sendMultipart(
                urlSession: urlSession, baseURL: baseURL, path: request.path,
                method: request.method, body: request.body ?? Data(), contentType: contentType, accessToken: token
            )
        }
        return try await HTTP.send(
            urlSession: urlSession, baseURL: baseURL, path: request.path,
            method: request.method, jsonBody: request.body, accessToken: token
        )
    }

    private func performMultipart(
        _ request: APIRequest,
        body: Data,
        contentType: String?,
        token: String
    ) async throws -> (Data, HTTPURLResponse) {
        try await HTTP.sendMultipart(
            urlSession: urlSession, baseURL: baseURL, path: request.path,
            method: request.method, body: body, contentType: contentType, accessToken: token
        )
    }

    /// Ошибка по ответу сервера. Отказ 401 — это конец сессии, и его надо
    /// отличить от обычной ошибки: иначе приложение остаётся внутри с текстом
    /// «Сессия закончилась», и человек думает, что действие не сработало.
    private static func failure(data: Data, response: HTTPURLResponse) -> APIError {
        if response.statusCode == 401 {
            return .unauthorized
        }
        return HTTP.apiError(data: data, response: response)
    }

    private static func decode<T: Decodable>(
        _ result: (Data, HTTPURLResponse),
        as _: T.Type
    ) throws -> T {
        guard (200 ..< 300).contains(result.1.statusCode) else {
            // 401 здесь уже после попытки обновиться: сессии нет, нужен вход.
            if result.1.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw HTTP.apiError(data: result.0, response: result.1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: result.0)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
