import Foundation

/// Слова о весе: как он менялся. Это чистые функции: их проверяют тестами, а
/// на экране они уже готовые строки.
enum MedicalCardWeight {
    /// «+0,4 кг с 03.10.2026»: как вес двигался с прошлого замера. Одного
    /// замера мало, и сравнивать не с чем.
    static func delta(_ series: [WeightPoint]) -> String? {
        guard series.count >= 2 else { return nil }
        let last = series[series.count - 1]
        let before = series[series.count - 2]
        // Разница округляется до десятой: вес меряют килограммами, а
        // «0,39999999 кг» — это калькулятор, а не весы.
        let diff = ((last.value - before.value) * 10).rounded() / 10
        let day = MedicalCardDates.russian(before.date)
        if diff == 0 {
            return "Без изменений с \(day)"
        }
        let sign = diff > 0 ? "+" : "−"
        return "\(sign)\(Amount.text(abs(diff))) кг с \(day)"
    }

    /// «6 замеров с 08.08.2026, от 28,4 до 29,3 кг»: сколько замеров и какой
    /// разброс. Одного замера для такой строки мало.
    static func summary(_ series: [WeightPoint]) -> String? {
        guard series.count > 1, let first = series.first, let last = series.last else { return nil }
        let count = Words.text(series.count, one: "замер", few: "замера", many: "замеров")
        return "\(count) с \(MedicalCardDates.russian(first.date)), "
            + "от \(Amount.text(first.value)) до \(Amount.text(last.value)) кг"
    }
}

/// Категории документов словами: сервер говорит по-английски, человек — по-русски.
enum MedicalCardDocuments {
    static func category(_ key: String) -> String {
        switch key {
        case "lab_result": "Анализ"
        case "conclusion": "Заключение"
        case "imaging": "Снимок"
        case "vaccination": "Прививка"
        case "insurance": "Страховка"
        default: "Документ"
        }
    }
}

extension MedicalCard {
    /// Клиники питомца: список из профиля, а если его нет — зеркало, как его
    /// держал сервер раньше. Врачу нужны все, а не только первые.
    var clinics: [ProfileClinic] {
        guard let profile else { return [] }
        if !profile.clinics.isEmpty {
            return profile.clinics
        }
        guard let name = profile.clinicName, !name.isEmpty else { return [] }
        let doctors = profile.vetName.map { [ProfileDoctor(name: $0, specialty: nil)] } ?? []
        return [ProfileClinic(name: name, phone: profile.clinicPhone, doctors: doctors)]
    }

    /// Чем кормят, где живёт и что с размножением: три строки, какие есть.
    var life: [(title: String, value: String)] {
        guard let profile else { return [] }
        var rows: [(String, String)] = []
        if let diet = profile.diet, !diet.isEmpty {
            rows.append(("Питание", diet))
        }
        if let living = profile.living, !living.isEmpty {
            rows.append(("Условия жизни", living))
        }
        if let reproduction = profile.reproduction, !reproduction.isEmpty {
            rows.append(("Репродуктивный статус", reproduction))
        }
        return rows
    }
}
