import Foundation

/// Выгрузка записей файлом и типы для её выбора.
///
/// Отдельный файл, потому что здесь живёт всё, что осталось от экрана истории:
/// сам экран веб убрал (лента и есть история), а выгрузка была и осталась
/// строкой в настройках.
extension AppModel {
    /// Типы для выбора в выгрузке: те, записи о которых у питомца есть, и в
    /// порядке справочника. Предлагать «Температуру» питомцу, у которого её
    /// никогда не мерили, незачем.
    var exportTypeOptions: [EventTypeInfo] {
        usedTypes.compactMap { eventTypes[$0] }
    }

    /// Список таких типов. Читается один раз и на питомца: из настроек историю
    /// мог и не открывать, а выбору в выгрузке он нужен всё равно.
    func loadUsedTypes() async {
        guard let petID = selectedPetID, usedTypes.isEmpty else { return }
        do {
            let used = try await client.get(
                "/api/events/used-types?pet_id=" + Self.query(petID),
                as: UsedTypesResponse.self
            )
            usedTypes = used.types
            if eventTypes.isEmpty {
                let types = try await client.get("/api/event-types", as: EventTypesResponse.self)
                eventTypes = Self.index(types.eventTypes)
            }
        } catch {
            if (error as? APIError)?.isAuthProblem == true {
                endSession()
                return
            }
            exportErrorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Скачивает записи файлом и возвращает путь к нему. Файл кладётся во
    /// временную папку приложения и оттуда уходит в системный лист
    /// «Поделиться»: там «Сохранить в файлы», «Отправить себе» и почта врачу.
    func export(type: String, format: String) async -> URL? {
        guard let petID = selectedPetID else { return nil }
        isExporting = true
        exportErrorText = nil
        defer { isExporting = false }
        do {
            let file = try await client.download(
                "/api/export/" + Self.query(type) + "/" + Self.query(format)
                    + "?pet_id=" + Self.query(petID)
                    + "&tz=" + Self.query(TimeZone.current.identifier)
            )
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                file.fileName ?? "записи." + format
            )
            try file.data.write(to: url, options: .atomic)
            exportedFile = url
            return url
        } catch {
            let apiError = error as? APIError
            if apiError?.isAuthProblem == true {
                endSession()
                return nil
            }
            exportErrorText = apiError?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    static func index(_ types: [EventTypeInfo]) -> [String: EventTypeInfo] {
        Dictionary(types.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
