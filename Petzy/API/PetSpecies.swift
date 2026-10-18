import Foundation

/// Ключи `species` и их подписи. Список взят из веб-приложения
/// (`frontend/src/utils/species.ts`), чтобы одно и то же животное называлось одинаково.
enum PetSpecies {
    private static let labels: [String: String] = [
        "cat": "Кот",
        "dog": "Собака",
        "rabbit": "Кролик",
        "ferret": "Хорёк",
        "guinea_pig": "Морская свинка",
        "chinchilla": "Шиншилла",
        "rat": "Крыса",
        "hamster": "Хомяк",
        "bird": "Птица",
        "fish": "Рыбка",
        "turtle": "Черепаха",
        "reptile": "Ящерица или змея",
        "other": "Другой питомец",
    ]

    /// Неизвестный вид показываем как прислали, а не выбрасываем.
    static func label(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        return labels[key] ?? key
    }
}
