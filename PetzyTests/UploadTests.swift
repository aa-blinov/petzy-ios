import Foundation
@testable import Petzy
import Testing

/// Загрузка файла отличается от остальных запросов: тело не JSON, а multipart,
/// и в нём лежит сам файл. Проверяется, что запрос собран правильно и что
/// сервер понял его как загрузку, а не как JSON.
@Suite("HTTP: загрузка файла")
@MainActor
struct UploadTests {
    @Test("Загрузка уходит multipart'ом с файлом и полями")
    func uploadSendsMultipart() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["id": "d1", "message": "Документ добавлен"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await DocumentsAPI.upload(
            client,
            petID: "p1",
            draft: DocumentDraft(
                petID: "p1",
                category: .vaccination,
                title: "Паспорт, прививки 2025",
                note: nil,
                expiresAt: "2027-04-21"
            ),
            file: UploadFile(name: "passport.pdf", contentType: "application/pdf", data: Data("%PDF-1.7".utf8))
        )

        #expect(StubURLProtocol.requestedPaths == ["/api/documents"])
        let request = try #require(StubURLProtocol.requests.last)
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(data: TestSupport.rawBody(of: request), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"pet_id\""))
        #expect(body.contains("name=\"category\""))
        #expect(body.contains("name=\"title\""))
        #expect(body.contains("Паспорт, прививки 2025"))
        #expect(body.contains("filename=\"passport.pdf\""))
        #expect(body.contains("%PDF-1.7"))
    }

    @Test("Зона уходит вместе с файлом: без неё дата добавления считалась бы по зоне смотрящего")
    func uploadCarriesZone() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["id": "d1"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await DocumentsAPI.upload(
            client,
            petID: "p1",
            draft: DocumentDraft(
                petID: "p1",
                category: .other,
                title: "Анализ",
                note: nil,
                expiresAt: nil
            ),
            file: UploadFile(name: "a.pdf", contentType: "application/pdf", data: Data()),
            zone: "Asia/Almaty"
        )

        let body = String(data: TestSupport.rawBody(of: StubURLProtocol.requests.last), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"tz\""))
        #expect(body.contains("Asia/Almaty"))
    }

    @Test("Срок не отправляется, если его нет: пустая строка значила бы «убери срок»")
    func emptyExpiryIsNotSent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: ["id": "d1"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await DocumentsAPI.upload(
            client,
            petID: "p1",
            draft: DocumentDraft(petID: "p1", category: .other, title: "Анализ", note: nil, expiresAt: nil),
            file: UploadFile(name: "a.pdf", contentType: "application/pdf", data: Data())
        )

        let body = String(data: TestSupport.rawBody(of: StubURLProtocol.requests.last), encoding: .utf8) ?? ""
        #expect(!body.contains("name=\"expires_at\""))
    }
}
