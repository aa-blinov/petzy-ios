import Foundation

/// Состояние экрана «Значения по умолчанию». Правки копятся в `values`, а
/// сервер получает набор целиком: он заменяет его, а не дополняет.
@MainActor
@Observable
final class FormDefaultsModel {
    /// Что человек набрал: ключ типа, внутри имена полей.
    private(set) var values: FormDefaults
    private(set) var isSaving = false
    var errorText: String?
    var notice: String?

    private let client: APIClient
    private let petID: String
    private let app: AppModel

    init(client: APIClient, petID: String, defaults: FormDefaults, app: AppModel) {
        self.client = client
        self.petID = petID
        self.app = app
        values = defaults
    }

    func value(_ field: EventFieldInfo, of type: String) -> String {
        values[type]?[field.name] ?? ""
    }

    func set(_ text: String, for field: EventFieldInfo, of type: String) {
        var fields = values[type] ?? [:]
        // Пустое значение значит «убери»: сервер принимает только заполненное,
        // а пустая строка в наборе осталась бы висеть навсегда.
        if text.isEmpty {
            fields.removeValue(forKey: field.name)
        } else {
            fields[field.name] = text
        }
        if fields.isEmpty {
            values.removeValue(forKey: type)
        } else {
            values[type] = fields
        }
    }

    /// Типы, у которых есть поля и для которых есть что набирать. Типы без
    /// полей показывать незачем: набирать там нечего.
    func types(_ catalog: [EventTypeInfo]) -> [EventTypeInfo] {
        catalog.filter { !$0.fields.isEmpty }
    }

    @discardableResult
    func save() async -> Bool {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            let saved = try await PetsAPI.saveFormDefaults(client, id: petID, defaults: values)
            values = saved
            // Форма записи читает значения из модели, и без этого новая запись
            // открылась бы по-старому.
            app.formDefaults = saved
            notice = "Значения сохранены"
            return true
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
