import SwiftUI

/// Медкарта как документ: кто это, что требует внимания и насколько карта
/// готова. Порядок и содержание — по iOS: сначала питомец, потом тревога,
/// потом готовность, и только потом записи по видам.
struct MedicalCardDocumentView: View {
    let card: MedicalCard
    /// Питомец, чья карта открыта: из него карточка в шапке.
    let pet: Pet?
    let app: AppModel
    /// Куда ведут кнопки документа.
    let actions: MedicalCardActions

    var body: some View {
        petCard
        attention
        readiness
    }

    /// Карточка питомца в шапке: фото, имя и строка «возраст, порода, пол» —
    /// та же, что в ленте. Отдельного паспорта не нужно: личность питомца
    /// видна и так, а его данные живут в «О питомце», куда карточка ведёт.
    @ViewBuilder
    private var petCard: some View {
        if let pet {
            Section {
                NavigationLink {
                    PetProfileView(client: app.client, petID: pet.id, app: app)
                } label: {
                    PetSummaryCard(pet: pet)
                }
                .accessibilityIdentifier("petCard")
            }
        }
    }

    /// Что требует внимания: врач спрашивает об этом раньше всего, и молчать
    /// об этом хуже, чем показать тревогу.
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
                .font(.subheadline)
                .foregroundStyle(.tint)
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
                .foregroundStyle(.tint)
                // Пока карта пуста, передавать её врачу нечем, и кнопка
                // «Передать врачу» в панели не нажмётся. Об этом сказано
                // здесь, а не отказом.
                if card.readinessDone < 2 {
                    Text("Карта почти пуста. Заполните её, и её можно будет передать врачу")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Главное для врача заполнено", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Готовность к приёму")
        }
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
