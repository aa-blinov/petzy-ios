import Foundation

/// Группа прививок из справочника: чем прививают и что это закрывает.
struct VaccineGroup: Identifiable, Sendable {
    let key: String
    let label: String
    let detail: String?
    let species: [String]

    var id: String {
        key
    }

    /// «Комплексная для собак, Чума, аденовирус, парвовирус, парагрипп».
    var text: String {
        guard let detail, !detail.isEmpty else { return label }
        return "\(label), \(detail)"
    }
}

/// Отбор групп для питомца. Справочник приходит целиком и один раз, а показывать
/// половину из него бессмысленно: у собаки нет смысла выбирать прививку от
/// кошачьего лейкоза.
enum VaccineCatalog {
    /// Виды животных сервер зовёт ключами, а карта отдаёт их словами. Список
    /// маленький и меняется вместе с серверным, поэтому живёт здесь.
    private static let speciesCodes = [
        "Собака": "dog",
        "Кот": "cat",
        "Кролик": "rabbit",
        "Хорёк": "ferret",
        "Морская свинка": "guinea_pig",
        "Шиншилла": "chinchilla",
        "Крыса": "rat",
        "Хомяк": "hamster",
        "Птица": "bird",
        "Рыбка": "fish"
    ]

    /// Группы, которые можно выбрать питомцу этого вида. Вид, которого в
    /// справочнике нет, получает общий список: пустой выбор означал бы, что
    /// прививку выбрать нечем.
    static func forSpecies(
        _ species: String,
        in groups: [VaccineGroup],
        keeping picked: String? = nil
    ) -> [VaccineGroup] {
        let code = speciesCodes[species] ?? "other"
        var suitable = groups.filter { $0.species.contains(code) || $0.species.contains("other") }
        // Уже выбранная группа остаётся в списке, даже когда виду не подходит:
        // иначе правка старой записи стёрла бы из неё то, что человек вписал.
        if let picked, !suitable.contains(where: { $0.key == picked }) {
            suitable.append(contentsOf: groups.filter { $0.key == picked })
        }
        return suitable
    }
}
