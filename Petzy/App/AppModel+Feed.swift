import Foundation

/// Приёмы ленты: страницы по курсору, показ копии без сети и отправка
/// очереди. Живут в своём файле, потому что `AppModel` и без них влезает в
/// лимит, а лента — половина экрана приложения.
extension AppModel {
    /// Показывает копию выбранного питомца. Вызывается перед первой попыткой
    /// сети: без связи человек должен увидеть свой дневник сразу, а не после
    /// ожидания, которое ничем не кончится.
    func restoreFromCache() {
        guard !offline.isShowingCached, let petID = selectedPetID,
              let cached = offline.cachedEvents(petID: petID) else { return }
        // Копия без типов показала бы записи голыми ключами, поэтому берём и
        // типы: без них человек не прочитает, что за запись увидел.
        eventTypes = offline.snapshot.eventTypes
        rawEvents = cached
        offline.isShowingCached = true
    }

    /// Записи очереди показываются в ленте сразу: человек сделал их в метро и
    /// должен видеть их так же, как остальные.
    func showPending() {
        guard let petID = selectedPetID else { return }
        rawEvents.removeAll { offline.pendingIDs.contains($0.id) }
        rawEvents.append(contentsOf: offline.pendingEvents(petID: petID))
    }

    /// Очередь уходит, когда сеть вернулась. После отправки лента перечитывается:
    /// сервер отдаст записи со своими `id` вместо наших имён.
    func flushQueue() async {
        guard !flushingPending else { return }
        let before = offline.pendingCount
        flushingPending = true
        await offline.flush(using: client)
        flushingPending = false
        // Лента перечитывается, когда очередь изменилась: ушедшая запись
        // приходит с серверным именем, а отброшенная сервером должна исчезнуть.
        guard before > 0, offline.pendingCount != before else { return }
        await loadFeed()
    }

    // MARK: - Страницы ленты

    /// Страница записей. Курсор вместо номера страницы: новая запись не сдвигает
    /// страницу, поэтому ни одна запись не читается дважды и ни одна не теряется.
    func fetchPage(petID: String, before: String?) async throws -> EventsPage {
        // with_deleted=1: удалённая запись приходит надгробием, и приложение
        // знает, что её надо убрать из своей копии. Сами надгробия на показ
        // не идут, их отсекает Feed.group.
        var path = "/api/events?with_deleted=1&page_size=100&pet_id=" + Self.query(petID)
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
            signOut()
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
