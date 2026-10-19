import Foundation
@testable import Petzy
import Testing

/// Раздел без сети. Открытая копия лекарств нужна человеку в тот же момент,
/// когда он открывает раздел, а не после того, как дождётся сети: лекарство
/// дают по часам, а не по расписанию интернета.
@MainActor
@Suite("Офлайн: разделы")
struct OfflineSectionsTests {
    @Test("Без сети раздел лекарств показывает копию")
    func medicationsFallBackToCopy() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await Self.medicationsModel(store: store)
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        await model.load()
        #expect(model.medications.count == 1)
        StubURLProtocol.stubOffline()
        StubURLProtocol.stubOffline()

        let offline = await Self.medicationsModel(store: store)
        await offline.load()

        #expect(offline.medications.map(\.name) == ["Дронтал Плюс"])
        #expect(offline.isShowingCached)
        #expect(offline.errorText == nil, "без сети это не ошибка, а копия")
    }

    @Test("Свежая загрузка переписывает копию раздела")
    func freshLoadReplacesCopy() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await Self.medicationsModel(store: store)
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])

        await model.load()

        let copy = await Self.medicationsModel(store: store)
        StubURLProtocol.stubOffline()
        StubURLProtocol.stubOffline()
        await copy.load()

        #expect(copy.medications.count == 1)
        #expect(copy.isShowingCached)
    }

    @Test("Копии раздела нет — без сети остаётся честная ошибка")
    func withoutCopyThereIsAnError() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await Self.medicationsModel(store: store)
        StubURLProtocol.stubOffline()
        StubURLProtocol.stubOffline()

        await model.load()

        #expect(model.medications.isEmpty)
        #expect(model.isShowingCached == false)
        #expect(model.errorText != nil, "нечего показать, и молчать об этом нельзя")
    }

    @Test("Без сети раздел документов показывает копию")
    func documentsFallBackToCopy() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await Self.documentsModel(store: store)
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        await model.load()
        #expect(model.documents.count == 2)
        StubURLProtocol.stubOffline()

        let offline = await Self.documentsModel(store: store)
        await offline.load()

        #expect(offline.documents.count == 2)
        #expect(offline.isShowingCached)
        #expect(offline.errorText == nil)
    }

    /// Раздел перечитывается, когда очередь ушла, и связь может оборваться
    /// ровно в этот момент. Данные на экране от этого не должны ни пропасть,
    /// ни превратиться в ошибку: человек видит копию и плашку.
    @Test("Повторная загрузка без связи не выбивает список")
    func secondFailedLoadKeepsListAndNoError() async {
        StubURLProtocol.reset()
        let store = LocalStore(url: TestSupport.tempStoreURL())
        let model = await Self.medicationsModel(store: store)
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        await model.load()
        StubURLProtocol.stubOffline()

        await model.load()

        #expect(model.medications.map(\.name) == ["Дронтал Плюс"])
        #expect(model.isShowingCached)
        #expect(model.errorText == nil, "вторая неудача не должна выбивать список ошибкой")
    }

    // MARK: - Образцы

    static func documentsModel(store: LocalStore) async -> DocumentsModel {
        await DocumentsModel(
            client: MedicationsTests.client(session: StubURLProtocol.makeSession()),
            petID: "p1",
            offline: OfflineState(store: store)
        )
    }

    static func medicationsModel(store: LocalStore) async -> MedicationsModel {
        await MedicationsModel(
            client: MedicationsTests.client(session: StubURLProtocol.makeSession()),
            petID: "p1",
            offline: OfflineState(store: store)
        )
    }
}
