import Foundation

/// Вид записи медкарты. Порядок случаев это порядок экрана, а не то, в каком
/// сервер прислал словарь: на экране человек ищет прививки первыми.
enum MedicalKind: String, CaseIterable, Sendable {
    case vaccination
    case parasite
    case visit
    case procedure

    var title: String {
        switch self {
        case .vaccination: "Прививки"
        case .parasite: "Обработка от паразитов"
        case .visit: "Приёмы врача"
        case .procedure: "Операции и процедуры"
        }
    }

    /// Значок плитки.
    var symbol: String {
        switch self {
        case .vaccination: "syringe"
        case .parasite: "ant"
        case .visit: "stethoscope"
        case .procedure: "cross.case"
        }
    }

    /// Кого обработка закрывает. Есть только у обработок.
    static let targets: [String: String] = [
        "fleas_ticks": "Блохи и клещи",
        "worms": "Глисты",
        "both": "Блохи, клещи и глисты"
    ]
}

/// Насколько запись «горит». Статус считает сервер, здесь он только читается.
enum MedicalStatus: String, Sendable {
    case overdue
    case soon
    /// Сервер зовёт это `ok`, а имя в Swift короче трёх букв не проходит линтер.
    case fine = "ok"
    case none
}

/// Запись медкарты питомца.
struct MedicalRecord: Identifiable, Sendable {
    let id: String
    let kind: MedicalKind
    let title: String
    let date: String
    /// Дата следующего прививки или обработки. `nil` — повтора нет.
    let nextDue: String?
    let status: MedicalStatus
    /// Осталось дней до повтора, отрицательное — просрочено.
    let daysLeft: Int?
    let clinic: String?
    let vet: String?
    let note: String?
    /// Номер партии прививки.
    let batch: String?
    /// Кого закрывает обработка.
    let target: String?
    /// От чего защищает прививка.
    let protects: String?
    /// Жалоба, диагноз и назначения приёма врача. Без них форма правки
    /// показала бы пустые поля и стёрла бы написанное врачом.
    let complaint: String?
    let diagnosis: String?
    let recommendations: String?
    /// Приложенные к записи документы. Сервер заменяет запись целиком, и без
    /// этих идентификаторов правка отвязала бы документы от записи.
    let documentIDs: [String]
    /// Версия записи, которую человек видел. Её приложение отправляет при
    /// правке: сервер отвечает отказом, если запись поменяли с тех пор.
    let updatedAt: String?

    /// «Просрочено 11 дней». Пусто у записи без даты повтора: выдуманный срок
    /// хуже отсутствия срока.
    var statusText: String? {
        guard let daysLeft else { return nil }
        // Просрочка считается отрицательным числом дней, поэтому в текст идёт
        // модуль: «Просрочено 11 дней», а не «Просрочено -11 дней».
        let days = Words.text(abs(daysLeft), one: "день", few: "дня", many: "дней")
        return status == .overdue ? "Просрочено \(days)" : "Осталось \(days)"
    }

    var isOverdue: Bool {
        status == .overdue
    }
}

/// Плитка раздела на экране медкарты.
struct CardTile: Identifiable, Sendable {
    let kind: MedicalKind
    let count: Int
    /// Сколько записей просрочено именно в этом разделе.
    let overdue: Int

    var id: String {
        kind.rawValue
    }

    /// «1 просрочена». Про остальные записи плитка молчит: они никуда не торопят.
    var statusText: String? {
        guard overdue > 0 else { return nil }
        return "\(overdue) \(Words.pick(overdue, one: "просрочена", few: "просрочены", many: "просрочены"))"
    }
}

/// Питомец в шапке медкарты: то, что врач видит первым.
struct CardPet: Sendable {
    let name: String
    let breed: String
    let species: String
    let ageText: String
    let neuteredText: String
}

/// Замер веса.
struct WeightPoint: Sendable {
    let date: String
    let value: Double
}

/// Медкарта выбранного питомца. Сервер собирает её целиком, поэтому и
/// приложение показывает её целиком: плитки, сроки и лекарства приходят одним
/// куском и не должны требовать пяти запросов при открытии вкладки.
struct MedicalCard: Sendable {
    let pet: CardPet
    let records: [MedicalKind: [MedicalRecord]]
    let counts: [MedicalKind: Int]
    let overdueCount: Int
    let weight: WeightPoint?
    let medications: [CardMedication]
    let documents: [CardDocument]
    let pastCourses: [CardCourse]
    let profile: MedicalProfile?
    let visitPrep: VisitPrep?
    let generatedAt: String
    let canEdit: Bool

    func count(for kind: MedicalKind) -> Int {
        counts[kind] ?? 0
    }

    /// «29,3 кг, последний 04.10.2026».
    var weightText: String? {
        guard let weight else { return nil }
        return "\(Amount.text(weight.value)) кг, последний \(Medication.russianDay(weight.date))"
    }

    /// Плитки в порядке экрана.
    var tiles: [CardTile] {
        MedicalKind.allCases.map { kind in
            CardTile(kind: kind, count: count(for: kind), overdue: overdueIn(kind))
        }
    }

    private func overdueIn(_ kind: MedicalKind) -> Int {
        (records[kind] ?? []).filter(\.isOverdue).count
    }
}

/// Курс лекарства в карте: то же лекарство, но без экрана лекарств.
struct CardMedication: Identifiable, Sendable {
    let id: String
    let name: String
    let doseText: String?
    let purpose: String?
}

/// Документ, приложенный к медкарте.
struct CardDocument: Identifiable, Sendable {
    let id: String
    let title: String
}

/// Законченный курс: человек хочет знать, чем лечили и что закончилось.
struct CardCourse: Identifiable, Sendable {
    let id: String
    let name: String
}

/// Отметки «К приёму». Значения сервер шлёт как `normal` и `changed`, а на
/// экране человек читает «Как обычно» и «Изменилось»: ключ и слово не то же
/// самое, и врачу список ключей не нужен.
enum VisitChecks {
    static let order = ["appetite", "thirst", "stool", "urine", "vomiting", "cough", "activity"]

    static let titles: [String: String] = [
        "appetite": "Аппетит",
        "thirst": "Жажда",
        "stool": "Стул",
        "urine": "Моча",
        "vomiting": "Рвота",
        "cough": "Кашель",
        "activity": "Активность"
    ]

    static func title(_ key: String) -> String {
        titles[key] ?? key
    }

    /// «Изменилось» и «Как обычно» в том порядке, в котором врач это читает:
    /// сначала что нового, потом подтверждение, что остальное в порядке.
    static func changed(_ checks: [String: String]) -> [String] {
        words(checks, value: "changed")
    }

    static func normal(_ checks: [String: String]) -> [String] {
        words(checks, value: "normal")
    }

    private static func words(_ checks: [String: String], value: String) -> [String] {
        order.compactMap { checks[$0] == value ? title($0).lowercased() : nil }
    }
}
