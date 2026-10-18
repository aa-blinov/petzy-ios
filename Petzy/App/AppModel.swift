import Foundation
import Observation

/// Состояние входа на уровне приложения.
@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn
    }

    private(set) var state: State = .restoring
    private(set) var isSigningIn = false
    var errorText: String?

    let client: APIClient
    private let auth: AuthSession

    init(auth: AuthSession) {
        self.auth = auth
        client = APIClient(baseURL: AppConfig.baseURL, urlSession: AppConfig.urlSession, auth: auth)
    }

    func start() async {
        // Прогон UI-теста начинает с чистого листа: Keychain от прошлого раза
        // иначе уводит с экрана входа, и проверять вход нечем.
        if ProcessInfo.processInfo.arguments.contains("-uiTestSignedOut") {
            await auth.signOut()
        }
        await auth.restore()
        state = await auth.isSignedIn ? .signedIn : .signedOut
    }

    func signIn(username: String, password: String) async {
        isSigningIn = true
        errorText = nil
        defer { isSigningIn = false }

        do {
            try await auth.signIn(username: username, password: password)
            state = .signedIn
        } catch {
            // Неверный пароль приходит 401, но текст здесь серверный:
            // «Неверный логин или пароль», а не «сессия закончилась».
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
            state = .signedOut
        }
    }

    func signOut() {
        Task { await auth.signOut() }
        errorText = nil
        state = .signedOut
    }
}
