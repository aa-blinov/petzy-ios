import Foundation

/// Пять пунктов, без которых врачу нечего сказать о питомце. Порядок — тот, в
/// каком врач их спрашивает, и он же порядок подсказок на экране.
enum MedicalReadiness: String, CaseIterable, Sendable {
    case allergies
    case vaccination
    case parasite
    case clinic
    case weight

    /// Название пункта. Словами, как их говорит врач.
    var title: String {
        switch self {
        case .allergies: "Аллергии"
        case .vaccination: "Прививки"
        case .parasite: "Обработки от паразитов"
        case .clinic: "Клиника"
        case .weight: "Вес"
        }
    }

    /// Что нажать, чтобы пункт стал готов.
    var action: String {
        switch self {
        case .allergies: "Указать аллергии"
        case .vaccination: "Записать прививку"
        case .parasite: "Записать обработку"
        case .clinic: "Указать клинику"
        case .weight: "Записать вес"
        }
    }
}

/// Что требует внимания: просроченная запись или истёкший сертификат.
enum MedicalAttention: Identifiable, Sendable {
    case record(MedicalRecord)
    case certificate(CardCertificate)

    var id: String {
        switch self {
        case let .record(record): "record-\(record.id)"
        case let .certificate(certificate): "certificate-\(certificate.id)"
        }
    }

    /// Запись или сертификат — по-разному, а на экране это две разные строки.
    var record: MedicalRecord? {
        if case let .record(record) = self {
            return record
        }
        return nil
    }

    var certificate: CardCertificate? {
        if case let .certificate(certificate) = self {
            return certificate
        }
        return nil
    }

    /// Насколько это горячее: чем больше дней просрочено, тем раньше.
    var daysOverdue: Int {
        switch self {
        case let .record(record): -(record.daysLeft ?? 0)
        case let .certificate(certificate): -(certificate.daysLeft ?? 0)
        }
    }
}

extension MedicalCard {
    /// Готовность к приёму: пять пунктов, что сделано и что нет. Считается по
    /// карте, а не по её разделы: иначе приложение считало бы одно, а врач
    /// видел бы другое.
    var readiness: [MedicalReadiness: Bool] {
        [
            .allergies: hasAllergies,
            .vaccination: count(for: .vaccination) > 0 || !certificates.isEmpty,
            .parasite: count(for: .parasite) > 0,
            .clinic: hasClinic,
            .weight: weight != nil
        ]
    }

    /// Сколько пунктов из пяти сделано.
    var readinessDone: Int {
        readiness.values.filter(\.self).count
    }

    /// Чего не хватает, названиями пунктов.
    var readinessMissing: [String] {
        MedicalReadiness.allCases
            .filter { readiness[$0] != true }
            .map { $0.title.lowercased() }
    }

    /// «аллергии, прививки и вес»: список словами. Разделитель «·» в интерфейсе
    /// не используется, а «и» перед последним читается как список.
    var readinessMissingText: String {
        let items = readinessMissing
        guard items.count > 1 else { return items.first ?? "" }
        if items.count == 2 {
            return "\(items[0]) и \(items[1])"
        }
        return "\(items.dropLast().joined(separator: ", ")) и \(items[items.count - 1])"
    }

    /// Первый шаг: то, что ещё не сделано, и кнопка, которая его делает.
    /// Когда всё сделано, шага нет: предлагать нечего.
    var readinessNext: (step: MedicalReadiness, action: String)? {
        guard let step = MedicalReadiness.allCases.first(where: { readiness[$0] != true }) else { return nil }
        return (step, step.action)
    }

    /// Что требует внимания: сначала самое горящее. Заменённая более новой
    /// запись не зовёт: её уже сделали заново.
    var attention: [MedicalAttention] {
        var items: [MedicalAttention] = overdueRecords
            .filter { !$0.superseded }
            .map { .record($0) }
        items += certificates.filter { $0.status == .expired }.map { .certificate($0) }
        return items.sorted { $0.daysOverdue > $1.daysOverdue }
    }

    /// Просрочено ли что-то по этому виду. Записи берём из полного списка, а не
    /// из показанных: показанных десять может не хватить, и значок на вкладке
    /// врал бы.
    private func isOverdue(_ kind: MedicalKind) -> Bool {
        if overdueRecords.contains(where: { $0.kind == kind && !$0.superseded }) {
            return true
        }
        // Сертификат — тоже прививка, и просроченный сертификат означает то же.
        return kind == .vaccination && certificates.contains { $0.status == .expired }
    }

    /// Аллергии сказаны или отмечено, что их нет. «Не заполнено» и «нет» это
    /// разные вещи, и врачу это важно.
    private var hasAllergies: Bool {
        guard let profile else { return false }
        return !profile.allergies.isEmpty || profile.allergiesNoneKnown
    }

    /// Клиника названа или у неё есть врач.
    private var hasClinic: Bool {
        guard let profile else { return false }
        if profile.clinics.contains(where: isFilled) {
            return true
        }
        return !(profile.clinicName ?? "").isEmpty || !(profile.clinicPhone ?? "").isEmpty
    }

    /// Клиника заполнена, если у неё есть имя, телефон или врач.
    private func isFilled(_ clinic: ProfileClinic) -> Bool {
        !(clinic.name ?? "").isEmpty || !(clinic.phone ?? "").isEmpty || !clinic.doctors.isEmpty
    }
}

extension CardCertificate {
    /// Статус сертификата словами: «Действует», «Скоро истекает», «Истекла
    /// 3 дня назад», «Срок не указан».
    var statusText: String {
        switch status {
        case .valid:
            return "Действует"
        case .soon:
            return "Скоро истекает"
        case .expired:
            guard let daysLeft else { return "Истекла" }
            let days = Words.text(abs(daysLeft), one: "день", few: "дня", many: "дней")
            return "Истекла \(days) назад"
        case .none:
            return "Срок не указан"
        }
    }
}
