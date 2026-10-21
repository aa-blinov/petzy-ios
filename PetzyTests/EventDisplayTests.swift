import Foundation
@testable import Petzy
import Testing

/// Значения записи показываются в порядке полей типа, а не по алфавиту
/// внутренних имён: главное значение, которое человек вносит первым, должно
/// стоять первым, а не вторым.
@MainActor
@Suite("Порядок значений записи")
struct EventFieldOrderTests {
    private func model() async -> AppModel {
        let defaults = TestSupport.makeDefaults()
        return await TestSupport.makeModel(defaults: defaults)
    }

    private func field(_ name: String, _ label: String) -> EventFieldInfo {
        EventFieldInfo(
            name: name,
            label: label,
            type: "number",
            required: false,
            min: nil,
            max: nil,
            options: nil
        )
    }

    @Test("Значения идут в порядке полей типа")
    func valuesFollowTypeOrder() async {
        let model = await model()
        model.eventTypes = ["weight": EventTypeInfo(
            key: "weight",
            label: "Вес",
            icon: "scale",
            category: "health",
            fields: [field("weight", "Вес (кг)"), field("kind", "Вид корма")],
            chart: nil
        )]

        let shown = model.fieldValues(["kind": .text("Обычный"), "weight": .number(29.3)], of: "weight")

        #expect(shown.map(\.label) == ["Вес (кг)", "Вид корма"])
        #expect(shown.map(\.value) == ["29,3", "Обычный"])
    }

    /// Поле, которого нет в справочнике, терять нельзя: запись пришла с
    /// данными, а приложение их покажет как есть.
    @Test("Неизвестное поле дописывается в конец")
    func unknownFieldKeepsItsValue() async {
        let model = await model()
        model.eventTypes = ["weight": EventTypeInfo(
            key: "weight",
            label: "Вес",
            icon: "scale",
            category: "health",
            fields: [field("weight", "Вес (кг)")],
            chart: nil
        )]

        let shown = model.fieldValues(["weight": .number(29.3), "mystery": .text("что-то")], of: "weight")

        #expect(shown.map(\.label) == ["Вес (кг)", "mystery"])
    }
}
