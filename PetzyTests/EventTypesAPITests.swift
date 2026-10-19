import Foundation
@testable import Petzy
import Testing

/// Свои типы записей: человек заводит свой тип со своими полями. Ключ и цвет
/// сервер назначает сам, а встроенные типы менять нельзя.
@MainActor
@Suite("Свои типы записей: контракт")
struct EventTypesAPITests {
    private func draft() -> CustomTypeDraft {
        var field = CustomFieldDraft()
        field.name = "duration_min"
        field.label = "Длительность (мин)"
        field.kind = .number
        field.required = true
        var type = CustomTypeDraft()
        type.label = "Выгул на поводке"
        type.fields = [field]
        return type
    }

    /// Ключ и цвет назначает сервер: отправлять их нельзя, ключа у нового типа
    /// ещё не существует.
    @Test("Создание уходит с названием, значком, цветом и полями")
    func createSendsDraft() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "key": "custom_df58831412", "label": "Выгул на поводке", "icon": "paw", "color": "blue",
            "is_builtin": false, "category": NSNull(), "created_by": "demo",
            "fields": [[
                "name": "duration_min", "label": "Длительность (мин)", "type": "number",
                "required": true, "options": NSNull(), "min": 0.0, "max": NSNull()
            ]],
            "chart": ["kind": "count"]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let created = try await EventTypesAPI.create(client, draft: draft())

        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/api/event-types")
        let body = TestSupport.body(of: request)
        #expect(body["label"] as? String == "Выгул на поводке")
        #expect(body["key"] == nil, "ключ у нового типа сервер назначает сам")
        let fields = body["fields"] as? [[String: Any]]
        #expect(fields?.first?["name"] as? String == "duration_min")
        #expect(fields?.first?["type"] as? String == "number")
        #expect(fields?.first?["required"] as? Bool == true)
        #expect(created.key == "custom_df58831412")
        #expect(created.category == nil, "свой тип приходит без категории")
    }

    /// Варианты выбора уходят списком объектов, а не строкой: иначе сервер не
    /// знает, что подпись и значение это разные вещи.
    @Test("Варианты выбора уходят значениями и подписями")
    func optionsGoAsPairs() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "key": "custom_1", "label": "Сон", "icon": "moon", "color": "purple",
            "is_builtin": false, "category": NSNull(), "created_by": "demo",
            "fields": [[
                "name": "quality", "label": "Качество", "type": "select",
                "required": false, "options": [["value": "good", "text": "Хороший"]],
                "min": NSNull(), "max": NSNull()
            ]],
            "chart": ["kind": "count"]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var type = CustomTypeDraft()
        type.label = "Сон"
        var field = CustomFieldDraft()
        field.name = "quality"
        field.label = "Качество"
        field.kind = .select
        field.options = "good=Хороший"
        type.fields = [field]

        _ = try await EventTypesAPI.create(client, draft: type)

        let fields = TestSupport.body(of: StubURLProtocol.requests.first)["fields"] as? [[String: Any]]
        let options = fields?.first?["options"] as? [[String: String]]
        #expect(options == [["value": "good", "text": "Хороший"]])
    }

    /// Удаление спрашивает, сколько записей исчезнет, и только потом удаляет:
    /// назад эти записи уже не вернуть.
    @Test("Превью удаления считает записи, само удаление уходит отдельным запросом")
    func deleteAsksBeforeItDeletes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "", "events_count": 3])
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Тип события удалён"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let count = try await EventTypesAPI.countBeforeDelete(client, key: "custom_1")
        try await EventTypesAPI.delete(client, key: "custom_1")

        #expect(count == 3)
        #expect(StubURLProtocol.requests.first?.url?.query?.contains("preview=true") == true)
        #expect(StubURLProtocol.requests.last?.url?.absoluteString.contains("preview") == false)
        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
        #expect(StubURLProtocol.requestedPaths == ["/api/event-types/custom_1", "/api/event-types/custom_1"])
    }

    /// Свои типы отличаются `category: null`, и в форме записи они идут
    /// последними, в группе «Свои».
    @Test("Список справочника отличает свои типы по category")
    func listKeepsCategoryNull() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["event_types": [
            ["key": "weight", "label": "Вес", "icon": "scale", "category": "health", "fields": []],
            ["key": "custom_1", "label": "Выгул на поводке", "icon": "paw", "category": NSNull(), "fields": []]
        ]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let response = try await client.get("/api/event-types", as: EventTypesResponse.self)

        #expect(response.eventTypes.first?.category == "health")
        #expect(response.eventTypes.last?.category == nil)
        #expect(EventCatalog.groups(response.eventTypes).last?.key == "own")
    }
}
