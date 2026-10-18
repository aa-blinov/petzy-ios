import Foundation
@testable import Petzy
import Testing

/// Выгрузка записей таблицей: файл, а не разобранный ответ, поэтому здесь
/// проверяется и тело, и имя файла из заголовка сервера.
@MainActor
@Suite("Выгрузка записей")
struct ExportTests {
    private func stubExport(body: String, fileName: String? = "рекс_вес_20261018_1317.csv") {
        var headers = ["Content-Type": "text/csv"]
        if let fileName {
            let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
            headers["Content-Disposition"] = "attachment; filename*=UTF-8''" + encoded
        }
        StubURLProtocol.stub(status: 200, data: Data(body.utf8), headers: headers)
    }

    @Test("Файл приходит целиком вместе с именем из заголовка")
    func fileIsDownloadedWithItsName() async throws {
        StubURLProtocol.reset()
        stubExport(body: "Дата и время,Вес (кг)\n04.10.2026 11:00,\"29,3\"")
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        let file = await model.export(type: "weight", format: "csv")

        let url = try #require(file, "файл не пришёл: \(model.exportErrorText ?? "без ошибки")")
        #expect(StubURLProtocol.requestedPaths == ["/api/export/weight/csv"], "выгрузка пошла не туда")
        let query = StubURLProtocol.requests.last?.url?.query ?? ""
        #expect(query.contains("pet_id=pet-1"), "питомец не ушёл на сервер: \(query)")
        #expect(query.contains("tz="), "часовой пояс не ушёл: времена в файле пересчитались бы по серверу")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("29,3"), "тело файла пустое или искажённое")
        #expect(
            file?.lastPathComponent.contains("вес") == true,
            "имя файла не из заголовка: \(file?.lastPathComponent ?? "")"
        )
    }

    /// Ответ без имени файла тоже надо сохранить: сервер вправе его не
    /// прислать, и человек получит «запись.csv» вместо пустого экрана.
    @Test("Без имени файла сохраняется под своим")
    func missingNameGetsOwnName() async {
        StubURLProtocol.reset()
        stubExport(body: "Дата и время\n04.10.2026 11:00", fileName: nil)
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        let file = await model.export(type: "weight", format: "csv")

        #expect(
            file?.lastPathComponent == "записи.csv",
            "файл сохранился под невнятным именем: \(file?.lastPathComponent ?? "нет")"
        )
    }

    /// Пустой ответ от сервера об ошибке должен дойти по-русски от него, а не
    /// как «неизвестная ошибка».
    @Test("Ошибка выгрузки показывается")
    func exportErrorIsShown() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 404, json: ["error": "Нет записей для выгрузки"])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        let file = await model.export(type: "weight", format: "csv")

        #expect(file == nil)
        #expect(model.exportErrorText == "Нет записей для выгрузки")
    }

    @Test("Без выбранного питомца идти некуда")
    func exportWithoutPetDoesNothing() async {
        StubURLProtocol.reset()
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())

        let file = await model.export(type: "weight", format: "csv")

        #expect(file == nil)
        #expect(StubURLProtocol.requests.isEmpty, "запрос ушёл без питомца")
    }
}
