import Foundation
@testable import Petzy
import Testing

/// Разбор ответа `/api/documents`. Фикстура снята с живого стенда: ручная
/// расходилась с сервером, и документы просто не показывались.
@Suite("Документы: разбор ответа")
struct DocumentResponseTests {
    @Test("Документы читаются из ответа сервера")
    func documentsAreMapped() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.response())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let documents = try await DocumentsAPI.list(client, petID: "p1")

        #expect(StubURLProtocol.requestedPaths == ["/api/documents"])
        #expect(StubURLProtocol.requests.last?.url?.query == "pet_id=p1")
        #expect(documents.count == 2)
        #expect(documents.first?.title == "Паспорт, прививки 2025")
        #expect(documents.first?.category == .vaccination)
        #expect(documents.first?.fileSize == 601)
        #expect(documents.first?.contentType == "application/pdf")
    }

    @Test("Срок и заметка читаются, а пустая заметка остаётся пустой")
    func expiryAndNoteAreRead() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.response())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let documents = try await DocumentsAPI.list(client, petID: "p1")

        #expect(documents.first?.expiresAt == nil)
        #expect(documents.last?.expiresAt == "2027-04-21")
        #expect(documents.last?.note == "Годовой полис")
    }

    @Test("Виды записей медкарты, ссылающиеся на документ, доезжают")
    func linkedKindsAreRead() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.response())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let documents = try await DocumentsAPI.list(client, petID: "p1")

        #expect(documents.first?.recordKinds == ["vaccination"])
        #expect(documents.first?.linkedText == "В медкарте: Прививки")
    }

    @Test("Фильтр по категории уходит в запрос, а не в экран")
    func categoryFilterGoesToServer() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: Self.response())
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        _ = try await DocumentsAPI.list(client, petID: "p1", category: .insurance)

        #expect(StubURLProtocol.requestedPaths == ["/api/documents"])
        #expect(StubURLProtocol.requests.last?.url?.query == "pet_id=p1&category=insurance")
    }

    /// Настоящий ответ стенда, обрезанный до двух документов. Ключи здесь
    /// snake_case, и разбор без явных `CodingKeys` их не увидит.
    static func response() -> [String: Any] {
        [
            "documents": [
                [
                    "_id": "6ac0b451c775325d197b871a",
                    "category": "vaccination",
                    "content_type": "application/pdf",
                    "created_at": "2026-10-03T07:52:00Z",
                    "expires_at": NSNull(),
                    "file_size": 601,
                    "file_url": NSNull(),
                    "medical_record_kinds": ["vaccination"],
                    "medical_records": [],
                    "note": "",
                    "original_filename": "passport.pdf",
                    "pet_id": "6ac0b44fc775325d197b84df",
                    "record_reminds": false,
                    "title": "Паспорт, прививки 2025",
                    "tz": "Asia/Almaty",
                    "username": "demo"
                ],
                [
                    "_id": "6ac0b451c775325d197b871b",
                    "category": "insurance",
                    "content_type": "application/pdf",
                    "created_at": "2026-10-01T07:52:00Z",
                    "expires_at": "2027-04-21",
                    "file_size": 590,
                    "file_url": NSNull(),
                    "medical_record_kinds": [],
                    "medical_records": [],
                    "note": "Годовой полис",
                    "original_filename": "insurance.pdf",
                    "pet_id": "6ac0b44fc775325d197b84df",
                    "record_reminds": false,
                    "title": "Страховка на год",
                    "tz": "Asia/Almaty",
                    "username": "demo"
                ]
            ],
            "page": 1,
            "page_size": 100,
            "total": 2
        ]
    }
}
