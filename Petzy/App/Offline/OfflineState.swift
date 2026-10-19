import Foundation
import Observation

/// Офлайн-состояние приложения: копия, очередь записей и признак «на экране
/// копия, а не сеть». Отдельным объектом, а не свойствами `AppModel`, потому
/// что у него своя жизнь и своё хранилище, а `AppModel` и без того влезает в
/// лимит файла.
@MainActor
@Observable
final class OfflineState {
    /// На экране копия, а не свежая лента. Человек должен понимать, что видит
    /// не всё и что записи сейчас не доходят.
    /// Пишется из `AppModel+Feed.swift`, поэтому без `private(set)`.
    var isShowingCached = false
    /// Имена записей, которые ещё не ушли на сервер.
    private(set) var pendingIDs: Set<String> = []

    /// Копия целиком. Держим в памяти: запись в ленте идёт пачками, а файл один.
    private(set) var snapshot: OfflineSnapshot
    /// Момент последней синхронизации с сервером: с него спрашивается
    /// `GET /api/sync`.
    private(set) var syncAt: String?

    private let store: LocalStore

    init(store: LocalStore) {
        self.store = store
        snapshot = store.load()
        syncAt = snapshot.syncAt
        pendingIDs = Set(snapshot.queue.map(\.localID))
    }

    var pendingCount: Int {
        snapshot.queue.count
    }

    /// Копия записей питомца. `nil` — копии нет, и показывать нечего.
    func cachedEvents(petID: String) -> [PetEvent]? {
        let events = snapshot.events[petID] ?? []
        return events.isEmpty ? nil : events
    }

    /// Копия после успешной загрузки. Без неё следующий запуск без сети
    /// показал бы пустую ленту, хотя человек её только что читал.
    func cache(events: [PetEvent], types: [String: EventTypeInfo], pets: [Pet], petID: String) {
        snapshot.events[petID] = events
        snapshot.eventTypes = types
        snapshot.pets = pets
        snapshot.syncAt = syncAt
        store.save(snapshot)
    }

    /// Ставит запись в очередь и отдаёт её для показа. Имя, которым устройство
    /// её назвало, делает отправку повторяемой: сервер на повтор ответит той же
    /// записью, а не создаст вторую.
    @discardableResult
    func enqueue(_ draft: EventDraft, petID: String) -> PetEvent {
        let pending = PendingWrite(
            localID: "local-" + UUID().uuidString,
            petID: petID,
            body: PendingBody(
                date: draft.date,
                time: draft.time,
                zone: TimeZone.current.identifier,
                type: draft.type.key,
                comment: draft.comment,
                fields: draft.encodedFields
            )
        )
        snapshot.queue.append(pending)
        store.save(snapshot)
        pendingIDs.insert(pending.localID)
        return Self.event(from: pending)
    }

    /// Записи очереди выбранного питомца, готовые к показу.
    func pendingEvents(petID: String) -> [PetEvent] {
        snapshot.queue.filter { $0.petID == petID }.map(Self.event(from:))
    }

    func removePending(_ localID: String) {
        snapshot.queue.removeAll { $0.localID == localID }
        store.save(snapshot)
        pendingIDs.remove(localID)
    }

    /// Отправляет очередь. Останавливается на первой неудаче: следующая запись
    /// может зависеть от предыдущей, и человек должен видеть, сколько ещё ждать.
    func flush(using client: APIClient) async {
        while let pending = snapshot.queue.first {
            do {
                let body = EventRequest(
                    petID: pending.petID,
                    date: pending.body.date,
                    time: pending.body.time,
                    comment: pending.body.comment,
                    fields: pending.body.fields,
                    type: pending.body.type,
                    timeZone: pending.body.zone,
                    localID: pending.localID
                )
                _ = try await client.post("/api/events", body: body, as: EventSavedResponse.self)
                removePending(pending.localID)
            } catch {
                // Запись на сервере уже удалили. Повторять её незачем: она вернёт
                // тот же отказ, и человек так и не увидит, что она исчезла.
                guard droppedByServer(error) else { return }
                removePending(pending.localID)
            }
        }
    }

    /// Сервер сказал, что записи больше нет. Ответы означают одно и то же: её
    /// нельзя ни отправить, ни показать.
    private func droppedByServer(_ error: Error) -> Bool {
        let code = (error as? APIError)?.code
        return code == "record_deleted" || code == "not_found" || code == "record_not_found"
    }

    /// Запись очереди в виде строки ленты. Время без пояса: человек вводил его
    /// на своих часах, а выдуманное смещение сдвинуло бы его в ленте.
    private static func event(from pending: PendingWrite) -> PetEvent {
        PetEvent(
            id: pending.localID,
            type: pending.body.type,
            dateTime: "\(pending.body.date) \(pending.body.time)",
            comment: pending.body.comment,
            fields: pending.body.fields,
            isDeleted: false
        )
    }
}
