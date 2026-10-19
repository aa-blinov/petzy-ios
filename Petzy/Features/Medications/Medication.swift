import Foundation

/// Курс лекарства. Это то, что видит экран: ни путей, ни ключей ответа
/// сервера здесь нет, всё разбирается в `MedicationsAPI`. Если контракт
/// поменяется, правится один файл, а не карточка в ленте.
struct Medication: Identifiable, Sendable {
    let id: String
    let petID: String
    let name: String
    /// «Таблетка», «Суспензия»: сервер присылает подпись, а не код.
    let kind: String
    let strength: String?
    let doseUnit: String?
    let defaultDose: Double?
    let schedule: DoseSchedule
    /// «По необходимости»: дают, когда дадут, а не по часам.
    let asNeeded: Bool
    let isActive: Bool
    let courseStatus: CourseStatus
    let startedOn: String?
    let endedOn: String?
    let stock: Stock?
    /// Сегодняшние времена, которые ещё не закрыты, по времени.
    let openSlotsToday: [String]
    let scheduledToday: Bool
    let lastTakenAt: String?
    let lastTakenBy: String?
    /// Комментарий, «от чего» и «кто назначил»: форма правки их показывает.
    let comment: String?
    let purpose: String?
    let prescribedBy: String?
    /// Версия курса, которую человек видел. Её приложение отправляет при
    /// правке: сервер отвечает отказом, если курс поменяли с тех пор.
    let updatedAt: String?

    /// Расписание словами: «Ежедневно в 09:00», «В выбранные дни в 10:00,
    /// 22:00», «По необходимости».
    var scheduleText: String {
        guard !asNeeded, !schedule.times.isEmpty else { return "По необходимости" }
        let days = schedule.days.count == 7 ? "Ежедневно" : "В выбранные дни"
        return "\(days) в \(schedule.times.joined(separator: ", "))"
    }

    /// Все приёмы дня закрыты. Курс по необходимости за день не сделан
    /// никогда: у него нет расписания, к которому можно отнести приём.
    var isDoneToday: Bool {
        !asNeeded && scheduledToday && openSlotsToday.isEmpty
    }

    /// «Сегодня 1 из 2, не отмечено в 21:00, дальше в 09:00». Времена
    /// сравниваются строками: они одного формата `ЧЧ:ММ`.
    func todayProgress(at now: String) -> String {
        let total = schedule.times.count
        let missed = openSlotsToday.filter { $0 <= now }
        let next = openSlotsToday.first { $0 > now }
        var parts = ["Сегодня \(max(0, total - openSlotsToday.count)) из \(total)"]
        if !missed.isEmpty {
            parts.append("не отмечено в \(missed.joined(separator: ", "))")
        }
        if let next {
            parts.append("дальше в \(next)")
        }
        return parts.joined(separator: ", ")
    }

    /// Метка рядом с названием: «Архив» у законченного курса, «Начнётся
    /// 01.12.2026» у ещё не начавшегося.
    var courseTag: String? {
        switch courseStatus {
        case .planned:
            startedOn.map { "Начнётся \(Self.russianDay($0))" }
        case .ended:
            "Архив"
        case .active:
            nil
        }
    }

    /// «С 12.05.2026 по 26.05.2026 включительно» из тех дат, что у курса есть.
    var coursePeriod: String? {
        switch (startedOn, endedOn) {
        case let (start?, end?):
            "С \(Self.russianDay(start)) по \(Self.russianDay(end)) включительно"
        case let (nil, end?):
            "До \(Self.russianDay(end)) включительно"
        case let (start?, nil) where courseStatus != .planned:
            "С \(Self.russianDay(start))"
        default:
            nil
        }
    }

    /// «06.10.2026 в 08:43». Дата по-русски и время на часах человека:
    /// смещение из ответа не переводится в пояс телефона.
    var lastTakenText: String? {
        guard let lastTakenAt else { return nil }
        return "\(MomentText.humanDay(MomentText.day(of: lastTakenAt))) в \(MomentText.time(of: lastTakenAt))"
    }

    /// Остаток крупно: «0 из 10». Под ним — на сколько дней хватит.
    var stockText: String? {
        guard let stock else { return nil }
        guard let total = stock.total else { return Amount.text(stock.current) }
        return "\(Amount.text(stock.current)) из \(Amount.text(total))"
    }

    var stockSubtext: String? {
        guard let days = stock?.daysLeft else { return nil }
        let daysText = "хватит на \(Days.text(days))"
        return stock?.isLow == true ? "\(daysText), запас заканчивается" : daysText
    }

    /// «2,5 мл». Без единицы измерения показывается «шт.», как в вебе.
    var doseText: String {
        "\(Amount.text(defaultDose ?? 1)) \(doseUnit ?? "шт.")"
    }

    /// Дата по-русски, `01.10.2026`. Разбор один на всё приложение.
    static func russianDay(_ iso: String) -> String {
        MomentText.russianDay(iso)
    }
}

/// Расписание: дни недели 0…6 и времена `ЧЧ:ММ`.
struct DoseSchedule: Sendable, Equatable, Codable {
    let days: [Int]
    let times: [String]
}

/// Состояние курса. Сервер присылает `course_status`, а у старых записей его
/// нет и остаётся только `is_active`.
enum CourseStatus: String, Sendable, Equatable {
    case active
    case planned
    case ended

    /// Без `course_status` решение принимает `is_active`.
    static func resolve(_ raw: String?, isActive: Bool) -> CourseStatus {
        if let raw, let parsed = CourseStatus(rawValue: raw) {
            return parsed
        }
        return isActive ? .active : .ended
    }
}

