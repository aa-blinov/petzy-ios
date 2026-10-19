import Foundation
@testable import Petzy
import Testing

/// Экран «Свои типы записей»: список, создание, правка и удаление. Ключевое
/// здесь — встроенные типы в списке не правятся, а удаление спрашивает, сколько
/// записей пропадёт, и только потом удаляет.
@MainActor
@Suite("Экран «Свои типы записей»", .serialized)
struct CustomTypesModelTests {
    private func model() async -> CustomTypesModel {
        let session = StubURLProtocol.makeSession()
        return await CustomTypesModel(client: MedicationsTests.client(session: session))
    }

    private func catalog() -> [String: Any] {
        ["event_types": [
            ["key": "weight", "label": "Вес", "icon": "scale", "category": "health", "fields": []],
            ["key": "custom_1", "label": "Выгул", "icon": "paw", "color": "blue",
             "category": NSNull(), "is_builtin": false,
             "fields": [["name": "dlitelnost", "label": "Длительность", "type": "number",
                         "required": true, "options": NSNull(), "min": NSNull(), "max": NSNull()]],
             "chart": ["kind": "value", "value_field": "dlitelnost", "value_label": "Минут"]]
        ]]
    }

    /// Встроенный тип на этом экране менять нельзя: правку он примет только
    /// автор, а в списке его не должно быть вовсе.
    @Test("В списке только свои типы")
    func listKeepsOwnTypesOnly() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: catalog())
        let model = await model()

        await model.load()

        #expect(model.types.map(\.key) == ["custom_1"])
        #expect(model.types.first?.fields.first?.label == "Длительность")
    }

    /// Пустая форма не должна уходить на сервер: он ответит 422, а человек
    /// увидит отказ вместо вопроса.
    @Test("Незаполненная форма не уходит")
    func emptyDraftIsNotSent() async {
        StubURLProtocol.reset()
        let model = await model()

        let saved = await model.save(CustomTypeDraft())

        #expect(saved == false)
        #expect(model.errorText == "Введите название типа")
        #expect(StubURLProtocol.requests.isEmpty, "пустая форма ушла на сервер")
    }

    /// Созданный тип обязан появиться в списке сам: без перечитывания человек
    /// решил бы, что тип не создался, и завёл бы второй.
    @Test("После сохранения тип появляется в списке")
    func savedTypeAppearsInList() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "key": "custom_1", "label": "Выгул", "icon": "paw", "color": "blue",
            "category": NSNull(), "is_builtin": false, "fields": [], "chart": ["kind": "count"]
        ])
        StubURLProtocol.stub(status: 200, json: catalog())
        let model = await model()

        let saved = await model.save(draft())

        #expect(saved)
        #expect(StubURLProtocol.requests.first?.httpMethod == "POST")
        #expect(model.types.map(\.key) == ["custom_1"])
        #expect(model.errorText == nil)
    }

    /// Правка уходит `PUT` по ключу типа, а не `POST`: новый тип тут не создаётся.
    @Test("Правка уходит по ключу типа")
    func updateUsesKey() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "key": "custom_1", "label": "Выгул", "icon": "paw", "color": "blue",
            "category": NSNull(), "is_builtin": false, "fields": [], "chart": ["kind": "count"]
        ])
        StubURLProtocol.stub(status: 200, json: catalog())
        let model = await model()
        var existing = draft()
        existing.key = "custom_1"

        let saved = await model.save(existing)

        #expect(saved)
        #expect(StubURLProtocol.requestedPaths.first == "/api/event-types/custom_1")
        #expect(StubURLProtocol.requests.first?.httpMethod == "PUT")
    }

    /// Записи удаляются вместе с типом жёстко. Человек должен увидеть их число
    /// до того, как нажмёт «Удалить».
    @Test("Удаление спрашивает, сколько записей пропадёт")
    func deleteCountsRecordsFirst() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: catalog())
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "", "events_count": 3])
        let model = await model()
        await model.load()

        await model.prepareDelete(model.types.first)
        #expect(model.pendingCount == 3)
        #expect(StubURLProtocol.requestedPaths == ["/api/event-types", "/api/event-types/custom_1"])

        model.cancelDelete()
        #expect(model.pendingCount == nil)
        #expect(StubURLProtocol.requests.count == 2, "отмена удалила тип раньше времени")
    }

    @Test("Удаление убирает тип из списка")
    func deleteRemovesType() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: catalog())
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "", "events_count": 0])
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Тип удалён"])
        let model = await model()
        await model.load()
        await model.prepareDelete(model.types.first)
        // Диалог закрывается раньше, чем срабатывает его кнопка: без этого
        // удаление не знает, что именно удалять, и молча ничего не делает.
        model.cancelDelete()

        await model.deletePending()

        #expect(model.types.isEmpty)
        #expect(StubURLProtocol.requestedPaths == [
            "/api/event-types",
            "/api/event-types/custom_1",
            "/api/event-types/custom_1"
        ])
    }

    /// Тип, у которого есть записи, сервер удалять не даёт: он отвечает отказом
    /// «event_type_has_events». Человек должен узнать об этом до нажатия, а не
    /// после отказа.
    @Test("Тип с записями удалить нельзя, и об этом сказано заранее")
    func typeWithRecordsCannotBeDeleted() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: catalog())
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "", "events_count": 121])
        let model = await model()
        await model.load()

        await model.prepareDelete(model.types.first)

        #expect(model.pendingCount == 121)
        #expect(model.canDelete == false)
    }

    private func draft() -> CustomTypeDraft {
        var field = CustomFieldDraft()
        field.label = "Длительность"
        field.name = "dlitelnost"
        field.kind = .number
        var type = CustomTypeDraft()
        type.label = "Выгул"
        type.fields = [field]
        return type
    }
}
