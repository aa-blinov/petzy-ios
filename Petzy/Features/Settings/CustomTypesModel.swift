import Foundation
import Observation

/// Состояние экрана «Свои типы записей». Знает про запросы и что после них
/// показать, но не знает про JSON: разбор лежит в `EventTypesAPI`.
@MainActor
@Observable
final class CustomTypesModel {
    /// Свои типы. Встроенные в правку не пускаются, а на этом экране они и
    /// не нужны: их и так видно под кнопкой «+».
    private(set) var types: [EventTypeInfo] = []
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски.
    var errorText: String?
    /// Тип, который человек согласился удалить, и сколько записей пропадёт
    /// вместе с ним. `nil` — вопрос ещё не задан.
    private(set) var pendingDelete: EventTypeInfo?
    private(set) var pendingCount: Int?
    /// Ключ удаляемого типа живёт отдельно от `pendingDelete`: диалог закрывается
    /// раньше, чем срабатывает его кнопка, и вместе с ним стирается всё, что
    /// показывалось в диалоге. Ключ перезаписывается каждым `prepareDelete`
    /// и сгорает в `deletePending`, поэтому stale-значением он быть не может.
    private var deletingKey: String?

    /// Удалять можно только пустой тип: у типа с записями сервер отвечает
    /// отказом, и обещать человеку удаление нельзя.
    var canDelete: Bool {
        pendingCount == 0
    }

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog: EventTypesResponse = try await client.get("/api/event-types")
            types = catalog.eventTypes.filter { $0.category == nil }
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Ключ есть у правки, его нет у нового типа: по нему и решается, что
    /// отправлять, `POST` или `PUT`.
    @discardableResult
    func save(_ draft: CustomTypeDraft) async -> Bool {
        if let problem = CustomTypeDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            if let key = draft.key {
                _ = try await EventTypesAPI.update(client, key: key, draft: draft)
            } else {
                _ = try await EventTypesAPI.create(client, draft: draft)
            }
            // Без перечитывания в списке не было бы нового типа, и человек
            // решил бы, что он не создался.
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Записи удаляются вместе с типом жёстко, поэтому сначала спрашиваем их
    /// число: человек должен увидеть, сколько пропадёт, до нажатия «Удалить».
    func prepareDelete(_ type: EventTypeInfo?) async {
        guard let type else { return }
        errorText = nil
        do {
            pendingCount = try await EventTypesAPI.countBeforeDelete(client, key: type.key)
            deletingKey = type.key
            pendingDelete = type
        } catch {
            errorText = Self.text(of: error)
        }
    }

    func cancelDelete() {
        pendingDelete = nil
        pendingCount = nil
    }

    func deletePending() async {
        guard let key = deletingKey else { return }
        deletingKey = nil
        do {
            try await EventTypesAPI.delete(client, key: key)
            // Убираем строку сами, а не перечитываем справочник: пока у неё
            // открыто свайп-действие, вторая перерисовка списка роняет
            // приложение внутри UIKit.
            types.removeAll { $0.key == key }
        } catch {
            errorText = Self.text(of: error)
        }
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
