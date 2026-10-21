import Foundation
@testable import Petzy
import Testing

/// Набор типов сохраняется вместе с питомцем: отдельного запроса у сервера нет,
/// поэтому он должен попасть в то же тело, что и остальные поля карточки.
@MainActor
@Suite("Сохранение набора типов")
struct TileSaveTests {
    @Test("Выключенный тип уходит в теле сохранения")
    func saveSendsHiddenType() async {
        StubURLProtocol.reset()
        // Первым читается питомец, потом его сохраняют и перечитывают.
        StubURLProtocol.stub(status: 200, json: ["pet": [
            "_id": "p1", "name": "Рекс", "current_user_is_owner": true
        ]])
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Данные питомца обновлены"])
        StubURLProtocol.stub(status: 200, json: ["pet": [
            "_id": "p1", "name": "Рекс", "current_user_is_owner": true
        ]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        let offline = OfflineState(store: LocalStore(url: TestSupport.tempStoreURL()))
        let model = PetProfileModel(client: client, petID: "p1", offline: offline)
        await model.load()

        model.draft.tiles.visible["feeding"] = false
        await model.save(photo: nil, removePhoto: false)

        let sent = StubURLProtocol.requests
            .filter { $0.httpMethod == "PUT" }
            .map { String(data: TestSupport.rawBody(of: $0), encoding: .utf8) ?? "" }
            .joined()
        #expect(sent.contains("tiles_settings"), "в теле нет поля: \(sent.prefix(400))")
        #expect(sent.contains("\"feeding\":false"), "в теле нет выключенного типа: \(sent.prefix(400))")
    }
}
