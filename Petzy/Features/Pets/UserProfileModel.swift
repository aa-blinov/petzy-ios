import Foundation
import Observation

/// Состояние страницы другого человека. Знает про запрос, но не про JSON и не
/// про вид: экран рисует то, что здесь.
@MainActor
@Observable
final class UserProfileModel {
    private(set) var profile: UserProfile?
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски.
    var errorText: String?

    private let client: APIClient
    private let username: String

    init(client: APIClient, username: String) {
        self.client = client
        self.username = username
    }

    /// Заголовок экрана: логин, пока имени нет.
    var title: String {
        profile?.title ?? username
    }

    func load() async {
        // Профиль читается один раз: экран не перечитывают, а вход в него
        // ничего не меняет.
        guard profile == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await UsersAPI.profile(client, username: username)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
