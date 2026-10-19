import Foundation
@testable import Petzy
import Testing

/// Офлайн-записи вне ленты: курс лекарства и отметка приёма. Сделано без
/// связи, уходит само, когда связь вернулась, и не создаёт второй записи.
@MainActor
@Suite("Офлайн: записи вне ленты")
struct OfflineWritesTests {
    @Test("Курс без сети уходит на сервер, когда связь вернулась")
    func queuedCourseIsSentWhenNetworkIsBack() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
        await model.select(petID: "p1")
        let section = MedicationsModel(client: model.client, petID: "p1", offline: model.offline)
        StubURLProtocol.stubOffline()
        await section.create(MedicationsWriteTests.draft)
        #expect(model.offline.pendingCount == 1)

        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "m9"])
        await model.flushQueue()

        #expect(StubURLProtocol.requestedPaths.first == "/api/medications")
        #expect(model.offline.pendingCount == 0)
    }

    /// Отметка приёма несёт своё имя: повтор отправки не должен закрыть слот
    /// второй раз и списать дозу дважды.
    @Test("Отметка приёма без сети уходит один раз")
    func queuedIntakeIsSentOnce() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
        await model.select(petID: "p1")
        let section = MedicationsModel(client: model.client, petID: "p1", offline: model.offline)
        StubURLProtocol.stubOffline()
        await section.markDose(MedicationsTests.med(days: [], times: []), dose: 1)

        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "i1", "ran_out": false])
        await model.flushQueue()

        #expect(StubURLProtocol.requestedPaths.first == "/api/medications/m1/log")
        let body = TestSupport.body(of: StubURLProtocol.requests.first)
        #expect(body["local_id"] is String, "без своего имени отметка повторится")
        #expect(model.offline.pendingCount == 0)
    }

    /// Медзапись без связи: вес, прививка, приём у врача. То же самое: своё
    /// имя, очередь, отправка при первом же удобном случае.
    @Test("Медзапись без сети уходит на сервер, когда связь вернулась")
    func queuedRecordIsSentWhenNetworkIsBack() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
        await model.select(petID: "p1")
        let section = MedicalCardModel(client: model.client, petID: "p1", offline: model.offline)
        StubURLProtocol.stubOffline()
        let saved = await section.save(MedicalCardWriteTests.draft(.vaccination))
        #expect(saved)
        #expect(model.offline.pendingCount == 1)

        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "r1"])
        await model.flushQueue()

        #expect(StubURLProtocol.requestedPaths.first == "/api/medical-records")
        #expect(model.offline.pendingCount == 0)
    }

    /// Правка курса без сети не теряется: ждёт в очереди и уходит сама, с
    /// версией, которую человек видел.
    @Test("Правка курса без сети встаёт в очередь и уходит сама")
    func queuedCourseUpdateIsSent() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
        await model.select(petID: "p1")
        let section = MedicationsModel(client: model.client, petID: "p1", offline: model.offline)
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        await section.load()
        StubURLProtocol.stubOffline()

        await section.update("m1", draft: MedicationsWriteTests.draft)

        #expect(store.load().queue.count == 1)
        #expect(store.load().queue.first?.method == "PUT")
        #expect(store.load().queue.first?.path == "/api/medications/m1")

        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "id": "m1"])
        await model.flushQueue()

        #expect(store.load().queue.isEmpty)
    }

    /// Правка, которую сервер затёр, не должна лежать в очереди вечно: версия
    /// сервера остаётся, и человек должен об этом узнать.
    @Test("Правка, которую затёрли, уходит из очереди, а человек узнаёт")
    func conflictDropsWriteAndTellsPerson() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
        await model.select(petID: "p1")
        let section = MedicationsModel(client: model.client, petID: "p1", offline: model.offline)
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        await section.load()
        StubURLProtocol.stubOffline()
        await section.update("m1", draft: MedicationsWriteTests.draft)

        StubURLProtocol.reset()
        StubURLProtocol.stub(
            status: 409,
            json: ["success": false, "error": "Запись изменили, пока вы её правили", "code": "conflict"]
        )
        await model.flushQueue()

        #expect(store.load().queue.isEmpty, "затёртая правка не должна лежать в очереди вечно")
        #expect(model.queueRefusals == ["Запись изменили, пока вы её правили"])
    }

    /// Отправленное должно появиться в разделе без ручного обновления: человек
    /// открыл раздел, увидел «не отправлено», и ждать, что он нажмёт
    /// обновление, нельзя.
    @Test("Раздел узнаёт, что очередь ушла")
    func flushTellsSectionsToReload() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults(), store: store)
        await model.select(petID: "p1")
        let section = MedicationsModel(client: model.client, petID: "p1", offline: model.offline)
        StubURLProtocol.stubOffline()
        await section.create(MedicationsWriteTests.draft)
        #expect(model.queueFlushCount == 0)

        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["success": true, "id": "m9"])
        await model.flushQueue()

        #expect(model.queueFlushCount == 1)
    }
}
