import Foundation
@testable import Petzy
import Testing

/// Модель документов: что показывается, что перечитывается после загрузки и
/// куда девается файл. Всё это проверяется без экрана.
@Suite("Документы: модель")
@MainActor
struct DocumentsModelTests {
    @Test("Список читается одним запросом и попадает в модель")
    func loadReadsDocuments() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        let model = try await makeModel()

        await model.load()

        #expect(StubURLProtocol.requestedPaths == ["/api/documents"])
        #expect(model.documents.count == 2)
        #expect(model.isLoading == false)
    }

    @Test("Загруженный документ перечитывает список: счётчики считает сервер")
    func uploadReloadsList() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        StubURLProtocol.stub(status: 201, json: ["id": "d9", "message": "Документ добавлен"])
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        let model = try await makeModel()
        await model.load()

        let saved = await model.upload(
            DocumentDraft(petID: "p1", category: .other, title: "Страховка", note: nil, expiresAt: nil),
            file: UploadFile(name: "a.pdf", contentType: "application/pdf", data: Data("%PDF".utf8))
        )

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/documents",
            "/api/documents",
            "/api/documents"
        ])
    }

    @Test("Без названия документ не уходит: сервер всё равно его не примет")
    func blankTitleNeverReachesServer() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        let model = try await makeModel()
        await model.load()

        let saved = await model.upload(
            DocumentDraft(petID: "p1", category: .other, title: "  ", note: nil, expiresAt: nil),
            file: UploadFile(name: "a.pdf", contentType: "application/pdf", data: Data())
        )

        #expect(saved == false)
        #expect(model.errorText == "Введите название")
        #expect(StubURLProtocol.requestedPaths == ["/api/documents"])
    }

    @Test("Сервер отказал в загрузке, список остался прежним")
    func failedUploadKeepsList() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        StubURLProtocol.stub(status: 422, json: [
            "success": false, "error": "Файл слишком большой", "code": "document_file_too_large"
        ])
        let model = try await makeModel()
        await model.load()

        let saved = await model.upload(
            DocumentDraft(petID: "p1", category: .other, title: "Страховка", note: nil, expiresAt: nil),
            file: UploadFile(name: "a.pdf", contentType: "application/pdf", data: Data())
        )

        #expect(saved == false)
        #expect(model.errorText == "Файл слишком большой")
        #expect(model.documents.count == 2)
    }

    @Test("Фильтр оставляет только свою категорию")
    func filterShowsOneCategory() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        let model = try await makeModel()
        await model.load()

        model.filter = .insurance

        #expect(model.visible.count == 1)
        #expect(model.visible.first?.title == "Страховка на год")
    }

    @Test("Значок вкладки считает документы с истёкшим сроком")
    func badgeCountsExpired() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        let model = try await makeModel()
        await model.load()

        // Документы из фикстуры живут до 2027 года, просроченных нет.
        #expect(model.expired == 0)
    }

    @Test("Документ с истёкшим сроком попадает в счётчик")
    func expiredDocumentIsCounted() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["documents": [
            [
                "_id": "d1", "category": "insurance", "content_type": "application/pdf",
                "created_at": "2020-01-01T00:00:00Z", "expires_at": "2020-04-21",
                "file_size": 100, "file_url": NSNull(), "medical_record_kinds": [],
                "medical_records": [], "note": "", "original_filename": "a.pdf",
                "pet_id": "p1", "record_reminds": false, "title": "Страховка"
            ]
        ]])
        let model = try await makeModel()
        await model.load()

        #expect(model.expired == 1)
    }

    /// Снятый срок сервер отдаёт пустой строкой. Читать её как дату нельзя:
    /// документ без срока вдруг оказывался «Срок истёк».
    @Test("Пустой срок — это отсутствие срока")
    func emptyExpiryMeansNoExpiry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["documents": [
            [
                "_id": "d1", "category": "insurance", "content_type": "application/pdf",
                "created_at": "2020-01-01T00:00:00Z", "expires_at": "",
                "file_size": 100, "file_url": NSNull(), "medical_record_kinds": [],
                "medical_records": [], "note": "", "original_filename": "a.pdf",
                "pet_id": "p1", "record_reminds": false, "title": "Страховка"
            ]
        ]])
        let model = try await makeModel()
        await model.load()

        let document = model.visible.first
        #expect(document?.expiresAt == nil)
        #expect(document?.expiryText == nil)
        #expect(model.expired == 0)
    }

    /// Сведения уходят первыми, файл вторым. Порядок не технический: если
    /// файл не приняли, у документа остаётся прежний, а уже набранные слова
    /// сохранены. Наоборот получилось бы наоборот: файл сменился бы, а
    /// название осталось старым.
    @Test("Правка документа: сведения, потом файл")
    func updateSendsDescriptionThenFile() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        StubURLProtocol.stub(status: 200, json: ["success": true])
        StubURLProtocol.stub(status: 200, json: ["success": true])
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        let model = try await makeModel()
        await model.load()

        let saved = await model.update(
            Self.document,
            draft: DocumentDraft(
                petID: "p1", category: .insurance, title: "Страховка 2027", note: nil, expiresAt: nil
            ),
            file: UploadFile(name: "new.pdf", contentType: "application/pdf", data: Data("%PDF".utf8))
        )

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/documents",
            "/api/documents/d1",
            "/api/documents/d1/file",
            "/api/documents"
        ])
    }

    @Test("Правка без нового файла не трогает прежний")
    func updateWithoutFileSkipsFileRoute() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        StubURLProtocol.stub(status: 200, json: ["success": true])
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        let model = try await makeModel()
        await model.load()

        let saved = await model.update(
            Self.document,
            draft: DocumentDraft(petID: "p1", category: .other, title: "Паспорт", note: nil, expiresAt: nil),
            file: nil
        )

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/documents",
            "/api/documents/d1",
            "/api/documents"
        ])
    }

    @Test("Непринятый файл показывает ошибку и не обещает, что всё сохранилось")
    func failedFileKeepsError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: DocumentResponseTests.response())
        StubURLProtocol.stub(status: 200, json: ["success": true])
        StubURLProtocol.stub(
            status: 422,
            json: ["success": false, "error": "Файл не поддерживается", "code": "validation_error"]
        )
        let model = try await makeModel()
        await model.load()

        let saved = await model.update(
            Self.document,
            draft: DocumentDraft(petID: "p1", category: .other, title: "Паспорт", note: nil, expiresAt: nil),
            file: UploadFile(name: "new.exe", contentType: "application/octet-stream", data: Data("MZ".utf8))
        )

        #expect(saved == false)
        #expect(model.errorText == "Файл не поддерживается")
    }

    static let document = PetDocument(
        id: "d1",
        category: .insurance,
        title: "Страховка",
        note: nil,
        expiresAt: "2020-04-21",
        createdAt: "2020-01-01T00:00:00Z",
        contentType: "application/pdf",
        fileSize: 100,
        fileURL: nil,
        recordKinds: [],
        recordReminds: false
    )

    private func makeModel() async throws -> DocumentsModel {
        // swiftlint:disable:next force_unwrapping
        let baseURL = URL(string: "http://localhost:5002")!
        let session = StubURLProtocol.makeSession()
        // swiftlint:disable:next force_unwrapping
        let tokens = InMemoryTokenStorage(
            tokens: StoredTokens(accessToken: "access-1", refreshToken: "refresh-1")
        )
        let auth = AuthSession(baseURL: baseURL, urlSession: session, storage: tokens)
        await auth.restore()
        return DocumentsModel(
            client: APIClient(baseURL: baseURL, urlSession: session, auth: auth),
            petID: "p1",
            offline: OfflineState(store: LocalStore(url: TestSupport.tempStoreURL()))
        )
    }
}
