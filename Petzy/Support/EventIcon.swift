import Foundation

/// Значки типов записей приходят именами из набора Lucide, которым нарисован веб.
/// Это не SF Symbols, и `Image(systemName:)` на таком имени молча рисует пустоту:
/// значок не появляется, ошибки нет. Поэтому имена переводятся здесь.
enum EventIcon {
    static func symbol(for lucideName: String?) -> String {
        guard let lucideName else { return "circle" }
        return table[lucideName] ?? "circle"
    }

    /// Всё, что приходит от сервера на сейчас. Пополняется новыми типами записей.
    private static let table: [String: String] = [
        "bone": "bandage",
        "droplet": "drop",
        "ear": "ear",
        "eye": "eye",
        "gift": "gift",
        "heart": "heart",
        "paw": "pawprint.fill",
        "scale": "scalemass",
        "shovel": "hands.sparkles",
        "smile": "face.smiling",
        "star": "star",
        "sun": "sun.max",
        "thermometer": "thermometer",
        "toilet": "toilet",
        "toothbrush": "mouth",
        "utensils": "fork.knife",
        "wind": "wind",
        "zap": "bolt.fill"
    ]
}
