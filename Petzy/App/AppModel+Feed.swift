import Foundation

/// Приёмы ленты: страницы по курсору, показ копии без сети и отправка
/// очереди. Живут в своём файле, потому что `AppModel` и без них влезает в
/// лимит, а лента — половина экрана приложения.
extension AppModel {
    /// Показывает копию выбранного питомца. Вызывается перед первой попыткой
    /// сети: без связи человек должен увидеть свой дневник сразу, а не после
    /// ожидания, которое ничем не кончится.
    func restoreFromCache() {
        // Копия своя: на общем устройстве следующий вошедший не должен видеть
        // чужой дневник.
        guard canUseDiary, !offline.isShowingCached, let petID = selectedPetID,
              let cached = offline.cachedEvents(petID: petID) else { return }
        // Копия без типов показала бы записи голыми ключами, поэтому берём и
        // типы: без них человек не прочитает, что за запись увидел.
        eventTypes = offline.snapshot.eventTypes
        rawEvents = cached
        offline.isShowingCached = true
        // Записи и правки, сделанные без сети, показываются и по копии: в
        // метро человек сделал их, и ждать связи, чтобы увидеть свою запись,
        // незачем.
        showPending()
    }

    /// Записи очереди показываются в ленте сразу: человек сделал их в метро и
    /// должен видеть их так же, как остальные.
    func showPending() {
        guard let petID = selectedPetID else { return }
        rawEvents.append(contentsOf: offline.pendingEvents(petID: petID))
        applyPendingEdits()
    }

    /// Правки, сделанные без сети, кладутся поверх того, что показано. Запись
    /// на сервере есть, и на экране должна быть отредактированная, с пометкой
    /// «не отправлено»: серверная версия выглядела бы так, будто правка
    /// пропала, а человек потом ищет её по всей ленте.
    func applyPendingEdits() {
        guard let petID = selectedPetID else { return }
        for edit in offline.pendingEventEdits(petID: petID) {
            guard let index = rawEvents.firstIndex(where: { $0.id == edit.id }) else { continue }
            let old = rawEvents[index]
            rawEvents[index] = PetEvent(
                id: old.id,
                type: old.type,
                dateTime: "\(edit.date) \(edit.time)",
                comment: edit.comment,
                fields: edit.fields,
                isDeleted: false,
                updatedAt: old.updatedAt
            )
        }
    }

    /// Очередь уходит, когда сеть вернулась. После отправки лента перечитывается:
    /// сервер отдаст записи со своими `id` вместо наших имён.
    func flushQueue() async {
        guard !flushingPending else { return }
        let before = offline.pendingCount
        let hadPets = offline.pendingPets.isEmpty == false
        flushingPending = true
        queueRefusals = await offline.flush(using: client)
        flushingPending = false
        // Лента перечитывается, когда очередь изменилась: ушедшая запись
        // приходит с серверным именем, а отброшенная сервером должна исчезнуть.
        guard before > 0, offline.pendingCount != before else { return }
        queueFlushCount += 1
        await loadFeed()
        // Питомец, заведённый без связи, появился на сервере: без перечитки
        // списка в переключателе его не было бы.
        if hadPets {
            await loadPets()
        }
    }

    // MARK: - Записи

    /// Сохраняет новую запись и, если получилось, перечитывает ленту: запись
    /// должна появиться сразу, а не после ручного обновления.
    func createEvent(_ draft: EventDraft) async {
        guard let petID = selectedPetID else { return }
        feedErrorText = nil
        do {
            let request = EventRequest.create(draft, petID: petID)
            let saved = try await client.post("/api/events", body: request, as: EventSavedResponse.self)
            await loadFeed()
            await reloadHistory()
            showSaved(saved.id, date: draft.date)
        } catch {
            // Запись без сети это не ошибка, а очередь: человек сделал её в
            // метро, и она должна дождаться связи вместе с остальными.
            if (error as? APIError)?.isTransport == true {
                if let event = queueEvent(draft, petID: petID) {
                    rawEvents.append(event)
                }
                feedNotice = "Записано в телефон, уйдёт на сервер, когда появится связь"
                return
            }
            handleFeedError(error)
        }
    }

    /// Ставит запись ленты в очередь под своим именем. Имя это то, по которому
    /// сервер узнает повтор: он отдаст ту же запись, а не создаст вторую.
    func queueEvent(_ draft: EventDraft, petID: String) -> PetEvent? {
        let localID = "local-" + UUID().uuidString
        guard let payload = EventRequest.payload(draft, petID: petID, localID: localID) else { return nil }
        let write = PendingWrite(
            localID: localID,
            petID: petID,
            kind: .event,
            title: draft.type.label,
            method: "POST",
            path: "/api/events",
            payload: payload
        )
        offline.enqueue(write)
        return OfflineState.event(from: write)
    }

