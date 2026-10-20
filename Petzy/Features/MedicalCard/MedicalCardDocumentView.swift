import SwiftUI

/// Медкарта как документ: паспорт, то, что требует внимания, и готовность к
/// приёму. Плиток больше нет — на вебе карту переписали в документ, и
/// приложение идёт следом, но по-русски и по-нативному.
struct MedicalCardDocumentView: View {
    let card: MedicalCard
    /// Куда ведут кнопки документа.
    let actions: MedicalCardActions

    var body: some View {
        passport
        attention
        readiness
    }

    /// Паспорт: кто это. Вид и порода крупно, остальное — мелкой строкой, как
    /// на вебе. Имя питомца здесь не повторяется: оно уже в заголовке и в
    /// переключателе.
    private var passport: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(identity).font(.title3.weight(.semibold))
                if !facts.isEmpty {
                    Text(facts).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            if let birth = card.pet.birthDate, !birth.isEmpty {
                LabeledContent("Дата рождения", value: MedicalCardDates.russian(birth))
            }
            if let weight = card.weightLine {
                LabeledContent("Вес", value: weight)
            }
            if let blood = card.profile?.bloodType, !blood.isEmpty {
                LabeledContent("Группа крови", value: blood)
            }
            if let chip = card.profile?.chipNumber, !chip.isEmpty {
                // Номер чипа копируется по нажатию: его диктуют по телефону.
                Button {
                    UIPasteboard.general.string = chip
                } label: {
                    HStack {
                        Label("Чип", systemImage: "doc.on.doc")
                        Spacer()
                        Text(chip)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Скопировать номер чипа")
            }
        } header: {
            Text("Паспорт")
        }
    }

    /// Что требует внимания: красным и первым. Врач спрашивает об этом
    /// раньше всего, и молчать об этом хуже, чем показать тревогу.
    @ViewBuilder
    private var attention: some View {
        if !card.attention.isEmpty {
            Section {
                ForEach(card.attention) { item in
                    attentionRow(item)
                }
            } header: {
                Label("Требует внимания", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private func attentionRow(_ item: MedicalAttention) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.subheadline.weight(.semibold))
            if let status = item.statusText {
                Text(status).font(.caption).foregroundStyle(.red)
            }
            if let kind = item.record?.kind {
                Button("Записать повторную \(kind.repeated)") {
                    actions.newRecord(kind)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    /// Готовность к приёму: пять пунктов, сколько сделано и чего не хватает.
    private var readiness: some View {
        Section {
            HStack {
                Text("\(card.readinessDone) из \(MedicalReadiness.allCases.count)")
                    .font(.headline)
                Spacer()
                // Шкала идёт слева направо и показывает, сколько пунктов
                // закрыто. Системный индикатор, а не свой рисунок.
                ProgressView(value: Double(card.readinessDone), total: Double(MedicalReadiness.allCases.count))
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(maxWidth: 140)
            }
            if !card.readinessMissing.isEmpty {
                Text("Не хватает: \(card.readinessMissingText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let next = card.readinessNext {
                Button(next.action) {
                    actions.readinessStep(next.step)
                }
                .font(.subheadline)
            } else {
                Label("Главное для врача заполнено", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Готовность к приёму")
        }
    }

    /// «Собака, лабрадор»: вид открывает строку, порода идёт в строчных.
    private var identity: String {
        [card.pet.species, card.pet.breed.lowercased()]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// «5 лет, мальчик, кастрирован»: остальные факты о питомце.
    private var facts: String {
        [card.pet.ageText, card.pet.gender?.lowercased(), card.pet.neuteredText]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

extension MedicalAttention {
    /// Название того, что требует внимания: запись или сертификат.
    var title: String {
        switch self {
        case let .record(record): record.title
        case let .certificate(certificate): certificate.title
        }
    }

    /// Статус словами: «Просрочено на 11 дней» или «Истекла 3 дня назад».
    var statusText: String? {
        switch self {
        case let .record(record): record.statusText
        case let .certificate(certificate): certificate.statusText
        }
    }
}

extension MedicalKind {
    /// «прививку», «обработку», «визит», «операцию»: как это читается в
    /// «Записать повторную …».
    var repeated: String {
        switch self {
        case .vaccination: "прививку"
        case .parasite: "обработку"
        case .visit: "визит"
        case .procedure: "операцию"
        }
    }
}

/// Даты медкарты в том виде, в каком их пишет человек.
enum MedicalCardDates {
    /// «01.08.2021» из «2021-08-01».
    static func russian(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
}
