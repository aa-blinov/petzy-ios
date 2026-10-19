import Foundation

/// Разговор с сервером про документы. Единственное место, где известны пути
/// `/api/documents` и ключи ответа: экран держит в руках `PetDocument` и про
/// JSON не знает.
enum DocumentsAPI {
    /// Список документов питомца, новые первыми.
    static func list(
        _ client: APIClient,
        petID: String,
        category: DocumentCategory? = nil
    ) async throws -> [PetDocument] {
        try await decode(raw(client, petID: petID, category: category))
    }

    /// Ответ списка как пришёл: его же кладут в копию для работы без сети.
    static func raw(_ client: APIClient, petID: String, category: DocumentCategory? = nil) async throws -> Data {
        var path = "/api/documents?pet_id=\(AppModel.query(petID))"
        if let category {
            path += "&category=\(AppModel.query(category.rawValue))"
        }
        return try await client.getRaw(path)
    }

    /// Разбор ответа списка. Один и тот же и для сети, и для копии.
    static func decode(_ data: Data) throws -> [PetDocument] {
        try JSONDecoder().decode(DocumentsResponse.self, from: data).documents.map(\.domain)
    }

    /// Загрузка файла. Тело не JSON, а multipart: поля формы и сам файл в
    /// одном теле. Файл тут обязателен: сервер без него отвечает 422.
    static func upload(
        _ client: APIClient,
        petID _: String,
        draft: DocumentDraft,
        file: UploadFile,
        zone: String? = nil
    ) async throws {
        var body = MultipartBody()
        body.addField(name: "pet_id", value: draft.petID)
        body.addField(name: "category", value: draft.category.rawValue)
        body.addField(name: "title", value: draft.title)
        if let note = draft.note {
            body.addField(name: "note", value: note)
        }
        if let expiresAt = draft.expiresAt {
            body.addField(name: "expires_at", value: expiresAt)
        }
        if let zone {
            body.addField(name: "tz", value: zone)
        }
        body.addFile(name: "file", fileName: file.name, contentType: file.contentType, data: file.data)

        let ack: DocumentAck = try await client.postMultipart(
            "/api/documents",
            body: body.data,
            contentType: body.contentType
        )
        _ = ack
    }

    /// Правка сведений о документе. Файл меняется отдельным запросом.
    static func update(_ client: APIClient, id: String, draft: DocumentDraft) async throws {
        let ack: DocumentAck = try await client.put(
            "/api/documents/\(AppModel.query(id))",
            body: DocumentUpdateBody(draft: draft)
        )
        _ = ack
    }

    /// Замена файла за тем же документом. Отдельным запросом, а не полем в
    /// правке сведений: так же и в веб-приложении, и причина одна — если
    /// файл не приняли, документ остаётся со своим прежним файлом и с уже
    /// сохранёнными словами. Старый файл сервер удаляет только после того,
    /// как новый сохранён.
    static func replaceFile(_ client: APIClient, id: String, file: UploadFile) async throws {
        var body = MultipartBody()
        body.addFile(name: "file", fileName: file.name, contentType: file.contentType, data: file.data)
        let ack: DocumentAck = try await client.putMultipart(
            "/api/documents/\(AppModel.query(id))/file",
            body: body.data,
            contentType: body.contentType
        )
        _ = ack
    }

    /// Файл документа целиком: его открывает системное меню «Поделиться».
    static func file(_ client: APIClient, id: String) async throws -> (data: Data, fileName: String?) {
        try await client.download("/api/documents/\(AppModel.query(id))/file")
    }

    static func delete(_ client: APIClient, id: String) async throws {
        try await client.delete("/api/documents/\(AppModel.query(id))")
    }
}

// MARK: - Тела запросов

/// Правка сведений. Пустая строка в `expires_at` и в `note` означает «убери
/// значение», а `null` — «не трогай»: это разные вещи, и путать их нельзя.
/// Именно из-за этой разницы снятый срок обязан уходить пустой строкой: если
/// поле просто не отправить, сервер оставит прежнюю дату, и человек увидит
/// срок, который уже снял.
private struct DocumentUpdateBody: Encodable {
    let category: String?
    let title: String?
    let note: String
    let expiresAt: String

    init(draft: DocumentDraft) {
        category = draft.category.rawValue
        title = draft.title
        note = draft.note ?? ""
        expiresAt = draft.expiresAt ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case category, title, note
        case expiresAt = "expires_at"
    }
}

// MARK: - Разобранный ответ

private struct DocumentsResponse: Decodable {
    let documents: [DocumentDTO]
}

private struct DocumentAck: Decodable {
    let id: String?
}

private struct DocumentDTO: Decodable {
    let id: String
    let category: String?
    let title: String
    let note: String?
    let expiresAt: String?
    let createdAt: String
    let contentType: String
    let fileSize: Int
    let fileURL: String?
    let medicalRecordKinds: [String]?
    let recordReminds: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case category, title, note
        case contentType = "content_type"
        case fileSize = "file_size"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case fileURL = "file_url"
        case medicalRecordKinds = "medical_record_kinds"
        case recordReminds = "record_reminds"
    }

    var domain: PetDocument {
        PetDocument(
            id: id,
            category: DocumentCategory.known(category ?? ""),
            title: title,
            note: note,
            // Пустая строка — это «срока нет»: сервер так отдаёт документ, у
            // которого срок сняли, а читать её как дату нельзя.
            expiresAt: expiresAt.flatMap { $0.isEmpty ? nil : $0 },
            createdAt: createdAt,
            contentType: contentType,
            fileSize: fileSize,
            fileURL: fileURL.flatMap(URL.init(string:)),
            recordKinds: medicalRecordKinds ?? [],
            recordReminds: recordReminds ?? false
        )
    }
}
