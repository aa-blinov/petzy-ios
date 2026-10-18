import Foundation
@testable import Petzy
import Testing

/// Список типов записи под кнопкой «+». Типов тридцать пять, и человек ищет
/// нужный по названию или по названию поля, поэтому и группы, и поиск
/// проверяются здесь, а не глазами на экране.
@Suite("Каталог типов записи")
struct EventCatalogTests {
    private func type(
        _ key: String,
        _ label: String,
        category: String?,
        fields: [EventFieldInfo] = []
    ) -> EventTypeInfo {
        EventTypeInfo(key: key, label: label, icon: "star", category: category, fields: fields)
    }

    private func numberField(_ name: String, _ label: String) -> EventFieldInfo {
        EventFieldInfo(
            name: name, label: label, type: "number",
            required: true, min: 0, max: 100, options: nil
        )
    }

    @Test("Типы разложены по группам в порядке каталога, свои в последней")
    func groupedByCategory() {
        let types = [
            type("walk", "Прогулка", category: "activity"),
            type("custom_1", "Осмотр у врача", category: nil),
            type("weight", "Вес", category: "health"),
            type("feeding", "Кормление", category: "food"),
            type("custom_2", "Стрижка", category: "care")
        ]

        let groups = EventCatalog.groups(types)

        #expect(
            groups.map(\.title) == ["Питание и вода", "Самочувствие и здоровье", "Уход", "Активность", "Свои"],
            "группы в неверном порядке: \(groups.map(\.title))"
        )
        #expect(groups.first?.types.map(\.key) == ["feeding"])
        #expect(groups.last?.types.map(\.key) == ["custom_1"])
    }

    @Test("Пустая группа на показ не выходит")
    func emptyGroupsAreDropped() {
        let types = [type("weight", "Вес", category: "health")]

        let groups = EventCatalog.groups(types)

        #expect(groups.count == 1)
        #expect(groups.first?.title == "Самочувствие и здоровье")
    }

    @Test("Поиск находит тип и по названию поля")
    func searchLooksAtFieldLabels() {
        let types = [
            type("walk", "Прогулка", category: "activity", fields: [numberField("minutes", "Длительность (мин)")]),
            type("weight", "Вес", category: "health", fields: [numberField("weight", "Вес (кг)")])
        ]

        #expect(EventCatalog.search(types, "вес").map(\.key) == ["weight"])
        #expect(EventCatalog.search(types, "длительность").map(\.key) == ["walk"])
        #expect(EventCatalog.search(types, "минус").isEmpty)
    }
}
