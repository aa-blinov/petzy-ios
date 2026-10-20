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

    // MARK: - Копии разделов

    /// Кладёт ответ раздела в копию. Отдел пришёл на телефон, и следующий
    /// запуск без сети должен показать ровно его.
    func cacheMedications(_ data: Data, petID: String) {
        snapshot.medications[petID] = data
        store.save(snapshot)
    }

    func medicationsCopy(petID: String) -> Data? {
        snapshot.medications[petID]
    }

    func cacheDocuments(_ data: Data, petID: String) {
        snapshot.documents[petID] = data
        store.save(snapshot)
    }

    func documentsCopy(petID: String) -> Data? {
        snapshot.documents[petID]
    }

    func cacheCard(_ data: Data, petID: String) {
        snapshot.card[petID] = data
        store.save(snapshot)
    }

    func cardCopy(petID: String) -> Data? {
        snapshot.card[petID]
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
    func enqueue(_ write: PendingWrite) -> PendingWrite {
        // Правка, которая уже лежит в очереди, заменяется новой: иначе ушло бы
        // два запроса с одной версией, и второй отказался бы как устаревший.
        snapshot.queue.removeAll { $0.localID == write.localID && $0.kind == write.kind }
        snapshot.queue.append(write)
        store.save(snapshot)
        pendingIDs.insert(write.localID)
        return write
    }

    /// Питомцы, которых ещё нет на сервере: они ждут своей очереди.
    var pendingPets: [PendingWrite] {
        snapshot.queue.filter { $0.kind == .pet }
    }

    /// Неотправленное выбранного питомца по виду записи: раздел показывает
    /// своё, а чужое ему видеть незачем.
    func pendingWrites(kind: PendingKind, petID: String) -> [PendingWrite] {
        snapshot.queue.filter { $0.kind == kind && $0.petID == petID }
    }

    /// Всё неотправленное, для списка в настройках.
    var pending: [PendingWrite] {
        snapshot.queue
    }

    /// Записи очереди выбранного питомца, готовые к показу. Только создания:
    /// правка меняет запись, которая уже на экране, и своей строкой не нужна.
    func pendingEvents(petID: String) -> [PetEvent] {
        pendingWrites(kind: .event, petID: petID)
            .filter { $0.method == "POST" }
            .compactMap(Self.event(from:))
    }

    /// Правки записей, сделанные без сети: что человек изменил и в какой
    /// записи. Их надо класть поверх того, что показано, иначе на экране
    /// останется серверная версия, а человек решит, что правка пропала.
    func pendingEventEdits(petID: String) -> [PendingEventEdit] {
        pendingWrites(kind: .event, petID: petID)
            .filter { $0.method == "PUT" }
            .compactMap { write in
                guard let body = try? JSONDecoder().decode(PendingEditBody.self, from: write.payload) else {
                    return nil
                }
                return PendingEventEdit(
                    id: write.localID,
                    date: body.date,
                    time: body.time,
                    comment: body.comment,
                    fields: body.fields
                )
            }
    }

    func removePending(_ localID: String) {
        snapshot.queue.removeAll { $0.localID == localID }
        store.save(snapshot)
        pendingIDs.remove(localID)
    }

    /// Правка неотправленной записи: она ещё не на сервере, и ждать ради
    /// исправления опечатки связи незачем. Отдаёт обновлённую запись для
    /// показа, `nil` — запись не наша, тогда правка идёт на сервер.
    @discardableResult
    func updatePending(_ localID: String, payload: Data, title: String) -> PendingWrite? {
        guard let index = snapshot.queue.firstIndex(where: { $0.localID == localID }) else { return nil }
        let old = snapshot.queue[index]
        snapshot.queue[index] = PendingWrite(
            localID: old.localID,
            petID: old.petID,
            kind: old.kind,
            title: title,
            method: old.method,
            path: old.path,
            payload: payload
        )
        store.save(snapshot)
        return snapshot.queue[index]
    }

    /// Отправляет очередь. Останавливается на первой неудаче: следующая запись
    /// может зависеть от предыдущей, и человек должен видеть, сколько ещё ждать.
    /// Возвращает то, что сервер отказал отправить: такие записи из очереди
    /// уходят, и человек должен узнать почему.
    @discardableResult
    func flush(using client: APIClient) async -> [String] {
        var refused: [String] = []
        while let pending = snapshot.queue.first {
            do {
                try await client.sendRaw(
                    pending.path,
                    method: pending.method,
                    body: pending.payload,
                    contentType: pending.contentType
                )
                removePending(pending.localID)
            } catch {
                // Запись на сервере уже удалили. Повторять её незачем: она вернёт
                // тот же отказ, и человек так и не увидит, что она исчезла.
                guard let apiError = error as? APIError, let code = apiError.code,
                      refusedByServer(code) else { return refused }
                if code != "record_deleted" {
                    refused.append(apiError.errorDescription ?? "Запись не отправлена")
                }
                removePending(pending.localID)
            }
        }
        return refused
    }

    /// Отказы, после которых запись из очереди уходит: её больше некуда
    /// отправлять, и повтор вернёт тот же отказ.
    private func refusedByServer(_ code: String) -> Bool {
        switch code {
        case "record_deleted", "not_found", "record_not_found", "local_id_taken", "conflict", "duplicate_intake":
            true
        default:
            false
        }
    }

    /// Запись очереди в виде строки ленты. Время без пояса: человек вводил его
    /// на своих часах, а выдуманное смещение сдвинуло бы его в ленте.
    static func event(from pending: PendingWrite) -> PetEvent? {
        guard let body = try? JSONDecoder().decode(PendingBody.self, from: pending.payload) else { return nil }
        return PetEvent(
            id: pending.localID,
            type: body.type,
            dateTime: "\(body.date) \(body.time)",
            comment: body.comment,
            fields: body.fields,
            isDeleted: false
        )
    }
}
