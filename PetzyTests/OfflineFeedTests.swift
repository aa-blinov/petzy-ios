import Foundation
@testable import Petzy
import Testing

/// Лента без сети. Человек в метро должен видеть свой дневник и уметь сделать
/// в нём запись: она уйдёт сама, когда связь вернётся.
@MainActor
@Suite("Офлайн: лента")
struct OfflineFeedTests {
    @Test("Без сети лента показывает копию, а не пустоту")
    func feedFallsBackToCache() async {
        StubURLProtocol.reset()
        let store = Self.storeWithEvent()
        let model = await Self.model(store: store)
        await model.select(petID: "p1")
        StubURLProtocol.stubOffline()
        StubURLProtocol.stubOffline()

        await model.loadFeed()

        #expect(model.rawEvents.map(\.id) == ["e1"])
        #expect(model.offline.isShowingCached, "приложение обязано сказать, что показывает копию")
    }

    @Test("Успешная загрузка обновляет копию")
    func successfulLoadUpdatesCache() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: Self.tempURL())
        let model = await Self.model(store: store)
        await model.select(petID: "p1")
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: Self.page())

        await model.loadFeed()

        #expect(store.load().events["p1"]?.map(\.id) == ["e1"])
        #expect(model.offline.isShowingCached == false)
    }

    @Test("Запись без сети попадает в очередь со своим именем и видна в ленте")
    func createWithoutNetworkGoesToQueue() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: Self.tempURL())
        let model = await Self.model(store: store)
        await model.select(petID: "p1")
        StubURLProtocol.stubOffline()

        await model.createEvent(Self.draft)

        let snapshot = store.load()
        #expect(snapshot.queue.count == 1)
        #expect(snapshot.queue.first?.localID.isEmpty == false, "без своего имени запись не отправить повторно")
        #expect(snapshot.queue.first?.petID == "p1")
        #expect(model.offline.pendingIDs == Set(snapshot.queue.map(\.localID)))
        #expect(model.rawEvents.first?.id == snapshot.queue.first?.localID)
    }

    @Test("Очередь уходит при появлении сети и снимается с экрана")
    func queueFlushesWhenNetworkReturns() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: Self.tempURL())
        let model = await Self.model(store: store)
        await model.select(petID: "p1")
        StubURLProtocol.stubOffline()
        await model.createEvent(Self.draft)
        let localID = store.load().queue.first?.localID
        // Сеть вернулась: ответ на создание, затем пустая лента.
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Запись сохранена", "id": "e9"])
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: Self.page())

        await model.flushQueue()

        #expect(store.load().queue.isEmpty)
        #expect(model.offline.pendingIDs.isEmpty)
        #expect(model.rawEvents.map(\.id) == ["e1"])
        // Последний, а не первый: неудачная попытка из createEvent тоже попала в журнал.
        let sent = TestSupport.body(of: StubURLProtocol.requests.last {
            $0.url?.path == "/api/events" && $0.httpMethod == "POST"
        })
        #expect(sent["local_id"] as? String == localID, "запись должна уйти под своим именем")
    }

    /// Контракт: `409 record_deleted` — запись уже удалена на этом или другом
    /// устройстве. Её надо убрать и не слать снова, иначе она будет биться в
    /// сервер до бесконечности.
    @Test("Запись, удалённую на сервере, приложение убирает и не шлёт снова")
    func deletedOnServerDropsPending() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: Self.tempURL())
        let model = await Self.model(store: store)
        await model.select(petID: "p1")
        StubURLProtocol.stubOffline()
        await model.createEvent(Self.draft)
        StubURLProtocol.stub(
            status: 409,
            json: ["success": false, "error": "Запись удалена", "code": "record_deleted"]
        )
        // Лента перечитывается после того, как очередь изменилась.
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: Self.page())

        await model.flushQueue()

        #expect(store.load().queue.isEmpty)
        #expect(!model.rawEvents.map(\.id).contains { $0.hasPrefix("local-") }, "отброшенная запись осталась в ленте")
        #expect(model.offline.pendingIDs.isEmpty)
    }

    // MARK: - Образцы

    static func storeWithEvent() -> LocalStore {
        let store = LocalStore(url: tempURL())
        var snapshot = OfflineSnapshot()
        snapshot.pets = [Pet(id: "p1", name: "Рекс", species: nil, breed: nil, birthDate: nil, gender: nil)]
        snapshot.events = ["p1": [PetEvent(
            id: "e1",
            type: "weight",
            dateTime: "2026-10-19T08:00:00+05:00",
            comment: "Поел",
            fields: [:],
            isDeleted: false
        )]]
        store.save(snapshot)
        return store
    }

    static func model(store: LocalStore) async -> AppModel {
        await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
    }

    static var draft: EventDraft {
        EventDraft(
            type: EventTypeInfo(
                key: "weight",
                label: "Вес",
                icon: "scalemass",
                category: "health",
                fields: [],
                chart: nil
            ),
            values: [:],
            comment: "В метро",
            date: "2026-10-19",
            time: "08:00"
        )
    }

    static func page() -> [String: Any] {
        ["items": [[
            "_id": "e1", "type": "weight", "date_time": "2026-10-19T08:00:00+05:00",
            "comment": "Поел", "fields": [:], "pet_id": "p1", "tz": "Asia/Almaty"
        ]], "next_cursor": NSNull(), "page": 1, "page_size": 100, "total": 1]
    }

    static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("petzy-offline-feed-\(UUID().uuidString).json")
    }
}
