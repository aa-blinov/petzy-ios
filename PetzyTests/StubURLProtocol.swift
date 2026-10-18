import Foundation
@testable import Petzy

/// Отдаёт заранее заданные ответы по очереди: так проверяются вход и обновление
/// токена без настоящего бэкенда. Последний ответ не повторяется, лишний запрос
/// получает 500, и тест это видно.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let body: Data
    }

    nonisolated(unsafe) static var stubs: [Stub] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        stubs = []
        requests = []
        headerFields = [:]
    }

    static func stub(status: Int, json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        stubs.append(Stub(statusCode: status, body: data))
    }

    /// Ответ с телом как есть и своими заголовками: выгрузка приходит не
    /// JSON, а файлом, и имя файла лежит в заголовке.
    static func stub(status: Int, data: Data, headers: [String: String]) {
        headerFields = headers
        stubs.append(Stub(statusCode: status, body: data))
    }

    private nonisolated(unsafe) static var headerFields: [String: String] = [:]

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Пути запросов по порядку: по ним видно, что клиент сначала получил 401,
    /// потом обновил токен и только затем повторил исходный запрос.
    static var requestedPaths: [String] {
        requests.compactMap { $0.url?.path }
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        // Лишний запрос получает 500, и это видно в тесте. Брать заглушку из
        // пустого списка нельзя: `removeFirst` на пустом массиве роняет весь
        // прогон, и падение выглядит как «тесты не запускаются», а не как
        // «тест запросил лишнее».
        guard !Self.stubs.isEmpty else {
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 500,
                                                 httpVersion: "HTTP/1.1", headerFields: nil)
            else {
                client?.urlProtocol(self, didFailWithError: APIError.transport("стаб не собрал ответ"))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let stub = Self.stubs.removeFirst()

        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.statusCode,
                                             httpVersion: "HTTP/1.1", headerFields: Self.headerFields)
        else {
            client?.urlProtocol(self, didFailWithError: APIError.transport("стаб не собрал ответ"))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
