import Foundation

/// Тело запроса с файлом. Сервер ждёт `multipart/form-data`: поля формы и сам
/// файл в одном теле, разделённые границей. Собирается вручную, а не
/// `URLRequest`-ом с `httpBodyStream`, потому что файл уже лежит в памяти и
/// поток тут ни к чему.
struct MultipartBody {
    let boundary: String
    private var parts: [Data] = []

    init(boundary: String = "PetzyBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))") {
        self.boundary = boundary
    }

    /// Поле формы. Пустое значение по умолчанию не отправляется: у документов
    /// его отсутствие значит «не прислали». Карточка питомца наоборот шлёт
    /// пустые поля явно — для неё пустая строка значит «убери значение».
    mutating func addField(name: String, value: String, includeEmpty: Bool = false) {
        guard includeEmpty || !value.isEmpty else { return }
        parts.append(Self.textPart(name: name, value: value))
    }

    mutating func addFile(name: String, fileName: String, contentType: String, data: Data) {
        var part = Data()
        part.append(Self.header(name: name, fileName: fileName, contentType: contentType))
        part.append(data)
        part.append(Self.newline)
        parts.append(part)
    }

    /// Готовое тело. Пустое, если ничего не добавили: запрос без файла
    /// сервер всё равно отклонит, и пустое тело скажет об этом раньше.
    var data: Data {
        guard !parts.isEmpty else { return Data() }
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(part)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// Заголовок `Content-Type` с той же границей, что и в теле. Без него
    /// сервер не поймёт, где кончается одна часть и начинается другая.
    var contentType: String? {
        parts.isEmpty ? nil : "multipart/form-data; boundary=\(boundary)"
    }

    private static let newline = Data("\r\n".utf8)

    private static func textPart(name: String, value: String) -> Data {
        var part = Data()
        part.append(header(name: name))
        part.append(Data(value.utf8))
        part.append(newline)
        return part
    }

    private static func header(name: String, fileName: String? = nil, contentType: String? = nil) -> Data {
        var text = "Content-Disposition: form-data; name=\"\(name)\""
        if let fileName {
            // Кавычка в имени закрыла бы заголовок, и сервер не понял бы файл.
            let safe = fileName.replacingOccurrences(of: "\"", with: "")
            text += "; filename=\"\(safe)\""
        }
        text += "\r\n"
        if let contentType {
            text += "Content-Type: \(contentType)\r\n"
        }
        text += "\r\n"
        return Data(text.utf8)
    }
}
