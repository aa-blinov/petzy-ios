import Foundation
@testable import Petzy
import Testing

@Suite("Запросы к API")
struct APIClientTests {
    private let baseURL = URL(string: "http://localhost:5002")!

    /// Сессию надо поднять из хранилища, как это делает приложение при старте:
    /// без `restore()` в `AuthSession` токенов нет и любой запрос падает с `.signedOut`.
    private func makeClient(storage: any TokenStorage) async -> APIClient {
        let session = StubURLProtocol.makeSession()
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: storage)
        await auth.restore()
        return APIClient(baseURL: baseURL, urlSession: session, auth: auth)
    }

    private func signedInStorage() -> InMemoryTokenStorage {
        InMemoryTokenStorage(tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1"))
    }

    @Test("Список питомцев читается и `_id` становится id")
    func readsPets() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "pets": [
                [
                    "_id": "6ac0b44fc775325d197b84df",
                    "name": "Рекс",
                    "species": "dog",
                    "breed": "Лабрадор",
                    "birth_date": "2021-08-01",
                    "gender": "male"
                ]
            ]
        ])
        let client = await makeClient(storage: signedInStorage())

        let response = try await client.get("/api/pets", as: PetsResponse.self)

        #expect(response.pets.count == 1)
        #expect(response.pets[0].id == "6ac0b44fc775325d197b84df")
        #expect(response.pets[0].name == "Рекс")
        #expect(PetSpecies.label(for: response.pets[0].species) == "Собака")
        #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
            == "Bearer access-1")
    }

    @Test("Истёкший access: сначала обновление, потом повтор того же запроса")
    func refreshesThenRetriesOnce() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        StubURLProtocol.stub(status: 200, json: [
            "access_token": "access-2",
            "refresh_token": "refresh-2"
        ])
        StubURLProtocol.stub(status: 200, json: [
            "pets": [["_id": "1", "name": "Рекс"]]
        ])
        let storage = signedInStorage()
        let client = await makeClient(storage: storage)

        let response = try await client.get("/api/pets", as: PetsResponse.self)

        #expect(response.pets.map(\.name) == ["Рекс"])
        #expect(StubURLProtocol.requestedPaths == ["/api/pets", "/api/auth/refresh", "/api/pets"])
        #expect(try storage.read() == StoredTokens(accessToken: "access-2", refreshToken: "refresh-2"))
    }

    @Test("Обновление не удалось: запрос не повторяется, сессия закрыта")
    func stopsAfterOneRetry() async throws {
        StubURLProtocol.reset()
        for _ in 0 ..< 4 {
            StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        }
        let storage = signedInStorage()
        let client = await makeClient(storage: storage)

        await #expect(throws: APIError.unauthorized) {
            _ = try await client.get("/api/pets", as: PetsResponse.self)
        }

        // Обновление вернуло 401, поэтому повторного запроса нет: повторять его
        // с заведомо мёртвым токеном бессмысленно. Ровно два запроса, не больше:
        // это и есть защита от бесконечного цикла.
        #expect(StubURLProtocol.requestedPaths == ["/api/pets", "/api/auth/refresh"])
        // Сессия снесена, чтобы приложение показало вход, а не повторяло попытки.
        #expect(try storage.read() == nil)
    }

    @Test("Успешное обновление с 401 на повторе уходит ровно один раз")
    func retriesOnlyOnceWhenRefreshSucceeds() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        StubURLProtocol.stub(status: 200, json: [
            "access_token": "access-2",
            "refresh_token": "refresh-2"
        ])
        // Повтор тоже отвечает 401: второй попытки обновить токен уже не будет.
        for _ in 0 ..< 3 {
            StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        }
        let client = await makeClient(storage: signedInStorage())

        await #expect(throws: APIError.unauthorized) {
            _ = try await client.get("/api/pets", as: PetsResponse.self)
        }

        // Один исходный запрос, одно обновление, один повтор. И всё.
        #expect(StubURLProtocol.requestedPaths == ["/api/pets", "/api/auth/refresh", "/api/pets"])
    }

    @Test("Ошибка бэкенда доходит со своим кодом и текстом")
    func serverErrorKeepsCode() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 429, json: [
            "code": "rate_limit_exceeded",
            "error": "Слишком много запросов",
            "success": false
        ])
        let client = await makeClient(storage: signedInStorage())

        do {
            _ = try await client.get("/api/pets", as: PetsResponse.self)
            Issue.record("ожидалась ошибка сервера")
        } catch let error as APIError {
            #expect(error.errorDescription == "Слишком много запросов")
            guard case let .server(code, _) = error else {
                Issue.record("ожидалась .server, получено \(error)")
                return
            }
            #expect(code == "rate_limit_exceeded")
            #expect(error.isAuthProblem == false)
        }
    }

    /// Сети нет в момент обновления: сессия жива, и запрос падает как обрыв
    /// связи. Без этого человек вылетал бы из приложения из-за плохой сети и
    /// вводил бы пароль заново.
    @Test("Обрыв сети при обновлении токена не закрывает сессию")
    func offlineRefreshKeepsSessionAlive() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        StubURLProtocol.stubOffline()
        let storage = signedInStorage()
        let client = await makeClient(storage: storage)

        do {
            _ = try await client.get("/api/pets", as: PetsResponse.self)
            Issue.record("ожидался обрыв связи")
        } catch let error as APIError {
            #expect(error.isTransport, "обрыв связи должен выглядеть как обрыв, а не как отказ: \(error)")
            #expect(error.isAuthProblem == false, "обрыв связи не должен выкидывать человека из приложения")
        }
        #expect(try storage.read() != nil, "токены стёрты, а сеть просто моргнула")
    }

    /// Отказ 401 на маршруте, где ответ не разбирается, означает то же, что и
    /// на остальных: сессия кончилась. Раньше такие маршруты отдавали обычную
    /// ошибку сервера, приложение оставалось внутри с текстом «Сессия
    /// закончилась», и человек думал, что действие не сработало.
    @Test("401 при удалении выкидывает на экран входа")
    func unauthorizedOnDelete() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        StubURLProtocol.stub(status: 401, json: ["error": "refresh-токен недействителен"])
        let client = await makeClient(storage: signedInStorage())

        await #expect(throws: APIError.unauthorized) {
            try await client.delete("/api/events/e-1")
        }
    }

    @Test("401 при выгрузке выкидывает на экран входа")
    func unauthorizedOnDownload() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        StubURLProtocol.stub(status: 401, json: ["error": "refresh-токен недействителен"])
        let client = await makeClient(storage: signedInStorage())

        await #expect(throws: APIError.unauthorized) {
            try await client.download("/api/export/all/csv?pet_id=p1")
        }
    }

    @Test("401 в очереди офлайн-записей выкидывает на экран входа")
    func unauthorizedOnRawSend() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Нет токена или он истёк"])
        StubURLProtocol.stub(status: 401, json: ["error": "refresh-токен недействителен"])
        let client = await makeClient(storage: signedInStorage())

        await #expect(throws: APIError.unauthorized) {
            try await client.sendRaw("/api/events", method: "POST", body: Data("{}".utf8))
        }
    }

    @Test("Без входа клиент не ходит в сеть")
    func refusesRequestWithoutTokens() async throws {
        StubURLProtocol.reset()
        let client = await makeClient(storage: InMemoryTokenStorage())

        await #expect(throws: APIError.signedOut) {
            _ = try await client.get("/api/pets", as: PetsResponse.self)
        }

        #expect(StubURLProtocol.requestedPaths.isEmpty)
    }
}
