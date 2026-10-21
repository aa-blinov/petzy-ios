import Foundation
@testable import Petzy
import Testing

/// Правка набора типов прямо из «+»: отдельного маршрута у сервера нет, набор
/// едет вместе с карточкой питомца, а карточка заменяется целиком. Значит перед
/// записью её надо прочитать, иначе сохранение затрёт остальные поля пустыми.
@MainActor
@Suite("Правка типов из «+»")
struct PetTilesSaveTests {
    @Test("Набор сохраняется на карточке, прочитанной перед записью")
    func saveReadsThenWrites() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["pet": [
            "_id": "p1", "name": "Рекс", "species": "dog", "breed": "Лабрадор",
            "gender": "boy", "health_notes": "Аллергия", "current_user_is_owner": true,
            "updated_at": "2026-10-21T06:57:45Z",
            "tiles_settings": ["order": ["feeding"], "visible": ["walk": true]]
        ]])
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Данные питомца обновлены"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var tiles = TileSettings()
        tiles.visible["vomiting"] = true

        try await PetTilesAPI.save(client, petID: "p1", tiles: tiles)

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1", "/api/pets/p1"])
        #expect(StubURLProtocol.requests.last?.httpMethod == "PUT")
        let sent = String(data: TestSupport.rawBody(of: StubURLProtocol.requests.last), encoding: .utf8) ?? ""
        #expect(sent.contains("tiles_settings"))
        #expect(sent.contains("\"vomiting\":true"))
        // Остальные поля не потерялись: карточка уходит целиком.
        #expect(sent.contains("Лабрадор"))
        #expect(sent.contains("Аллергия"))
    }
}
