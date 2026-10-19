import Foundation
@testable import Petzy
import Testing

/// Имя поля получается из подписи само: сервер требует латиницу, а человек
/// пишет по-русски, и без перевода пришлось бы выдумывать имя вручную.
@Suite("Свои типы записей: форма")
struct CustomTypeFormTests {
    @Test("Подпись «Длительность (мин)» становится именем поля")
    func nameIsMadeFromLabel() {
        #expect(FieldName.from("Длительность (мин)", existing: []) == "dlitelnost_min")
        #expect(FieldName.from("Вес", existing: []) == "ves")
    }

    /// Одинаковые подписи есть у разных полей, и имя у них должно разойтись:
    /// иначе второе поле затёрло бы первое в записях.
    @Test("Одинаковые подписи получают разные имена")
    func duplicateLabelsGetDifferentNames() {
        let first = FieldName.from("Корм", existing: [])
        let second = FieldName.from("Корм", existing: [first])

        #expect(first == "korm")
        #expect(second == "korm_2")
    }

    @Test("Подпись без букв всё равно даёт допустимое имя")
    func labelWithoutLettersStillHasName() {
        #expect(FieldName.from("5 кг", existing: []) == "field_5_kg")
        #expect(FieldName.from("", existing: []) == "field")
    }

    @Test("Пустая форма не уходит на сервер")
    func emptyTypeIsNotSent() {
        var draft = CustomTypeDraft()
        draft.label = "  "

        #expect(CustomTypeDraft.problem(draft) == "Введите название типа")

        draft.label = "Выгул"
        #expect(CustomTypeDraft.problem(draft) == "Добавьте хотя бы одно поле")
    }

    @Test("Тип без названия поля и у выбора без вариантов не проходит")
    func fieldsAreChecked() {
        var draft = CustomTypeDraft()
        draft.label = "Выгул"
        var field = CustomFieldDraft()
        field.label = "Настроение"
        field.name = "nastroenie"
        field.kind = .select
        draft.fields = [field]

        #expect(CustomTypeDraft.problem(draft) == "Поле 1: для выбора нужны варианты, по одному в строке")

        field.options = "грустно\nвесело"
        draft.fields = [field]
        #expect(CustomTypeDraft.problem(draft) == nil)
    }

    /// Имена записи сервер оставил за собой: такое поле он не примет, а отказ
    /// придёт уже после отправки.
    @Test("Служебное имя поля не проходит")
    func reservedFieldNameIsRejected() {
        var draft = CustomTypeDraft()
        draft.label = "Выгул"
        var field = CustomFieldDraft()
        field.label = "Дата"
        field.name = "date"
        draft.fields = [field]

        #expect(CustomTypeDraft.problem(draft) == "Поле 1: имя date сервер оставил за собой")
    }

    /// График по величине без выбранного числового поля сервер не примет, и
    /// график в истории был бы пустым.
    @Test("График по величине требует числовое поле")
    func valueChartNeedsNumericField() {
        var draft = CustomTypeDraft()
        draft.label = "Выгул"
        var field = CustomFieldDraft()
        field.label = "Длительность"
        field.name = "dlitelnost"
        field.kind = .number
        draft.fields = [field]
        draft.chart = CustomChart(kind: .value, field: "", valueLabel: "Минут")

        #expect(CustomTypeDraft.problem(draft) == "Выберите числовое поле для графика")

        draft.chart.field = "dlitelnost"
        #expect(CustomTypeDraft.problem(draft) == nil)
    }

    @Test("Варианты выбора разбираются в значения и подписи")
    func optionsAreParsed() {
        let pairs = CustomFieldDraft.parseOptions("good=Хороший\nПлохо\n")

        #expect(pairs.count == 2)
        #expect(pairs[0]["value"] == "good")
        #expect(pairs[0]["text"] == "Хороший")
        #expect(pairs[1]["value"] == "Плохо")
        #expect(pairs[1]["text"] == "Плохо")
    }

    /// Человек добавил поле и оставил его пустым, чтобы заполнить потом. В
    /// запрос такое поле попадать не должно: сервер отвечает 422 на пустое имя,
    /// а отказ приходит после отправки.
    @Test("Пустое поле в запрос не уходит")
    func emptyFieldIsNotSent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 201, json: [
            "key": "custom_1", "label": "Выгул", "icon": "paw", "color": "blue",
            "category": NSNull(), "fields": [], "chart": ["kind": "count"]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())
        var draft = CustomTypeDraft()
        draft.label = "Выгул"
        var field = CustomFieldDraft()
        field.label = "Длительность"
        field.name = "dlitelnost"
        draft.fields = [field, CustomFieldDraft()]

        _ = try await EventTypesAPI.create(client, draft: draft)

        let body = TestSupport.body(of: StubURLProtocol.requests.first)
        let fields = body["fields"] as? [[String: Any]]
        #expect(fields?.count == 1, "пустое поле ушло на сервер и он его отвергнет")
        #expect(fields?.first?["name"] as? String == "dlitelnost")
    }

    /// Правка открывается тем, что уже заведено. Если что-то потеряется, то
    /// сохранение без единой правки сотрёт его у человека.
    @Test("Правка открывается с тем, что уже заведено")
    func editStartsFromSavedType() {
        let saved = EventTypeInfo(
            key: "custom_1",
            label: "Выгул",
            icon: "moon",
            category: nil,
            fields: [EventFieldInfo(
                name: "dlitelnost",
                label: "Длительность",
                type: "number",
                required: true,
                min: nil,
                max: nil,
                options: nil
            )],
            chart: EventChart(kind: "value", valueField: "dlitelnost", valueLabel: "Минут")
        )

        let draft = CustomTypeDraft.from(saved)

        #expect(draft.key == "custom_1")
        #expect(draft.icon == .moon)
        #expect(draft.fields.map(\.name) == ["dlitelnost"])
        #expect(draft.fields.first?.required == true)
        #expect(draft.chart.kind == .value)
        #expect(draft.chart.field == "dlitelnost")
        #expect(draft.chart.valueLabel == "Минут")
        #expect(CustomTypeDraft.problem(draft) == nil, "сохранение без правок должно проходить")
    }

    /// Свой тип приходит без категории, и встроенный значок не из нашего списка:
    /// на правке это не должно выглядеть как пустое поле.
    @Test("Чужое имя значка и цвета не ломает правку")
    func unknownIconFallsBack() {
        let saved = EventTypeInfo(
            key: "custom_2",
            label: "Сон",
            icon: "zzz-unknown",
            category: nil,
            fields: [EventFieldInfo(
                name: "chas",
                label: "Часы",
                type: "number",
                required: false,
                min: nil,
                max: nil,
                options: nil
            )],
            chart: nil
        )

        let draft = CustomTypeDraft.from(saved)

        #expect(draft.icon == .paw)
        #expect(draft.color == .blue)
        #expect(draft.chart.kind == .count)
    }
}
