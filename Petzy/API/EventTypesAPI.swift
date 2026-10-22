import Foundation

/// Разговор с сервером о типах записей `/api/event-types`. Встроенные типы
/// приходят тем же справочником, но менять их нельзя: правка и удаление
/// принадлежат автору своего типа, и то по ключу `custom_`.
enum EventTypesAPI {
    /// Создать свой тип. Ключ и цвет сервер назначает сам: у нового типа ключа
    /// ещё нет, а цвет из набора сервера человек на телефоне не выбирает.
    static func create(_ client: APIClient, draft: CustomTypeDraft) async throws -> EventTypeInfo {
        try await client.post("/api/event-types", body: TypeBody(draft: draft))
    }

    /// Правка своего типа. Встроенный сервер не примет, а чужой откажет с 403:
    /// поэтому в списке правятся только свои.
    static func update(
        _ client: APIClient,
        key: String,
        draft: CustomTypeDraft
    ) async throws -> EventTypeInfo {
        try await client.put(
            "/api/event-types/" + AppModel.query(key),
            body: TypeBody(draft: draft)
        )
    }

    /// Сколько записей исчезнет вместе с типом. Спрашивается до удаления:
    /// записи удаляются жёстко, и назад их не вернуть.
    static func countBeforeDelete(_ client: APIClient, key: String) async throws -> Int {
        let response: DeletePreviewDTO = try await client.delete(
            "/api/event-types/" + AppModel.query(key) + "?preview=true",
            as: DeletePreviewDTO.self
        )
        return response.eventsCount
    }

    static func delete(_ client: APIClient, key: String) async throws {
        try await client.delete("/api/event-types/" + AppModel.query(key))
    }
}

// MARK: - Тела запросов

private struct TypeBody: Encodable {
    let label: String
    let icon: String
    let color: String
    let fields: [FieldBody]
    let chart: ChartBody

    init(draft: CustomTypeDraft) {
        label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        icon = draft.icon.rawValue
        color = draft.color.rawValue
        fields = draft.filledFields.map(FieldBody.init(draft:))
        chart = ChartBody(
            kind: draft.chart.kind.rawValue,
            // У счётного графика поля нет, и сервер его не примет: пустая
            // строка означала бы «считай по полю без названия».
            valueField: draft.chart.kind == .value ? draft.chart.field : nil,
            valueLabel: draft.chart.kind == .value ? draft.chart.valueLabel : nil
        )
    }
}

private struct FieldBody: Encodable {
    let name: String
    let label: String
    let type: String
    let required: Bool
    /// Пустой список вариантов уходит `null`, а не `[]`: сервер отличает поле
    /// выбора без вариантов от обычного текстового.
    let options: [[String: String]]?

    init(draft: CustomFieldDraft) {
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        type = draft.kind.rawValue
        required = draft.required
        options = draft.kind == .select ? CustomFieldDraft.parseOptions(draft.options) : nil
    }
}

private struct ChartBody: Encodable {
    let kind: String
    let valueField: String?
    let valueLabel: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case valueField = "value_field"
        case valueLabel = "value_label"
    }
}

// MARK: - Разобранный ответ

private struct DeletePreviewDTO: Decodable {
    let eventsCount: Int

    enum CodingKeys: String, CodingKey {
        case eventsCount = "events_count"
    }
}

/// Обёртки ответов: у сервера список приходит под именем ключа, и это
/// единственное, что здесь есть.
struct UsedTypesResponse: Decodable, Sendable {
    let types: [String]
}

struct EventTypesResponse: Decodable, Sendable {
    let eventTypes: [EventTypeInfo]

    enum CodingKeys: String, CodingKey {
        case eventTypes = "event_types"
    }
}
