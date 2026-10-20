import SwiftUI

/// Блоки медкарты с записями: прививки и обработки, визиты и операции,
/// документы, клиника и условия жизни. Идут после состояния питомца, в том
/// же порядке, в каком спрашивает врач.
struct MedicalCardRecords: View {
    let card: MedicalCard
    let actions: MedicalCardActions

    var body: some View {
        prevention
        visits
        documents
        clinic
        life
    }

    // MARK: - Прививки и обработки

    private var prevention: some View {
        Section {
            ForEach(card.records[.vaccination] ?? []) { record in
                recordButton(record)
            }
            ForEach(card.records[.parasite] ?? []) { record in
                recordButton(record)
            }
            if !(card.records[.vaccination] ?? []).isEmpty {
                door("Все прививки", action: { actions.openSection(.vaccination) })
            }
            if !(card.records[.parasite] ?? []).isEmpty {
                door("Все обработки", action: { actions.openSection(.parasite) })
            }
            if (card.records[.vaccination] ?? []).isEmpty, (card.records[.parasite] ?? []).isEmpty {
                Text("Прививок и обработок нет").foregroundStyle(.secondary)
            }
            ForEach(card.certificates) { certificate in
                VStack(alignment: .leading, spacing: 2) {
                    Text(certificate.title).font(.subheadline)
                    Label(certificate.statusText, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(certificate.status == .expired ? .red : .secondary)
                }
            }
        } header: {
            Text("Прививки и обработки")
        }
    }

    // MARK: - Визиты и операции

    private var visits: some View {
        Section {
            ForEach(card.records[.visit] ?? []) { record in
                recordButton(record)
            }
            ForEach(card.records[.procedure] ?? []) { record in
                recordButton(record)
            }
            if !(card.records[.visit] ?? []).isEmpty {
                door("Все визиты", action: { actions.openSection(.visit) })
            }
            if !(card.records[.procedure] ?? []).isEmpty {
                door("Все операции", action: { actions.openSection(.procedure) })
            }
            if (card.records[.visit] ?? []).isEmpty, (card.records[.procedure] ?? []).isEmpty {
                Text("Визитов и операций нет").foregroundStyle(.secondary)
            }
        } header: {
            Text("Визиты и операции")
        }
    }

    // MARK: - Анализы и заключения

    private var documents: some View {
        Section {
            if card.documents.isEmpty {
                Text("Документов нет").foregroundStyle(.secondary)
            } else {
                ForEach(card.documents) { document in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title).font(.subheadline)
                        Text(MedicalCardDocuments.category(document.category))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                door("Все документы", action: actions.showDocuments)
            }
        } header: {
            Text("Анализы и заключения")
        }
    }

    // MARK: - Клиника и врачи

    private var clinic: some View {
        Section {
            if card.clinics.isEmpty {
                Text("Клиника не указана").foregroundStyle(.secondary)
            } else {
                ForEach(Array(card.clinics.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = entry.name, !name.isEmpty {
                            Text(name).font(.subheadline.weight(.medium))
                        }
                        if let phone = entry.phone, !phone.isEmpty {
                            phoneLink(phone)
                        }
                        ForEach(Array(entry.doctors.enumerated()), id: \.offset) { _, doctor in
                            Text(doctorLine(doctor))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            door("Изменить", action: actions.openProfile)
        } header: {
            Text("Клиника и врачи")
        }
    }

    /// Телефон открывается как звонок: его диктуют по телефону, и искать его
    /// вручную незачем.
    private func phoneLink(_ phone: String) -> some View {
        let number = phone.filter(\.isNumber)
        return Link(destination: URL(string: "tel://\(number)") ?? URL(string: "tel:")!) {
            Label(phone, systemImage: "phone")
                .font(.subheadline)
        }
    }

    /// «Каримов Д.» или «Каримов Д., кардиолог».
    private func doctorLine(_ doctor: ProfileDoctor) -> String {
        let name = doctor.name ?? ""
        let specialty = doctor.specialty ?? ""
        return specialty.isEmpty ? name : "\(name), \(specialty)"
    }

    // MARK: - Питание и условия

    private var life: some View {
        Section {
            if card.life.isEmpty {
                Text("Ничего не записано").foregroundStyle(.secondary)
            } else {
                ForEach(card.life, id: \.title) { row in
                    LabeledContent(row.title, value: row.value)
                }
            }
            door("Изменить", action: actions.openProfile)
        } header: {
            Text("Питание и условия")
        }
    }

    /// Тап по записи открывает её правку, как на вебе.
    private func recordButton(_ record: MedicalRecord) -> some View {
        Button {
            actions.editRecord(record)
        } label: {
            MedicalRecordRow(record: record)
        }
        .buttonStyle(.plain)
    }

    /// Тихая дверь внизу блока: «Изменить», «Все прививки». Она не спорит с
    /// содержимым блока, а просто ведёт дальше.
    private func door(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline)
            // Дверь — это ссылка, и она должна выглядеть ссылкой: акцентным
            // цветом, как ссылки в iOS, а не обычным текстом.
            .foregroundStyle(.tint)
    }
}

/// Строка записи в документе: название, когда, срок и где делали.
struct MedicalRecordRow: View {
    let record: MedicalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title).font(.subheadline.weight(.medium))
                Spacer()
                Text(MedicalCardDates.russian(record.date)).font(.caption).foregroundStyle(.secondary)
            }
            if let status = record.statusText {
                Label(status, systemImage: Self.symbol(for: record.status))
                    .font(.caption)
                    .foregroundStyle(Self.tint(for: record.status))
            }
            if let clinic = record.clinic, !clinic.isEmpty {
                Text(clinic).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Знак статуса: тревога, часы или галочка. Смысл читается и без цвета.
    static func symbol(for status: MedicalStatus) -> String {
        switch status {
        case .overdue: "exclamationmark.triangle"
        case .soon: "clock"
        case .fine: "checkmark.circle"
        case .none: "minus.circle"
        }
    }

    /// Цвет статуса: тревога, предупреждение, обычный.
    static func tint(for status: MedicalStatus) -> Color {
        switch status {
        case .overdue: .red
        case .soon: .orange
        case .fine, .none: .secondary
        }
    }
}