    /// Правка существующей записи.
    func updateEvent(id: String, draft: EventDraft) async {
        // Запись из очереди ещё не на сервере: правка идёт по своему имени и
        // без сети, иначе опечатку в метро было бы не исправить.
        if updatePending(id: id, draft: draft) {
            feedNotice = nil
            return
        }
        feedErrorText = nil
        do {
            let request = EventRequest.update(draft, baseVersion: version(of: id))
            _ = try await client.put("/api/events/\(id)", body: request, as: EventSavedResponse.self)
            await loadFeed()
            await reloadHistory()
        } catch {
            // Правка без сети не теряется: она ждёт в очереди и уходит сама.
            if (error as? APIError)?.isTransport == true {
                queueUpdate(id: id, draft: draft)
                return
            }
            // Запись поменяли, пока человек её правил. Остаётся версия
            // сервера, и её надо показать, а не держать на экране старую.
            if (error as? APIError)?.code == "conflict" {
                await loadFeed()
            }
            handleFeedError(error)
        }
    }

    /// Правка записи, которая ещё лежит в очереди: на сервере её нет, и
    /// ждать ради исправления опечатки связи незачем.
    private func updatePending(id: String, draft: EventDraft) -> Bool {
        guard offline.pendingIDs.contains(id), let petID = selectedPetID, let payload = EventRequest.payload(
            draft,
            petID: petID,
            localID: id
        ), let updated = offline.updatePending(id, payload: payload, title: draft.type.label),
        let event = OfflineState.event(from: updated),
        let index = rawEvents.firstIndex(where: { $0.id == id }) else { return false }
        rawEvents[index] = event
        return true
    }

    /// Ставит правку в очередь. Запись на сервере уже есть, поэтому идёт
    /// запрос на её адрес, но с версией, которую человек видел: сервер откажет,
    /// если запись поменяли с тех пор, и останется версия сервера.
    private func queueUpdate(id: String, draft: EventDraft) {
        guard let petID = selectedPetID,
              let payload = EventRequest.updatePayload(draft, baseVersion: version(of: id))
        else { return }
        offline.enqueue(PendingWrite(
            localID: id,
            petID: petID,
            kind: .event,
            title: draft.type.label,
            method: "PUT",
            path: "/api/events/\(id)",
            payload: payload
        ))
        // На экране сразу новое значение с отметкой «не отправлено»: человек
        // должен видеть, что он изменил, а не то, что было до правки.
        if let index = rawEvents.firstIndex(where: { $0.id == id }) {
            let old = rawEvents[index]
            rawEvents[index] = PetEvent(
                id: old.id,
                type: old.type,
                dateTime: old.dateTime,
                comment: draft.comment,
                fields: draft.encodedFields,
                isDeleted: false,
                updatedAt: old.updatedAt
            )
        }
        feedNotice = "Правка сохранена в телефон, уйдёт на сервер, когда появится связь"
    }

    /// Версия записи, которую человек правил. Сервер откажет, если запись
    /// поменяли с тех пор, как её прочитали.
    private func version(of id: String) -> String? {
        rawEvents.first { $0.id == id }?.updatedAt
    }

    /// Удаление. Убираем из своей копии только после ответа сервера: иначе
    /// запись исчезла бы с экрана, но осталась бы в базе, и человек бы её
    /// искал, думая, что неудачно сохранил.
    func deleteEvent(id: String) async {
        // Запись из очереди удаляется целиком на устройстве: на сервере её
        // нет, и запрос только спросил бы о том, чего не существует.
        if offline.pendingIDs.contains(id) {
            offline.removePending(id)
            rawEvents.removeAll { $0.id == id }
            return
        }
        feedErrorText = nil
        do {
            try await client.delete("/api/events/\(id)")
            rawEvents.removeAll { $0.id == id }
        } catch {
            handleFeedError(error)
        }
    }

    // MARK: - Страницы ленты

    /// Страница записей. Курсор вместо номера страницы: новая запись не сдвигает
    /// страницу, поэтому ни одна запись не читается дважды и ни одна не теряется.
    func fetchPage(petID: String, before: String?) async throws -> EventsPage {
        // Без надгробий: удалённые записи сервер и так не отдаёт, а надгробия
        // занимали бы место в странице — из ста записей на показ оставалась одна,
        // и лента выглядела пустой. Свою копию приложение и так заменяет
        // целиком, поэтому знать об удалениях по надгробиям не нужно.
        var path = "/api/events?page_size=100&pet_id=" + Self.query(petID)
        if let before {
            path += "&before=" + Self.query(before)
        }
        return try await client.get(path, as: EventsPage.self)
    }

    func apply(_ page: EventsPage, appending: Bool) {
        rawEvents = appending ? rawEvents + page.items : page.items
        feedNextCursor = page.nextCursor
        hasMoreEvents = page.nextCursor != nil
    }

    /// Показать сохранённую запись. Если её нет в загруженной части ленты,
    /// говорим словами, за какой день она: запись с датой в прошлом после
    /// сохранения иначе просто исчезает, и человек решает, что не записалась.
    func showSaved(_ id: String?, date: String) {
        feedNotice = nil
        guard let id, !rawEvents.contains(where: { $0.id == id }) else { return }
        feedNotice = "Она за " + MomentText.russianDay(date) + ", в ленте до неё надо долистать"
    }

    func handleFeedError(_ error: Error) {
        let apiError = error as? APIError
        if apiError?.isAuthProblem == true {
            endSession()
            return
        }
        // Сервера не было: оставляем на экране копию и говорим об этом, вместо
        // того чтобы заменить дневник пустотой.
        if apiError?.isTransport == true, !rawEvents.isEmpty {
            offline.isShowingCached = true
            return
        }
        feedErrorText = apiError?.errorDescription ?? error.localizedDescription
    }
}
