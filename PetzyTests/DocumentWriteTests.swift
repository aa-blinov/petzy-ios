import Foundation
@testable import Petzy
import Testing

/// Правка документа: сведения и файл уходят разными запросами. Здесь важно
/// само тело, потому что пустая строка на сервере значит «убери», а `null`
/// значит «не трогай», и перепутать их — значит тихо оставить старое.
@Suite("Документы: запись")
struct DocumentWriteTests {
    @Test("Снятый срок уходит пустой строкой, а не пропадает из запроса")
    func updateClearsExpiryWithEmptyString() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Документ обновлён"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await DocumentsAPI.update(
            client,
            id: "d1",
            draft: DocumentDraft(petID: "p1", category: .insurance, title: "Страховка", note: nil, expiresAt: nil)
        )

        #expect(StubURLProtocol.requestedPaths == ["/api/documents/d1"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["expires_at"] as? String == "")
        #expect(body["category"] as? String == "insurance")
        #expect(body["title"] as? String == "Страховка")
    }

    @Test("Пустая заметка убирается, а не остаётся прежней")
    func updateClearsNote() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await DocumentsAPI.update(
            client,
            id: "d1",
            draft: DocumentDraft(petID: "p1", category: .other, title: "Паспорт", note: nil, expiresAt: "2027-01-01")
        )

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["note"] as? String == "")
        #expect(body["expires_at"] as? String == "2027-01-01")
    }

    @Test("Файл документа меняется отдельным запросом multipart")
    func replaceFileUsesItsOwnRoute() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Документ обновлён"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await DocumentsAPI.replaceFile(
            client,
            id: "d1",
            file: UploadFile(name: "new.pdf", contentType: "application/pdf", data: Data("%PDF-2".utf8))
        )

        #expect(StubURLProtocol.requestedPaths == ["/api/documents/d1/file"])
        let request = try #require(StubURLProtocol.requests.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
        let sent = String(data: TestSupport.rawBody(of: request), encoding: .utf8) ?? ""
        #expect(sent.contains("name=\"file\""))
        #expect(sent.contains("new.pdf"))
    }
}
