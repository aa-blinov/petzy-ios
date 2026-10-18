import Foundation
@testable import Petzy
import Testing

/// Загрузка файла идёт multipart'ом: сервер ждёт поля формы и сам файл в
/// теле. Проверяется не только «файл уехал», но и что запрос собран верно:
/// граница, имя файла, тип и заголовок `Content-Type` с той же границей.
@Suite("HTTP: тело с файлом")
struct MultipartTests {
    @Test("Тело собирается из полей и файла с общей границей")
    func bodyHasFieldsAndFile() {
        var body = MultipartBody()
        body.addField(name: "pet_id", value: "p1")
        body.addField(name: "title", value: "Анализ крови")
        body.addFile(name: "file", fileName: "анализ.pdf", contentType: "application/pdf", data: Data("%PDF-1.7".utf8))

        let text = String(data: body.data, encoding: .utf8) ?? ""

        #expect(text.contains("Content-Disposition: form-data; name=\"pet_id\""))
        #expect(text.contains("Анализ крови"))
        #expect(text.contains("filename=\"анализ.pdf\""))
        #expect(text.contains("Content-Type: application/pdf"))
        #expect(text.contains("%PDF-1.7"))
    }

    @Test("Граница в теле и в заголовке одна и та же")
    func boundaryMatchesHeader() {
        var body = MultipartBody()
        body.addField(name: "pet_id", value: "p1")

        #expect(body.contentType == "multipart/form-data; boundary=\(body.boundary)")
        #expect((String(data: body.data, encoding: .utf8) ?? "").contains("--\(body.boundary)"))
    }

    @Test("Кавычка в имени не ломает заголовок, кириллица остаётся")
    func cyrillicFileNameIsSafe() {
        var body = MultipartBody()
        body.addFile(
            name: "file",
            fileName: "паспорт, прививки \"2025\".pdf",
            contentType: "application/pdf",
            data: Data()
        )

        let text = String(data: body.data, encoding: .utf8) ?? ""

        // Сервер разбирает имя как строку в кавычках: кавычка внутри закрыла бы
        // её, и имя отбросилось бы до хвоста. Кириллица при этом законна.
        #expect(text.contains("filename=\"паспорт, прививки 2025.pdf\""))
        #expect(text.contains("Content-Type: application/pdf"))
    }

    @Test("Поле без значения не отправляется")
    func emptyFieldIsSkipped() {
        var body = MultipartBody()
        body.addField(name: "note", value: "")
        body.addField(name: "expires_at", value: "2027-04-21")

        let text = String(data: body.data, encoding: .utf8) ?? ""

        #expect(!text.contains("name=\"note\""))
        #expect(text.contains("name=\"expires_at\""))
    }

    @Test("Пустое тело не отправляется: запрос без файла сервер не примет")
    func emptyBodyHasNoContent() {
        var body = MultipartBody()

        #expect(body.data.isEmpty)
        #expect(body.contentType == nil)
    }
}
