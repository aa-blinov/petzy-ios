import Foundation
import Observation

/// Состояние экрана администратора. Знает про запросы и что после них
/// показать, но не знает про JSON: разбор лежит в `UsersAPI`.
@MainActor
@Observable
final class UsersModel {
    private(set) var users: [UserInfo] = []
    /// Сколько всего людей на сервере: список постраничный, и без этого числа
    /// не видно, что список кончился.
    private(set) var total = 0
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски.
    var errorText: String?
    /// Поиск по логину или имени. Пустой список обновляется сам.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            page = 1
        }
    }

    private(set) var page = 1
    /// Отложенный поиск: следующий ввод отменяет предыдущий.
    private var searchTask: Task<Void, Never>?

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await UsersAPI.list(client, page: page, query: query)
            users = result.users
            total = result.total
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Поиск не ждёт нажатия «найти»: он идёт сам, но не сразу, иначе на
    /// каждый введённый символ уходил бы запрос. Предыдущий поиск при этом
    /// отменяется, иначе все они проснутся одновременно и спросят сервер
    /// несколько раз подряд.
    func searchChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    @discardableResult
    func create(_ draft: UserDraft) async -> Bool {
        if let problem = UserDraft.problem(draft, isNew: true) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            _ = try await UsersAPI.create(client, draft: draft)
            // Без перечитывания в списке не было бы нового человека, и
            // администратор решил бы, что учётка не создалась.
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    func update(_ user: UserInfo, draft: UserDraft) async -> Bool {
        errorText = nil
        do {
            try await UsersAPI.update(client, username: user.username, draft: draft)
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    func resetPassword(for user: UserInfo?, to password: String) async -> Bool {
        guard let user else { return false }
        errorText = nil
        do {
            try await UsersAPI.resetPassword(client, username: user.username, to: password)
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Отключение необратимо для входа: человек перестаёт входить сразу.
    func disable(_ user: UserInfo?) async {
        guard let user else { return }
        errorText = nil
        do {
            try await UsersAPI.disable(client, username: user.username)
            await load()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
