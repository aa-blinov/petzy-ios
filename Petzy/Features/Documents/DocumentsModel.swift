import Foundation
import Observation

/// Состояние вкладки «Документы». Знает про запросы и что после них показать,
/// но не знает про JSON: разбор лежит в `DocumentsAPI`, экран рисует то, что
/// здесь.
@MainActor
@Observable
final class DocumentsModel {
    private(set) var documents: [PetDocument] = []
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски.
    var errorText: String?
    var notice: String?
    /// Категория, по которой фильтруют. `nil` — показывают все.
    var filter: DocumentCategory?
    /// Файл, готовый к отправке из системного меню «Поделиться».
    /// Файл, открытый в просмотрщике. Записывается и из модели, и из
    /// просмотрщика: он закрывается сам и обнуляет это поле.
    var file: URL?

    private let client: APIClient
    private let petID: String
    private let offline: OfflineState

    /// На экране копия, а не сеть.
    private(set) var isShowingCached = false

    init(client: APIClient, petID: String, offline: OfflineState) {
        self.client = client
        self.petID = petID
        self.offline = offline
    }

    /// Документы по фильтру. Фильтр в списке, а не в запросе: список короткий,
    /// и перечитывать его при каждом нажатии не нужно.
    var visible: [PetDocument] {
        guard let filter else { return documents }
        return documents.filter { $0.category == filter }
    }

    /// Сколько документов в каждой категории: показывается рядом с фильтром.
    var counts: [(category: DocumentCategory, count: Int)] {
        DocumentCategory.allCases.compactMap { category in
            let count = documents.count { $0.category == category }
            return count > 0 ? (category, count) : nil
        }
    }

    /// Документы с истёкшим сроком: о них человек узнаёт из списка.
    var expired: Int {
        documents.count { $0.expiryText?.hasPrefix("Срок истёк") == true }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await DocumentsAPI.raw(client, petID: petID)
            documents = try DocumentsAPI.decode(data)
            offline.cacheDocuments(data, petID: petID)
            errorText = nil
            isShowingCached = false
        } catch {
            // Копия, а не ошибка: список документов без сети всё равно полезен,
            // а сообщение об ошибке только отнимает у человека пустой экран.
            if let decoded = documentsFromCopy() {
                documents = decoded
                isShowingCached = true
                return
            }
            errorText = Self.text(of: error)
        }
    }

    /// Загрузка файла. Файл уходит multipart'ом: сервер ждёт поля формы и
    /// сам файл в теле.
    @discardableResult
    func upload(_ draft: DocumentDraft, file upload: UploadFile) async -> Bool {
        if let problem = DocumentDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            try await DocumentsAPI.upload(
                client,
                petID: petID,
                draft: draft,
                file: upload,
                zone: Self.zone
            )
            notice = "Документ добавлен"
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Правка документа. Файла может не быть: человек правит название или срок
    /// и не прикасается к файлу, и прежний файл должен остаться.
    @discardableResult
    func update(_ document: PetDocument, draft: DocumentDraft, file: UploadFile?) async -> Bool {
        if let problem = DocumentDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            // Порядок не технический. Если файл не примут, у документа
            // останется прежний, а уже набранные слова будут сохранены.
            try await DocumentsAPI.update(client, id: document.id, draft: draft)
            if let file {
                try await DocumentsAPI.replaceFile(client, id: document.id, file: file)
            }
            notice = "Документ обновлён"
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Файл документа. Кладётся во временную папку: телефон не умеет
    /// показывать PDF сам, а системное меню умеет его отправить.
    func download(_ document: PetDocument) async {
        do {
            let loaded = try await DocumentsAPI.file(client, id: document.id)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                Self.fileName(title: document.title, serverName: loaded.fileName)
            )
            try loaded.data.write(to: url, options: .atomic)
            file = url
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Имя файла для просмотрщика. Он показывает имя, а не заголовок, а с
    /// сервера приходит `insurance.pdf`: человек должен видеть «Страховка на
    /// год». Расширение берём серверное — по нему просмотрщик выбирает, чем
    /// открывать.
    static func fileName(title: String, serverName: String?) -> String {
        let ext = (serverName as NSString?)?.pathExtension ?? ""
        // Слеш в заголовке сделал бы из имени путь.
        let base = title.replacingOccurrences(of: "/", with: "-")
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    func delete(_ document: PetDocument) async {
        errorText = nil
        do {
            try await DocumentsAPI.delete(client, id: document.id)
            // Убираем из своей копии только после ответа сервера: иначе документ
            // исчез бы с экрана, но остался бы в базе.
            documents.removeAll { $0.id == document.id }
        } catch {
            errorText = Self.text(of: error)
        }
    }

    private static var zone: String {
        TimeZone.current.identifier
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// Документы из копии, если она есть и разбирается.
    private func documentsFromCopy() -> [PetDocument]? {
        guard let copy = offline.documentsCopy(petID: petID),
              let decoded = try? DocumentsAPI.decode(copy), !decoded.isEmpty else { return nil }
        return decoded
    }
}

extension DocumentDraft {
    /// Что человек должен поправить до запроса, своими словами. `nil` — можно
    /// отправлять.
    static func problem(_ draft: DocumentDraft) -> String? {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите название"
        }
        return nil
    }
}
