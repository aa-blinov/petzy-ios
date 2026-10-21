import SwiftUI

/// Блоки медкарты с записями: прививки и обработки, визиты и операции,
/// документы. Идут после состояния питомца, в том же порядке, в каком
/// спрашивает врач.
struct MedicalCardRecords: View {
    let card: MedicalCard
    let actions: MedicalCardActions

    var body: some View {
        prevention
        visits
        documents
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
                NavigationLink(value: MedicalKind.vaccination) {
                    Text("Все прививки")
                }
            }
            if !(card.records[.parasite] ?? []).isEmpty {
                NavigationLink(value: MedicalKind.parasite) {
                    Text("Все обработки")
                }
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
                NavigationLink(value: MedicalKind.visit) {
                    Text("Все визиты")
                }
            }
            if !(card.records[.procedure] ?? []).isEmpty {
                NavigationLink(value: MedicalKind.procedure) {
                    Text("Все операции")
                }
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
                    // Строка открывает файл, а не просто сообщает название:
                    // в медкарте документ нужен ради самого файла.
                    Button {
                        actions.openDocument(document)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title).font(.subheadline)
                            Text(MedicalCardDocuments.category(document.category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Анализы и заключения")
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
