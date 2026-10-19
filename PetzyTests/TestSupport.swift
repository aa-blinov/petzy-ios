import Foundation
@testable import Petzy
import Testing

/// Общие заготовки для тестов модели. Вынесены отдельно, потому что и
/// оболочка, и история собирают модель одинаково, а держать это в двух
/// местах значит через месяц забыть про одно из них.
enum TestSupport {
    /// Настройки с отдельным именем, чтобы тест не затирал то, что на симуляторе.
    /// Файл копии на одноразовом пути: тесты не должны делить одну копию.
    static func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("petzy-store-\(UUID().uuidString).json")
    }

    static func makeDefaults() -> UserDefaults {
        let suite = "TestSupport.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        return UserDefaults(suiteName: suite)!
    }

    /// Модель с залогиненной сессией. Без токенов APIClient отвечает
    /// `.signedOut` и в сеть не ходит вовсе: тест проходил бы, ни разу не
    /// проверив запрос.
    @MainActor
    static func makeModel(defaults: UserDefaults, store: LocalStore = LocalStore(
        url: FileManager.default.temporaryDirectory.appendingPathComponent("petzy-test-\(UUID().uuidString).json")
    )) async -> AppModel {
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let auth = AuthSession(
            baseURL: URL(string: "http://localhost:5002")!,
            urlSession: session,
            storage: InMemoryTokenStorage(
                tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
            )
        )
        await auth.restore()
        // Тот же заглушечный сеанс отдаём и клиенту: иначе запросы уйдут
        // в настоящий стенд, а тест будет зелёным, не проверив ничего.
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        return AppModel(auth: auth, baseURL: baseURL, urlSession: session, defaults: defaults, store: store)
    }

    /// Справочник типов из одного типа записи: истории хватает его, чтобы
    /// показать названия и вид графика.
    static func stubTypeReference() {
        StubURLProtocol.stub(status: 200, json: ["event_types": [
            ["key": "weight", "label": "Вес", "icon": "scale", "fields": [
                [
                    "name": "weight", "label": "Вес (кг)", "type": "number",
                    "required": true, "min": 0.0, "max": 100.0, "options": nil
                ]
            ], "chart": ["kind": "value", "value_field": "weight", "value_label": "Вес (кг)"]]
        ]])
    }

    /// Тело запроса. `URLSession` отдаёт `URLProtocol` не `httpBody`, а поток,
    /// поэтому читать приходится из обоих: иначе тело выглядит пустым, хотя
    /// запрос ушёл вовсе с данными.
    static func body(of request: URLRequest?) -> [String: Any] {
        guard let data = bodyData(of: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    /// Тело запроса как есть, без разбора: multipart'ом уходит файл, и
    /// JSON-разбор тут ни при чём.
    static func rawBody(of request: URLRequest?) -> Data {
        bodyData(of: request) ?? Data()
    }

    private static func bodyData(of request: URLRequest?) -> Data? {
        if let body = request?.httpBody {
            return body
        }
        guard let stream = request?.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
