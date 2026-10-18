import Foundation

/// Вид питомца: ключ, который знает сервер, и подпись для человека. Список
/// взят из веб-приложения (`frontend/src/utils/species.ts`), чтобы одно и то же
/// животное называлось одинаково.
enum PetSpecies {
    struct Kind: Identifiable, Sendable {
        let key: String
        let title: String
        /// У рыбы и попугая породы нет: то, что у собаки «порода», у рыбки
        /// «вид». Подпись поля меняется вместе с видом питомца.
        let breedTitle: String
        /// Кастрация бывает у млекопитающих, у рыбы её не спросишь.
        let neutering: Bool

        var id: String {
            key
        }
    }

    private static let kinds: [Kind] = [
        Kind(key: "cat", title: "Кот", breedTitle: "Порода", neutering: true),
        Kind(key: "dog", title: "Собака", breedTitle: "Порода", neutering: true),
        Kind(key: "rabbit", title: "Кролик", breedTitle: "Порода", neutering: true),
        Kind(key: "ferret", title: "Хорёк", breedTitle: "Окрас", neutering: true),
        Kind(key: "guinea_pig", title: "Морская свинка", breedTitle: "Порода", neutering: true),
        Kind(key: "chinchilla", title: "Шиншилла", breedTitle: "Окрас", neutering: true),
        Kind(key: "rat", title: "Крыса", breedTitle: "Порода", neutering: true),
        Kind(key: "hamster", title: "Хомяк", breedTitle: "Порода", neutering: true),
        Kind(key: "bird", title: "Птица", breedTitle: "Вид", neutering: false),
        Kind(key: "fish", title: "Рыбка", breedTitle: "Вид", neutering: false),
        Kind(key: "turtle", title: "Черепаха", breedTitle: "Вид", neutering: false),
        Kind(key: "reptile", title: "Ящерица или змея", breedTitle: "Вид", neutering: false),
        Kind(key: "other", title: "Другой питомец", breedTitle: "Порода или вид", neutering: true)
    ]

    /// Порядок как в вебе: сначала те, у кого вид выбирают чаще.
    static var all: [Kind] {
        kinds
    }

    private static func kind(_ key: String?) -> Kind? {
        guard let key else { return nil }
        return kinds.first { $0.key == key }
    }

    /// Неизвестный вид показываем как прислали, а не выбрасываем.
    static func label(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        return kind(key)?.title ?? key
    }

    static func breedTitle(for key: String?) -> String {
        kind(key)?.breedTitle ?? "Порода"
    }

    /// Про кастрацию спрашивают только у тех, у кого она бывает. Без вида
    /// питомца не спросим вовсе: человек ещё не выбрал, о ком речь.
    static func asksAboutNeutering(_ key: String?) -> Bool {
        kind(key)?.neutering == true
    }
}
