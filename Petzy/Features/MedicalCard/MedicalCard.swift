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

    /// От чего прививка защищает. Есть только у прививок.
    static let protects: [String: String] = [
        "rabies": "Бешенство",
        "dhpp": "Комплексная (DHPP)",
        "lepto": "Лептоспироз",
        "kennel": "Парагрипп",
        "fvrcp": "Комплексная для кошек",
        "felv": "Кошачий лейкоз",
        "myxo_rhd": "Миксоматоз и геморрагическая болезнь"
    ]

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

/// Профиль для врача: аллергии, условия, питание.
struct MedicalProfile: Sendable {
    let allergies: [Allergy]
    let allergiesNoneKnown: Bool
    let bloodType: String?
    let chipNumber: String?
    let clinicName: String?
    let clinicPhone: String?
    let vetName: String?
    let conditions: [MedicalCondition]
    let diet: String?
    let living: String?
    let reproduction: String?
}

struct Allergy: Sendable, Equatable {
    let substance: String
    let reaction: String
}

/// Хроническое заболевание: название, чем обостряется и с какого года.
struct MedicalCondition: Sendable, Equatable, Identifiable {
    let name: String
    let note: String?
    let sinceYear: Int?

    var id: String {
        name
    }

    /// «Дисплазия тазобедренных суставов, с 2023, обострения после нагрузки».
    var text: String {
        var parts = [name]
        if let sinceYear {
            parts.append("с \(sinceYear)")
        }
        if let note, !note.isEmpty {
            parts.append(note)
        }
        return parts.joined(separator: ", ")
    }
}

/// «К приёму»: что беспокоит и что изменилось.
struct VisitPrep: Sendable {
    let complaint: String?
    let checks: [VisitCheck]
}

struct VisitCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
}

/// Запись медкарты в том виде, как её заполняет форма. Экран отдаёт
/// черновик, а названия полей сервера здесь не встречаются.
struct MedicalRecordDraft: Sendable {
    var petID: String
    var kind: MedicalKind
    var date: String
    var title: String
    /// Дата повтора. Пустая строка на сервере значит «убери», `nil` — «не трогай».
    var nextDue: String?
    var clinic: String?
    var vet: String?
    var note: String?
    /// Номер партии прививки.
    var batch: String?
    /// Кого закрывает обработка: обязателен для `parasite`.
    var target: String?
    /// От чего защищает прививка.
    var protects: String?
    var complaint: String?
    var diagnosis: String?
    var recommendations: String?

    init(
        petID: String,
        kind: MedicalKind,
        date: String,
        title: String,
        nextDue: String? = nil,
        clinic: String? = nil,
        vet: String? = nil,
        note: String? = nil,
        batch: String? = nil,
        target: String? = nil,
        protects: String? = nil,
        complaint: String? = nil,
        diagnosis: String? = nil,
        recommendations: String? = nil
    ) {
        self.petID = petID
        self.kind = kind
        self.date = date
        self.title = title
        self.nextDue = nextDue
        self.clinic = clinic
        self.vet = vet
        self.note = note
        self.batch = batch
        self.target = target
        self.protects = protects
        self.complaint = complaint
        self.diagnosis = diagnosis
        self.recommendations = recommendations
    }
}

extension MedicalRecordDraft {
    /// Что человек должен поправить до запроса, своими словами. `nil` — можно
    /// отправлять. Проверка здесь, а не только на сервере: человек видит
    /// подсказку у поля, а не ошибку после похода туда и обратно.
    static func problem(_ draft: MedicalRecordDraft) -> String? {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите название"
        }
        if draft.date.isEmpty {
            return "Укажите дату"
        }
        // Обработка без цели сервер не примет: «от кого» здесь обязателен.
        if draft.kind == .parasite, (draft.target ?? "").isEmpty {
            return "Выберите, от кого обработка"
        }
        return nil
    }
}
