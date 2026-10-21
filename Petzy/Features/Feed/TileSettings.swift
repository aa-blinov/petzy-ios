import Foundation

/// Что на «+» у этого питомца и в каком порядке. Поле питомца
/// (`tiles_settings`), своё у каждого: у кошки лоток, у рыбы смена воды.
///
/// Отсутствие записи в `order` значит «как в каталоге», отсутствие в
/// `visible` — «по умолчанию». Так питомец без сохранённой настройки просто
/// показывает свой набор, и пустое умолчание остаётся пустым.
struct TileSettings: Codable, Sendable, Equatable {
    var order: [String] = []
    var visible: [String: Bool] = [:]

    /// Восемь типов, которые на «+» были всегда.
    static let originals = [
        "feeding", "weight", "defecation", "litter", "asthma", "eye_drops", "ear_cleaning", "tooth_brushing"
    ]

    /// Показывать ли тип на «+». Сказанное человеком важнее умолчания, а
    /// умолчание — это восемь изначальных типов и свои типы семьи: всё, что
    /// добавили в каталог позже, само не появляется, иначе «+» забился бы
    /// десятками кнопок, которых никто не просил.
    func isShown(_ id: String) -> Bool {
        if let said = visible[id] {
            return said
        }
        return Self.originals.contains(id) || id.hasPrefix("custom_")
    }

    /// Порядок: сначала поставленные человеком, потом остальные — в том
    /// порядке, в каком пришли. Устойчиво: два непереставленных типа не
    /// меняются местами.
    func ordered(_ ids: [String]) -> [String] {
        ids.enumerated()
            .sorted { left, right in
                let leftRank = rank(left.element)
                let rightRank = rank(right.element)
                return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
            }
            .map(\.element)
    }

    private func rank(_ id: String) -> Int {
        order.firstIndex(of: id) ?? Int.max
    }

    enum CodingKeys: String, CodingKey {
        case order, visible
    }
}
