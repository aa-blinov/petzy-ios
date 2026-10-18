import Foundation
@testable import Petzy
import Testing

@Suite("Вход и обновление токена")
struct AuthSessionTests {
    private let baseURL = URL(string: "http://localhost:5002")!

    private func makeSession(storage: any TokenStorage) -> AuthSession {
        let session = StubURLProtocol.makeSession()
        return AuthSession(baseURL: baseURL, urlSession: session, storage: storage)
    }

    @Test("Вход сохраняет оба токена")
    func signInStoresTokens() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "message": "Вы вошли",
            "access_token": "access-1",
            "refresh_token": "refresh-1"
        ])
        let storage = InMemoryTokenStorage()
        let auth = makeSession(storage: storage)

        try await auth.signIn(username: "demo", password: "secret")

        let signedIn = await auth.isSignedIn
        #expect(signedIn)
        #expect(try storage.read() == StoredTokens(accessToken: "access-1", refreshToken: "refresh-1"))
        #expect(StubURLProtocol.requestedPaths == ["/api/auth/login"])
        // Нативный клиент не шлёт Origin: иначе бэкенд ответит куками, а не токенами.
        #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Origin") == nil)
    }

    @Test("Обновление заменяет refresh-токен на новый")
    func refreshRotatesRefreshToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "access_token": "access-2",
            "refresh_token": "refresh-2"
        ])
        let storage = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = makeSession(storage: storage)
        await auth.restore()

        let refreshed = await auth.refreshAccessToken()
        #expect(refreshed)
        #expect(try storage.read() == StoredTokens(accessToken: "access-2", refreshToken: "refresh-2"))
        #expect(StubURLProtocol.requestedPaths == ["/api/auth/refresh"])
    }

    @Test("Бэкенд не прислал новый refresh: старый остаётся в силе")
    func refreshKeepsOldTokenWhenNoneReturned() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["access_token": "access-2"])
        let storage = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = makeSession(storage: storage)
        await auth.restore()

        let refreshed = await auth.refreshAccessToken()
        #expect(refreshed)
        #expect(try storage.read() == StoredTokens(accessToken: "access-2", refreshToken: "refresh-1"))
    }

    @Test("Отказ в обновлении стирает токены")
    func failedRefreshClearsTokens() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "refresh-токен недействителен"])
        let storage = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "stolen")
        )
        let auth = makeSession(storage: storage)
        await auth.restore()

        let refreshed = await auth.refreshAccessToken()
        let signedIn = await auth.isSignedIn
        #expect(refreshed == false)
        #expect(signedIn == false)
        #expect(try storage.read() == nil)
    }

    @Test("Неверный пароль показывает текст бэкенда, а не «сессия истекла»")
    func wrongPasswordSurfacesServerMessage() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: [
            "code": "unauthorized_invalid_credentials",
            "error": "Неверный логин или пароль",
            "success": false
        ])
        let auth = makeSession(storage: InMemoryTokenStorage())

        do {
            try await auth.signIn(username: "demo", password: "wrong")
            Issue.record("ожидалась ошибка входа")
        } catch let error as APIError {
            #expect(error.errorDescription == "Неверный логин или пароль")
            #expect(error.isAuthProblem == false, "Ошибка входа это не потеря сессии")
        }
        let signedIn = await auth.isSignedIn
        #expect(signedIn == false)
    }

    @Test("Выход стирает токены только на устройстве")
    func signOutIsLocalOnly() async throws {
        StubURLProtocol.reset()
        let storage = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = makeSession(storage: storage)
        await auth.restore()

        await auth.signOut()

        #expect(try storage.read() == nil)
        #expect(StubURLProtocol.requestedPaths.isEmpty, "Серверный logout выбивает все устройства, его не зовём")
    }
}
