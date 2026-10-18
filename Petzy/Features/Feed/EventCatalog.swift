import Foundation

/// Выбор типа записи под кнопкой «+». Порядок групп и их названия взяты у
/// веб-приложения, там же и решение, что тип без категории, то есть свой,
/// идёт последним.
enum EventCatalog {
    struct Group: Identifiable {
        let key: String
        let title: String
        let types: [EventTypeInfo]

        var id: String {
            key
        }
    }

    private static let categories: [(key: String, title: String)] = [
        ("food", "Питание и вода"),
        ("excretion", "Туалет"),
        ("health", "Самочувствие и здоровье"),
        ("care", "Уход"),
        ("activity", "Активность"),
        ("habitat", "Среда обитания")
    ]

    /// Пустых групп не бывает: группа без типов на показ не выходит.
    static func groups(_ types: [EventTypeInfo]) -> [Group] {
        var result = categories.compactMap { category -> Group? in
            let inGroup = types.filter { $0.category == category.key }
            guard !inGroup.isEmpty else { return nil }
            return Group(key: category.key, title: category.title, types: inGroup)
        }
        let own = types.filter { $0.category == nil }
        if !own.isEmpty {
            result.append(Group(key: "own", title: "Свои", types: own))
        }
        return result
    }

    /// Поиск идёт по названию типа и по названиям его полей: человек ищет
    /// «вес» и должен найти и «Вес», и «Вес (кг)» у другого типа.
    static func search(_ types: [EventTypeInfo], _ query: String) -> [EventTypeInfo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return types }
        return types.filter { type in
            ([type.label] + type.fields.map(\.label)).contains { $0.lowercased().contains(needle) }
        }
    }
}
