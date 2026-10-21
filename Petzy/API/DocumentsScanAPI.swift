import Foundation

/// Сканы: снимки МРТ и КТ приходят архивами, и такие файлы идут мимо сервера.
/// Приложение берёт у сервера ссылку, кладёт файл прямо в хранилище и потом
/// подтверждает загрузку. Без подтверждения файл остаётся занятым слотом и в
/// документы не попадает.
extension DocumentsAPI {
    /// Расширения, которые сервер принимает архивами (`SCAN_EXTENSIONS` в
    /// `web/storage.py`; в вебе те же, что в `documents.service.ts`).
    static let scanExtensions = [
        ".zip", ".7z", ".rar", ".tar", ".tar.gz", ".tgz", ".gz", ".dcm", ".iso"
    ]

    static func isScan(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return scanExtensions.contains { lower.hasSuffix($0) }
    }

    /// Что сервер говорит про сканы: включены ли они вовсе и какой файл велик.
    static func scanStatus(_ client: APIClient) async throws -> ScanStatus {
        try await client.get("/api/documents/storage")
    }

    /// Слот под загрузку: ссылка, тип и предел размера.
    static func reserveScan(
        _ client: APIClient,
        petID: String,
        filename: String,
        size: Int
    ) async throws -> ScanSlot {
        try await client.post(
            "/api/documents/scans",
            body: ScanRequest(petID: petID, filename: filename, size: size)
        )
    }

    /// Три шага: слот, загрузка по ссылке, подтверждение. Ошибка любого шага
    /// оставляет человека с несохранённым документом, но не с половиной.
    @discardableResult
    static func uploadScan(_ client: APIClient, draft: DocumentDraft, file: UploadFile) async throws -> Bool {
        let slot = try await reserveScan(
            client,
            petID: draft.petID,
            filename: file.name,
            size: file.data.count
        )
        try await put(file.data, to: slot, session: client.urlSession)
        let ack: DocumentAck = try await client.post(
            "/api/documents/scans/\(AppModel.query(slot.uploadID))/complete",
            body: ScanComplete(
                title: draft.title,
                note: draft.note,
                expiresAt: draft.expiresAt,
                category: draft.category.rawValue
            )
        )
        return ack.success
    }

    /// Файл кладётся прямо по подписанной ссылке: токен приложения туда не
    /// идёт, подпись в самой ссылке.
    private static func put(_ data: Data, to slot: ScanSlot, session: URLSession) async throws {
        guard let url = URL(string: slot.uploadURL) else {
            throw APIError.transport("Ссылка на хранилище не разобралась")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(slot.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await session.data(for: request)
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(code) else {
            throw APIError.transport("Хранилище не приняло файл")
        }
    }

    /// Размер словами: «512 КБ», «512 МБ». Своими руками, а не
    /// `ByteCountFormatter`: тот берёт локаль системы, а в тестах она английская,
    /// и строка «1 KB» разошлась бы с тем, что видит человек.
    static func sizeText(_ bytes: Int) -> String {
        let megabyte = 1024 * 1024
        if bytes >= megabyte {
            return "\(bytes / megabyte) МБ"
        }
        return "\(max(1, bytes / 1024)) КБ"
    }
}

/// Что сервер разрешает по сканам.
struct ScanStatus: Decodable, Sendable {
    let scansEnabled: Bool
    let maxScanBytes: Int

    enum CodingKeys: String, CodingKey {
        case scansEnabled = "scans_enabled"
        case maxScanBytes = "max_scan_bytes"
    }

    /// Что не так с файлом — до запроса, теми же словами, что и сервер.
    func problem(for filename: String, size: Int) -> String? {
        if !DocumentsAPI.isScan(filename) {
            return "Такой файл не принимается"
        }
        return size > maxScanBytes ? "Файл больше \(DocumentsAPI.sizeText(maxScanBytes))" : nil
    }
}

/// Слот под загрузку скана.
struct ScanSlot: Decodable, Sendable {
    let uploadID: String
    let uploadURL: String
    let contentType: String
    let maxBytes: Int

    enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case uploadURL = "upload_url"
        case contentType = "content_type"
        case maxBytes = "max_bytes"
    }
}

private struct ScanRequest: Encodable, Sendable {
    let petID: String
    let filename: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case filename
        case size
    }
}

private struct ScanComplete: Encodable, Sendable {
    let title: String
    let note: String?
    let expiresAt: String?
    let category: String

    enum CodingKeys: String, CodingKey {
        case title, note, category
        case expiresAt = "expires_at"
    }
}

private struct DocumentAck: Decodable, Sendable {
    let success: Bool
}
