import Foundation
@testable import Petzy
import Testing

/// Форма записи. Здесь проверяется то, что человек набрал, до того как запрос
/// уйдёт на сервер: пустое обязательное поле и число не в том диапазоне
/// сервер вернёт ошибкой, но человек увидит её уже после отправки.
@Suite("Форма записи")
struct EventDraftTests {
    private func numberField(
        name: String = "weight",
        label: String = "Вес (кг)",
        required: Bool = true,
        min: Double? = 0,
        max: Double? = 100
    ) -> EventFieldInfo {
        EventFieldInfo(
            name: name,
            label: label,
            type: "number",
            required: required,
            min: min,
            max: max,
            options: nil
        )
    }

    private func textField(
        name: String = "food",
        label: String = "Корм",
        required: Bool = false
    ) -> EventFieldInfo {
        EventFieldInfo(
            name: name,
            label: label,
            type: "text",
            required: required,
            min: nil,
            max: nil,
            options: nil
        )
    }

    private func typeInfo(_ fields: [EventFieldInfo]) -> EventTypeInfo {
        EventTypeInfo(key: "weight", label: "Вес", icon: "scale", category: "health", fields: fields)
    }

    private func draft(_ fields: [EventFieldInfo], _ values: [String: String]) -> EventDraft {
        EventDraft(
            type: typeInfo(fields),
            values: values,
            comment: "",
            date: "2026-10-18",
            time: "12:00"
        )
    }

    @Test("Пустое обязательное поле не даёт сохранить")
    func requiredFieldMustBeFilled() {
        let one = draft([numberField()], [:])

        let problem = one.problem

        #expect(problem != nil)
        #expect(problem?.contains("Вес (кг)") == true, "в тексте нет названия поля: \(problem ?? "")")
    }

    @Test("Заполненное обязательное поле претензий не вызывает")
    func filledFieldIsAccepted() {
        let one = draft([numberField()], ["weight": "29,3"])

        #expect(one.problem == nil)
    }

    @Test("Число вне диапазона не даёт сохранить")
    func numberOutOfRange() {
        let tooMuch = draft([numberField(max: 40)], ["weight": "41"])
        let tooLittle = draft([numberField(min: 5)], ["weight": "4"])

        #expect(tooMuch.problem != nil)
        #expect(tooLittle.problem != nil)
    }

    @Test("Границы диапазона в него входят")
    func boundsAreIncluded() {
        let one = draft([numberField(min: 5, max: 40)], ["weight": "5"])
        let two = draft([numberField(min: 5, max: 40)], ["weight": "40"])

        #expect(one.problem == nil)
        #expect(two.problem == nil)
    }

    @Test("Запятая вместо точки это нормально, так пишут в русской записи")
    func commaDecimalIsAccepted() {
        let one = draft([numberField()], ["weight": "29,3"])

        #expect(one.problem == nil)
        #expect(one.encodedFields["weight"] == .number(29.3))
    }

    @Test("Слово в числовом поле не даёт сохранить")
    func textInNumberFieldIsRejected() {
        let one = draft([numberField()], ["weight": "много"])

        #expect(one.problem != nil)
    }

    @Test("Пустое необязательное поле в запрос не попадает")
    func emptyOptionalFieldIsOmitted() {
        let one = draft([numberField(), textField()], ["weight": "29,3"])

        #expect(one.encodedFields.count == 1)
        #expect(one.encodedFields["food"] == nil)
    }

    @Test("Текстовое поле уходит текстом")
    func textFieldStaysText() {
        let one = draft([numberField(), textField()], ["weight": "29,3", "food": "Монж"])

        #expect(one.encodedFields["food"] == .text("Монж"))
    }

    @Test("Дата и время из формы идут в запрос в том же виде, что и у записи")
    func dateAndTimeAreKeptAsTyped() {
        let one = draft([numberField()], ["weight": "29,3"])

        #expect(one.date == "2026-10-18")
        #expect(one.time == "12:00")
    }

    /// Правка открывается на значениях самой записи. Если число вернётся в поле
    /// точкой, а не запятой, человек увидит «29.3» вместо «29,3» и решит, что
    /// запись испортилась.
    @Test("Черновик правки заполняется из самой записи")
    func draftIsBuiltFromEvent() {
        let event = PetEvent(
            id: "e-1",
            type: "weight",
            dateTime: "2026-10-04 11:00",
            comment: "после прогулки",
            fields: ["weight": .number(29.3), "food": .text("Монж")],
            isDeleted: false
        )

        let one = EventDraft(event: event, type: typeInfo([numberField(), textField()]))

        #expect(one.values["weight"] == "29,3", "число вернулось в поле в чужом виде: \(one.values)")
        #expect(one.values["food"] == "Монж")
        #expect(one.date == "2026-10-04")
        #expect(one.time == "11:00")
        #expect(one.comment == "после прогулки")
        #expect(one.problem == nil, "правка открылась бы с претензией: \(one.problem ?? "")")
    }
}