/// Остаток упаковки. `daysLeft` сервер считает по расписанию курса.
struct Stock: Sendable, Equatable {
    let current: Double
    let total: Double?
    let daysLeft: Double?
    let isLow: Bool
    let warningDays: Double?
}

/// Приём, который пора дать. Приходит одним маршрутом на все курсы питомца,
/// с флагом просрочки: об этом узнают, не заходя внутрь.
struct UpcomingDose: Identifiable, Sendable {
    var id: String {
        "\(medicationID)@\(date) \(time)"
    }

    let medicationID: String
    let name: String
    let kind: String
    let time: String
    let date: String
    let isOverdue: Bool
    let inventoryWarning: Bool
    /// Приём вчерашнего вечера, который никто не отметил: несколько часов
    /// после полуночи он ещё предлагается.
    let carriedOver: Bool
}

/// Число по-русски: `2,5`, без хвостовых нулей.
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

enum Days {
    static func text(_ count: Double) -> String {
        "\(Amount.text(count)) \(Words.pick(Int(count), one: "день", few: "дня", many: "дней"))"
    }
}

/// Момент времени, введённый человеком: день и время его часами. Время уходит
/// на сервер вместе с `tz`, иначе приём «в 21:00» записался бы по времени
/// телефона в другом поясе.
struct Moment: Sendable, Equatable {
    let day: String
    let time: String
}

/// Слот расписания, который закрывает отметка. Без него сервер закрывает
/// ближайший открытый слот, а нажатие «09:00» могло бы закрыть «21:00».
struct DoseSlot: Sendable, Equatable {
    let date: String
    let time: String
}

/// Курс в том виде, как его заполняет форма. Экран отдаёт черновик и не знает,
/// какое поле называется как в ответе сервера.
struct MedicationDraft: Sendable {
    var petID: String
    var name: String
    var kind: String
    var strength: String?
    var doseUnit: String?
    var defaultDose: Double?
    var schedule: DoseSchedule
    var asNeeded: Bool
    var inventoryEnabled: Bool
    var inventoryCurrent: Double?
    var inventoryTotal: Double?
    var inventoryWarningDays: Double?
    var comment: String?
    var startedOn: String?
    var endedOn: String?
    var purpose: String?
    var prescribedBy: String?

    /// Пустая строка на сервере значит «убери дату», а `nil` — «не трогай».
    /// Форма отдаёт пустую строку только там, где человек снял дату руками.
    init(
        petID: String,
        name: String,
        kind: String,
        strength: String? = nil,
        doseUnit: String? = nil,
        defaultDose: Double? = nil,
        schedule: DoseSchedule,
        asNeeded: Bool,
        inventoryEnabled: Bool = false,
        inventoryCurrent: Double? = nil,
        inventoryTotal: Double? = nil,
        inventoryWarningDays: Double? = nil,
        comment: String? = nil,
        startedOn: String? = nil,
        endedOn: String? = nil,
        purpose: String? = nil,
        prescribedBy: String? = nil
    ) {
        self.petID = petID
        self.name = name
        self.kind = kind
        self.strength = strength
        self.doseUnit = doseUnit
        self.defaultDose = defaultDose
        self.schedule = schedule
        self.asNeeded = asNeeded
        self.inventoryEnabled = inventoryEnabled
        self.inventoryCurrent = inventoryCurrent
        self.inventoryTotal = inventoryTotal
        self.inventoryWarningDays = inventoryWarningDays
        self.comment = comment
        self.startedOn = startedOn
        self.endedOn = endedOn
        self.purpose = purpose
        self.prescribedBy = prescribedBy
    }
}

/// Что человек отметил: когда, сколько и какой слот расписания это закрывает.
/// Собрано в одну структуру, потому что иначе у метода шесть параметров, и
/// половину их перепутать на вызове легко.
struct IntakeMark: Sendable {
    let medicationID: String
    let moment: Moment
    /// Часовой пояс человека, а не телефона: время вводили на своих часах.
    let zone: String
    var dose: Double?
    var slot: DoseSlot?
    var skipped = false
}

/// Отмеченный приём в истории курса.
struct MedicationIntake: Identifiable, Sendable {
    let id: String
    let medicationID: String
    let medicationName: String
    let day: String
    let time: String
    let dose: Double
    let author: String?
    let comment: String?
}

extension Medication {
    /// Порядок списка. Сначала курс, у которого ближайший приём ещё не
    /// отмечен, внутри — по времени приёма; потом те, где на сегодня всё;
    /// потом ещё не начатые и в конце архив. Без сортировки самый просроченный
    /// курс уезжал бы вниз списка под теми, где всё сделано.
    static func byUrgency(_ lhs: Medication, _ rhs: Medication) -> Bool {
        rank(lhs) < rank(rhs)
    }

    /// Место курса в списке и то, чем внутри места он сортируется: временем
    /// ближайшего приёма или датой начала.
    private struct Urgency: Comparable {
        let rank: Int
        let tie: String

        static func < (lhs: Urgency, rhs: Urgency) -> Bool {
            (lhs.rank, lhs.tie) < (rhs.rank, rhs.tie)
        }
    }

    private static func rank(_ med: Medication) -> Urgency {
        switch med.courseStatus {
        case .ended:
            return Urgency(rank: 3, tie: "")
        case .planned:
            return Urgency(rank: 2, tie: med.startedOn ?? "")
        case .active:
            if let slot = med.openSlotsToday.first {
                return Urgency(rank: 0, tie: slot)
            }
            return Urgency(rank: 1, tie: "")
        }
    }
}
