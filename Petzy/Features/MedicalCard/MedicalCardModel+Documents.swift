import Foundation

extension MedicalCardModel {
    /// Документ из блока «Анализы и заключения» открывается файлом: строка,
    /// которая ничего не делает, хуже её отсутствия. Файл тот же, что и на
    /// вкладке «Документы», поэтому и имя собирается там же.
    func openDocument(id: String, title: String, serverName: String?) async {
        do {
            let loaded = try await DocumentsAPI.file(client, id: id)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                DocumentsModel.fileName(title: title, serverName: loaded.fileName ?? serverName)
            )
            try loaded.data.write(to: url, options: .atomic)
            documentFile = url
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }
}
