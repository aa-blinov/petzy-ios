import Foundation
@testable import Petzy
import Testing

/// Курс и отметка приёма без связи. Сделано в метро, уйдёт само.
@MainActor
@Suite("Лекарства: без сети")
struct MedicationsOfflineTests {
    /// Курс, созданный без связи, не должен пропасть: он встаёт в очередь под
    /// своим именем, и сервер на повтор ответит тем же курсом, а не вторым.
    @Test("Курс без сети встаёт в очередь под своим именем")
    func createWithoutNetworkGoesToQueue() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stubOffline()
        let model = try await makeModel()

        let saved = await model.create(MedicationsWriteTests.draft)

        #expect(saved)
        #expect(model.pending.count == 1)
        #expect(model.pending.first?.kind == .medication)
        #expect(model.pending.first?.title == MedicationsWriteTests.draft.name)
        #expect(model.pending.first?.path == "/api/medications")
    }

    /// Отметка приёма без связи: человек дал дозу, а сеть появится позже.
    /// Повтор отправки не должен закрыть слот второй раз.
    @Test("Отметка приёма без сети встаёт в очередь")
    func markWithoutNetworkGoesToQueue() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        StubURLProtocol.stubOffline()
        let model = try await makeModel()
        await model.load()

        await model.markDose(MedicationsTests.med(days: [], times: []), dose: 1)

        #expect(model.pending.count == 1)
        #expect(model.pending.first?.kind == .intake)
        #expect(model.pending.first?.path == "/api/medications/m1/log")
    }

    /// Правка курса отправляет версию, которую человек видел. Если курс
    /// поменяли с тех пор, сервер отвечает отказом, и остаётся версия сервера.
    @Test("Правка курса отправляет версию, при отказе остаётся версия сервера")
    func updateSendsVersionAndKeepsServerVersion() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["medications": [MedicationsTests.drontalJSON]])
        StubURLProtocol.stub(status: 200, json: ["doses": []])
        StubURLProtocol.stub(
            status: 409,
            json: ["success": false, "error": "Запись изменили, пока вы её правили", "code": "conflict"]
        )
        let model = try await makeModel()
        await model.load()

        await model.update("m1", draft: MedicationsWriteTests.draft)

        let body = TestSupport.body(of: StubURLProtocol.requests.first { $0.httpMethod == "PUT" })
        #expect(body["base_version"] as? String == "2026-10-19T13:03:38Z", "без версии правка затрёт чужую")
        #expect(model.errorText == "Запись изменили, пока вы её правили")
    }

    private func makeModel() async throws -> MedicationsModel {
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let tokens = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: tokens)
        await auth.restore()
        return MedicationsModel(
            client: APIClient(baseURL: baseURL, urlSession: session, auth: auth),
            petID: "p1",
            offline: OfflineState(store: LocalStore(url: TestSupport.tempStoreURL()))
        )
    }
}
