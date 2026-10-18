import Foundation
import Observation

/// Состояние экрана «Доступы для ассистентов». Знает про запросы и что после
/// них показать, но не знает про JSON: разбор лежит в `TokensAPI`.
@MainActor
@Observable
final class AccessTokensModel {
    private(set) var tokens: [AccessToken] = []
    private(set) var isLoading = false
    /// Секрет нового доступа. Сервер отдаёт его один раз, поэтому он живёт
    /// здесь, пока человек его не забрал или не закрыл.
    private(set) var secret: String?
    /// Что ответил сервер, по-русски.
    var errorText: String?
    var draft = AccessTokenDraft()

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tokens = try await TokensAPI.list(client)
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    @discardableResult
    func create() async -> Bool {
        if let problem = AccessTokenDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            let created = try await TokensAPI.create(
                client,
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                scopes: draft.scopeKeys,
                days: draft.days
            )
            secret = created.secret
            draft = AccessTokenDraft()
            // Без перечитывания в списке не было бы нового доступа, а человек
            // решил бы, что он не создался.
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Отзыв необратим: сервер хранит только хэш, вернуть токен нельзя.
    func revoke(id: String) async {
        errorText = nil
        do {
            try await TokensAPI.revoke(client, id: id)
            await load()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    func forgetSecret() {
        secret = nil
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
