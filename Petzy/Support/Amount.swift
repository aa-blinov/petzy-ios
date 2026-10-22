import Foundation

/// Числа словами: «2,5» вместо «2.5». Запятая — не украшение: числа здесь
/// читают по-русски, и точка в «2.5 мл» выглядит как опечатка. Одно правило на
/// всё приложение, потому что дозировка, вес и остаток показываются одинаково.
enum Amount {
    static func text(_ value: Double) -> String {
        String(format: "%g", value).replacingOccurrences(of: ".", with: ",")
    }
}

/// Склонение по-русски: 1 день, 2 дня, 5 дней. Правило общее для всего
/// приложения, потому что «дней» встречается и в остатке лекарства, и в
/// сроке прививки.
enum Words {
    /// «11 дней» вместе с числом, а не только формой слова.
    static func text(_ count: Int, one: String, few: String, many: String) -> String {
        "\(count) \(pick(count, one: one, few: few, many: many))"
    }

    static func pick(_ count: Int, one: String, few: String, many: String) -> String {
        let rest100 = count % 100
        let rest10 = count % 10
        if (11 ... 14).contains(rest100) {
            return many
        }
        if rest10 == 1 {
            return one
        }
        return (2 ... 4).contains(rest10) ? few : many
    }
}
