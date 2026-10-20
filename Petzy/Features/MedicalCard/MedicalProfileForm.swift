import Foundation

/// Профиль для врача: аллергии, условия, питание. То, что врач видит первым и
/// о чём спрашивает на каждом приёме.
struct MedicalProfile: Sendable {
    /// Версия, с которой открывается правка: сервер откажет сохранению из
    /// устаревшей копии, иначе правка второго человека затиралась бы молча.
    let baseVersion: String?
    let allergies: [Allergy]
    let allergiesNoneKnown: Bool
    let bloodType: String?
    let chipNumber: String?
    let clinicName: String?
    let clinicPhone: String?
    let vetName: String?
    /// Все клиники, а не только основная: сервер заменяет профиль целиком, и
    /// одна клиника вместо списка стирала бы остальные.
    let clinics: [ProfileClinic]
    let conditions: [MedicalCondition]
    let diet: String?
    let living: String?
    let reproduction: String?
}

/// Клиника и её врачи, как их держит сервер.
struct ProfileClinic: Sendable {
    var name: String?
    var phone: String?
    var doctors: [ProfileDoctor]
}

struct ProfileDoctor: Sendable {
    var name: String?
    var specialty: String?
}

struct Allergy: Sendable, Equatable {
    /// `var`, а не `let`: аллергию в форме добавляют и правят на месте.
    var substance: String
    var reaction: String
}

/// Хроническое заболевание: название, чем обостряется и с какого года.
struct MedicalCondition: Sendable, Equatable, Identifiable {
    var name: String
    var note: String?
    var sinceYear: Int?

    var id: String {
        name
    }

    /// «Дисплазия тазобедренных суставов, с 2023, обострения после нагрузки».
    var text: String {
        ([name] + subtitleParts).joined(separator: ", ")
    }

    /// «с 2023, обострения после нагрузки»: подпись под названием, без самого
    /// названия — иначе оно читалось бы дважды подряд.
    var subtitle: String {
        subtitleParts.joined(separator: ", ")
    }

    private var subtitleParts: [String] {
        var parts: [String] = []
        if let sinceYear {
            parts.append("с \(sinceYear)")
        }
        if let note, !note.isEmpty {
            parts.append(note)
        }
        return parts
    }

    /// Год из того, что человек напечатал. Пустая строка это «год не указан»,
    /// а не ноль, иначе в медкарте появилась бы запись «с 0».
    static func year(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4, let year = Int(trimmed) else { return nil }
        return (1950 ... 2100).contains(year) ? year : nil
    }
}

/// Профиль для врача в том виде, как его заполняет форма. `baseVersion` —
/// версия, с которой форму открыли: сохранение устаревшей копии сервер
/// отклоняет, иначе правка второго человека затиралась бы молча.
struct MedicalProfileDraft: Sendable {
    var baseVersion: String?
    var allergies: [Allergy]
    /// Владелец подтверждает, что аллергий нет. «Не заполнено» и «нет» это
    /// разные вещи, и врачу это важно.
    var allergiesNoneKnown: Bool
    var bloodType: String?
    var chipNumber: String?
    var clinicName: String?
    var clinicPhone: String?
    var vetName: String?
    var clinics: [ProfileClinic] = []
    var conditions: [MedicalCondition]
    var diet: String?
    var living: String?
    var reproduction: String?

    init(
        clinics: [ProfileClinic] = [],
        baseVersion: String?,
        allergies: [Allergy],
        allergiesNoneKnown: Bool,
        bloodType: String?,
        chipNumber: String?,
        clinicName: String?,
        clinicPhone: String?,
        vetName: String?,
        conditions: [MedicalCondition],
        diet: String?,
        living: String?,
        reproduction: String?
    ) {
        self.clinics = clinics
        self.baseVersion = baseVersion
        self.allergies = allergies
        self.allergiesNoneKnown = allergiesNoneKnown
        self.bloodType = bloodType
        self.chipNumber = chipNumber
        self.clinicName = clinicName
        self.clinicPhone = clinicPhone
        self.vetName = vetName
        self.conditions = conditions
        self.diet = diet
        self.living = living
        self.reproduction = reproduction
    }

    /// Профиль из ответа сервера, готовый к правке.
    init(baseVersion: String?, profile: MedicalProfile) {
        self.init(
            baseVersion: baseVersion,
            allergies: profile.allergies,
            allergiesNoneKnown: profile.allergiesNoneKnown,
            bloodType: profile.bloodType,
            chipNumber: profile.chipNumber,
            clinicName: profile.clinicName,
            clinicPhone: profile.clinicPhone,
            vetName: profile.vetName,
            conditions: profile.conditions,
            diet: profile.diet,
            living: profile.living,
            reproduction: profile.reproduction
        )
    }

    /// Профиль, которого ещё нет. Версии у него нет, и отправлять её незачем:
    /// сервер проверяет версию только когда её прислали.
    static func empty() -> MedicalProfileDraft {
        MedicalProfileDraft(
            baseVersion: nil,
            allergies: [],
            allergiesNoneKnown: false,
            bloodType: nil,
            chipNumber: nil,
            clinicName: nil,
            clinicPhone: nil,
            vetName: nil,
            conditions: [],
            diet: nil,
            living: nil,
            reproduction: nil
        )
    }

    /// Что человек должен поправить до запроса, своими словами. Проверки те же,
    /// что на сервере: пустая строка в поле уехала бы запросом и вернулась бы
    /// ошибкой после похода туда и обратно.
    static func problem(_ draft: MedicalProfileDraft) -> String? {
        if draft.allergies.contains(where: { $0.substance.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Укажите, на что аллергия"
        }
        if draft.conditions.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Укажите название заболевания"
        }
        if draft.conditions.contains(where: { condition in
            guard let year = condition.sinceYear else { return false }
            return !(1950 ... 2100).contains(year)
        }) {
            return "Год должен быть от 1950 до 2100"
        }
        return nil
    }
}
