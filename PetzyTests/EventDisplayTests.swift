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

/// Подпись под графиком говорит словами то, что картинка не говорит. При
/// нулевом изменении «плюс 0,00» не говорит ничего, а уровень должен
/// выглядеть так же, как на оси.
@Suite("Подпись под графиком")
struct TrendSummaryTests {
    private func bucket(_ value: Double) -> EventStatsBucket {
        EventStatsBucket(start: "2026-10-01", label: "1 окт.", value: value)
    }

    @Test("Изменение читается словами")
    func changeIsSpelled() {
        let text = EventStats.trendSummary([bucket(28.4), bucket(29.3)], isValued: true)

        #expect(text == "За период: с 28,4 до 29,3, плюс 0,9")
    }

    @Test("Без изменений подпись не врёт про плюс")
    func noChangeIsNotAPlus() {
        let text = EventStats.trendSummary([bucket(250), bucket(250)], isValued: true)

        #expect(text == "За период: без изменений")
    }

    /// Уровень на подписи и на оси должен выглядеть одинаково: «250,0» и
    /// «250,00» рядом читаются как разные числа.
    @Test("Уровень с одним знаком, как на оси")
    func levelMatchesTheAxis() {
        let text = EventStats.trendSummary([bucket(250), bucket(251)], isValued: true)

        #expect(text.contains("с 250,0 до 251,0"))
    }

    @Test("Счётный тип говорит о количестве")
    func countTypeCountsRecords() {
        let text = EventStats.trendSummary([bucket(3), bucket(2)], isValued: false)

        #expect(text == "За период: 5 записей")
    }
}
