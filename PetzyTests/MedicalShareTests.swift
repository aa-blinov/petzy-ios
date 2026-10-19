import Foundation
@testable import Petzy
import Testing

/// Ссылка для врача. Секрет сервер показывает один раз и больше не хранит,
/// поэтому тест здесь про то, что адрес не теряется и что список действующих
/// ссылок перечитывается, а не остаётся как был.
@Suite("Медкарта: ссылка для врача")
@MainActor
struct MedicalShareTests {
    @Test("Срок ссылки выбирается только из тех, что сервер принимает")
    func daysAreFromServerSet() {
        // `days` на сервере это Literal[1, 7, 30], и четвёртое значение
        // отклонилось бы 422. Список живёт здесь, а не в форме.
        #expect(MedicalShareDays.all == [1, 7, 30])
        #expect(MedicalShareDays.title(1) == "1 день")
        #expect(MedicalShareDays.title(7) == "7 дней")
        #expect(MedicalShareDays.title(30) == "30 дней")
    }

    @Test("Действующие ссылки читаются и показываются до какого дня")
    func sharesAreLoaded() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, json: ["shares": [
            ["id": "s1", "username": "demo", "created_at": "2026-10-18T07:52:00Z",
             "expires_at": "2026-10-25T07:52:00Z"],
            ["id": "s2", "username": "demo", "created_at": "2026-10-17T07:52:00Z",
             "expires_at": "2026-11-16T07:52:00Z"]
        ]])
        let model = try await makeModel()
        await model.load()

        await model.loadShares()

        #expect(StubURLProtocol.requestedPaths == [
            "/api/pets/p1/medical-card",
            "/api/pets/p1/medical-card/shares"
        ])
        #expect(model.shares.map(\.id) == ["s1", "s2"])
        #expect(model.shares.first?.expiresText == "Откроется до 25.10.2026")
    }

    @Test("Отзыв ссылки убирает её из списка и перечитывает его у сервера")
    func revokeRemovesShare() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, json: ["shares": [
            ["id": "s1", "expires_at": "2026-10-25T07:52:00Z"],
            ["id": "s2", "expires_at": "2026-11-16T07:52:00Z"]
        ]])
        StubURLProtocol.stub(status: 200, json: ["revoked": true])
        StubURLProtocol.stub(status: 200, json: ["shares": [
            ["id": "s2", "expires_at": "2026-11-16T07:52:00Z"]
        ]])
        let model = try await makeModel()
        await model.load()
        await model.loadShares()

        await model.revoke(LiveShare(id: "s1", expiresAt: "2026-10-25T07:52:00Z"))

        // Отзыв это DELETE по адресу самой ссылки, а не по списку.
        let deletes = StubURLProtocol.requests.filter { $0.httpMethod == "DELETE" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.url?.path == "/api/pets/p1/medical-card/shares/s1")
        #expect(StubURLProtocol.requestedPaths.last == "/api/pets/p1/medical-card/shares")
        #expect(model.shares.map(\.id) == ["s2"])
    }

    /// Отозванный адрес нельзя оставлять на экране готовым к отправке: человек
    /// поделился бы ссылкой, которая карту уже не открывает.
    @Test("Отзыв убирает и готовую ссылку с экрана")
    func revokeClearsReadyShare() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 201, json: [
            "share": ["id": "s1", "expires_at": "2026-10-25T07:52:00Z"],
            "token": "tok123"
        ])
        StubURLProtocol.stub(status: 200, json: ["shares": [
            ["id": "s1", "expires_at": "2026-10-25T07:52:00Z"]
        ]])
        StubURLProtocol.stub(status: 200, json: ["revoked": true])
        StubURLProtocol.stub(status: 200, json: ["shares": []])
        let model = try await makeModel()
        await model.load()

        await model.createShare(days: 7)
        #expect(model.share != nil)

        await model.revoke(LiveShare(id: "s1", expiresAt: "2026-10-25T07:52:00Z"))

        #expect(model.share == nil)
    }

    @Test("Сервер не отозвал ссылку: список остаётся как был")
    func failedRevokeKeepsShare() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, json: ["shares": [
            ["id": "s1", "expires_at": "2026-10-25T07:52:00Z"]
        ]])
        StubURLProtocol.stub(status: 404, json: [
            "success": false, "error": "Ссылка не найдена", "code": "not_found"
        ])
        let model = try await makeModel()
        await model.load()
        await model.loadShares()

        await model.revoke(LiveShare(id: "s1", expiresAt: "2026-10-25T07:52:00Z"))

        #expect(model.errorText == "Ссылка не найдена")
        #expect(model.shares.map(\.id) == ["s1"])
    }

    @Test("Созданная ссылка попадает и в список действующих")
    func createdShareJoinsList() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: LiveFixtures.medicalCard)
        StubURLProtocol.stub(status: 200, json: ["shares": []])
        StubURLProtocol.stub(status: 201, json: [
            "share": ["id": "s9", "username": "demo", "expires_at": "2026-10-25T07:52:00Z"],
            "token": "abc123",
            "path": "/share/medical/abc123"
        ])
        StubURLProtocol.stub(status: 200, json: ["shares": [
            ["id": "s9", "expires_at": "2026-10-25T07:52:00Z"]
        ]])
        let model = try await makeModel()
        await model.load()
        await model.loadShares()

        await model.createShare(days: 7)

        // Без перечитывания список врал бы: ссылка есть, а в нём пусто.
        #expect(model.shares.map(\.id) == ["s9"])
        #expect(model.share?.token == "abc123")
    }

    @Test("Ссылка без даты окончания показывается без неё")
    func shareWithoutExpiry() {
        #expect(LiveShare(id: "s1", expiresAt: nil).expiresText == nil)
    }

    private func makeModel() async throws -> MedicalCardModel {
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let tokens = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: tokens)
        await auth.restore()
        return MedicalCardModel(client: APIClient(baseURL: baseURL, urlSession: session, auth: auth), petID: "p1")
    }
}
