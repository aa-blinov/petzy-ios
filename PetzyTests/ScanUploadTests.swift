import Foundation
@testable import Petzy
import Testing

/// Сканы: снимки МРТ и КТ приходят архивами, и такие файлы идут мимо сервера —
/// приложение берёт у него ссылку, кладёт файл прямо в хранилище и потом
/// подтверждает загрузку. Три шага, и порядок в них не косметика: без
/// подтверждения файл остаётся слотом и в документы не попадает.
@Suite("Документы: сканы архивом")
struct ScanUploadTests {
    @Test("Архив узнаётся по расширению")
    func scanIsRecognised() {
        for name in ["кт.zip", "мрт.7z", "снимки.rar", "архив.tar", "а.tar.gz", "б.tgz", "в.gz", "г.dcm", "д.iso"] {
            #expect(DocumentsAPI.isScan(name), "\(name) — архив")
        }
        #expect(DocumentsAPI.isScan("фото.jpg") == false)
        #expect(DocumentsAPI.isScan("анализ.pdf") == false)
    }

    @Test("Резерв уходит именем файла и размером")
    func reserveCarriesNameAndSize() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "upload_id": "u1",
            "upload_url": "https://storage.example/put/u1",
            "content_type": "application/zip",
            "max_bytes": 524_288_000
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let slot = try await DocumentsAPI.reserveScan(client, petID: "p1", filename: "кт.zip", size: 1024)

        #expect(StubURLProtocol.requestedPaths == ["/api/documents/scans"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["pet_id"] as? String == "p1")
        #expect(body["filename"] as? String == "кт.zip")
        #expect(body["size"] as? Int == 1024)
        #expect(slot.uploadID == "u1")
        #expect(slot.contentType == "application/zip")
    }

    @Test("Скан больше предела не уходит вовсе")
    func oversizedScanIsRefused() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["scans_enabled": true, "max_scan_bytes": 1000])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let status = try await DocumentsAPI.scanStatus(client)
        let problem = status.problem(for: "кт.zip", size: 2000)

        #expect(problem == "Файл больше 1 КБ")
    }

    /// Три шага и их порядок: резерв, загрузка по ссылке, подтверждение.
    @Test("Загрузка идёт тремя шагами по порядку")
    func uploadGoesThroughThreeSteps() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "upload_id": "u1",
            "upload_url": "https://storage.example/put/u1",
            "content_type": "application/zip",
            "max_bytes": 524_288_000
        ])
        StubURLProtocol.stub(status: 200, data: Data(), headers: [:])
        StubURLProtocol.stub(status: 201, json: ["success": true, "message": "Документ добавлен"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        let file = UploadFile(name: "кт.zip", contentType: "application/zip", data: Data("PK".utf8))

        let saved = try await DocumentsAPI.uploadScan(
            client,
            draft: DocumentDraft(petID: "p1", category: .imaging, title: "КТ", note: nil, expiresAt: nil),
            file: file
        )

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/documents/scans",
            "/put/u1",
            "/api/documents/scans/u1/complete"
        ])
        let put = StubURLProtocol.requests[1]
        #expect(put.httpMethod == "PUT")
        #expect(put.value(forHTTPHeaderField: "Content-Type") == "application/zip")
        let complete = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(complete["title"] as? String == "КТ")
    }
}
