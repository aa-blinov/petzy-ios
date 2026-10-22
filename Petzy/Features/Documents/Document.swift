import Foundation
import UIKit
import UniformTypeIdentifiers

/// Категория документа. Сервер зовёт её ключом, человек читает словом, и без
/// перевода список был бы списком ключей.
enum DocumentCategory: String, CaseIterable, Sendable {
    case vaccination
    case labResult = "lab_result"
    case conclusion
    case imaging
    case insurance
    case other

    var title: String {
        switch self {
        case .vaccination: "Прививки"
        case .labResult: "Анализы"
        case .conclusion: "Заключения"
        case .imaging: "Снимки"
        case .insurance: "Страховка"
        case .other: "Другое"
        }
    }

    /// Значок раздела в списке.
    var symbol: String {
        switch self {
        case .vaccination: "syringe"
        case .labResult: "cross.vial"
        case .conclusion: "text.page"
        case .imaging: "photo"
        case .insurance: "doc.text"
        case .other: "folder"
        }
    }

    /// Категория по ключу сервера. Неизвестная ключа — это «Другое», а не
    /// поломка списка: сервер может добавить категорию раньше, чем выйдет
    /// обновление приложения.
    static func known(_ raw: String) -> DocumentCategory {
        DocumentCategory(rawValue: raw) ?? .other
    }
}

/// Документ питомца: файл, его название и срок.
struct PetDocument: Identifiable, Sendable {
    let id: String
    let category: DocumentCategory
    let title: String
    let note: String?
    /// Срок действия. `nil` — срока нет.
    let expiresAt: String?
    let createdAt: String
    let contentType: String
    let fileSize: Int
    /// Подписанный адрес картинки: открыт без входа и живёт 1–2 часа.
    let fileURL: URL?
    /// Виды записей медкарты, ссылающиеся на этот документ.
    let recordKinds: [String]
    /// Запись с датой повтора ссылается на документ: напоминает о сроке сама.
    let recordReminds: Bool

    /// «Срок истёк 21.04.2020». Документ без срока срока не показывает.
    var expiryText: String? {
        guard let expiresAt else { return nil }
        let day = MomentText.russianDay(MomentText.day(of: expiresAt))
        let passed = MomentText.humanDay(MomentText.day(of: expiresAt)) == "Сегодня"
            || MomentText.day(of: expiresAt) < MomentText.isoDay(.now, calendar: .current)
        return passed ? "Срок истёк \(day)" : "Действует до \(day)"
    }

    /// «В медкарте: Прививки». Связь с записью медкарты человек ищет именно
    /// так, и пустой список молчал бы.
    var linkedText: String? {
        guard !recordKinds.isEmpty else { return nil }
        let names = recordKinds.compactMap { kind -> String? in
            MedicalKind(rawValue: kind)?.title
        }
        guard !names.isEmpty else { return nil }
        return "В медкарте: \(names.joined(separator: ", "))"
    }

    /// «601 КБ» или «2,4 МБ». Размер нужен, чтобы человек понимал, что он
    /// открывает, и килобайты не выглядят как «0,0006 МБ».
    var sizeText: String {
        if fileSize < 1000 {
            return "\(fileSize) Б"
        }
        let megabytes = Double(fileSize) / 1_000_000
        if megabytes >= 1 {
            return Amount.text((megabytes * 10).rounded() / 10) + " МБ"
        }
        return "\(fileSize / 1000) КБ"
    }
}

/// Документ в том виде, как его заполняет форма. Экран отдаёт черновик, а
/// названия полей сервера здесь не встречаются.
struct DocumentDraft: Sendable {
    var petID: String
    var category: DocumentCategory
    var title: String
    var note: String?
    /// Срок действия. `nil` — срока нет.
    var expiresAt: String?
}

/// Файл, который едет на сервер.
struct UploadFile: Sendable {
    let name: String
    let contentType: String
    let data: Data

    /// Тип по расширению: без него сервер получает файл без заголовка
    /// `Content-Type` и сам не разберётся, картинка это или pdf.
    static func contentType(of url: URL) -> String {
        let type = UTType(filenameExtension: url.pathExtension)
        return type?.preferredMIMEType ?? "application/octet-stream"
    }

    /// Что сервер берёт: ровно этот набор (`ALLOWED_CONTENT_TYPES` в
    /// `web/documents.py`). Всё остальное он отвергает ответом 422, и узнать
    /// об этом после загрузки — потерянное время человека.
    static let accepted: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "application/pdf"
    ]

    /// Подойдёт ли файл серверу. Регистр не наш, и `IMAGE/JPEG` — не отказ.
    static func isAccepted(_ contentType: String) -> Bool {
        accepted.contains(contentType.lowercased())
    }

    /// Фото из галереи или с камеры в том виде, в каком его примет сервер.
    /// Библиотека умеет отдать GIF или TIFF, а сервер их не берёт: отказать
    /// человеку после съёмки хуже, чем перегнать картинку в JPEG.
    static func normalizedImage(_ data: Data, type: String) -> UploadFile? {
        if isAccepted(type) {
            return UploadFile(name: "фото.\(fileExtension(of: type))", contentType: type, data: data)
        }
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else { return nil }
        return UploadFile(name: "фото.jpg", contentType: "image/jpeg", data: jpeg)
    }

    /// Расширение по типу: имя файла должно кончаться на то, чем он является,
    /// иначе сервер и «Файлы» будут спорить о нём.
    private static func fileExtension(of contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/webp": "webp"
        case "image/heic": "heic"
        case "image/heif": "heif"
        case "application/pdf": "pdf"
        default: "jpg"
        }
    }
}
