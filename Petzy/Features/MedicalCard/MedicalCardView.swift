import SwiftUI

/// Медкарта выбранного питомца. Экран рисует состояние `MedicalCardModel` и
/// ничего не знает про пути и ключи ответа.
struct MedicalCardView: View {
    let model: MedicalCardModel
    let app: AppModel

    @State private var form: MedicalFormTarget?
    @State private var pendingDelete: MedicalRecord?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Медкарта")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: app) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            form = .new(app: app)
                        } label: {
                            Label("Новая запись", systemImage: "plus")
                        }
                        .disabled(model.card?.canEdit != true)
                    }
                }
        }
        .task(id: app.selectedPetID) {
            await model.load()
        }
        .sheet(item: $form) { target in
            MedicalRecordFormView(app: app, model: model, target: target)
        }
        .confirmationDialog(
            "Удалить запись?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let record = pendingDelete {
                    Task { await model.delete(record) }
                }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Запись пропадёт из медкарты")
        }
        .alert("Медкарта не открылась", isPresented: Binding(
            get: { model.errorText != nil && model.card == nil },
            set: {
                if !$0 {
                    model.errorText = nil
                }
            }
        )) {
            Button("Повторить") {
                model.errorText = nil
                Task { await model.load() }
            }
            Button("Отмена", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
        .alert("Записано", isPresented: Binding(get: { model.notice != nil }, set: {
            if !$0 {
                model.notice = nil
            }
        })) {
            Button("Понятно", role: .cancel) { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.card == nil {
            ProgressView()
        } else if let card = model.card {
            list(card)
        } else {
            ContentUnavailableView("Медкарта не открылась", systemImage: "cross.case")
        }
    }

    private func list(_ card: MedicalCard) -> some View {
        List {
            header(card)
            Section("Разделы") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(card.tiles) { tile in
                        NavigationLink {
                            MedicalKindSectionView(
                                model: model,
                                app: app,
                                kind: tile.kind,
                                onEdit: { form = .edit(app: app, record: $0) }
                            )
                        } label: {
                            CardTileView(tile: tile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            }
            visitPrep(card)
            vet(card)
        }
        .listStyle(.plain)
        .refreshable { await model.load() }
    }

    private func header(_ card: MedicalCard) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.pet.name).font(.title2.weight(.semibold))
                Text(subtitle(card.pet)).font(.subheadline).foregroundStyle(.secondary)
                if let weight = card.weightText {
                    Label(weight, systemImage: "scalemass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func subtitle(_ pet: CardPet) -> String {
        var parts = [pet.breed, pet.ageText, pet.neuteredText].filter { !$0.isEmpty }
        if parts.isEmpty {
            parts = ["Возраст не указан"]
        }
        return parts.joined(separator: ", ")
    }

    private func visitPrep(_ card: MedicalCard) -> some View {
        Section("К приёму") {
            if let prep = card.visitPrep {
                if let complaint = prep.complaint, !complaint.isEmpty {
                    Text(complaint).font(.subheadline)
                }
                ForEach(prep.checks) { check in
                    HStack {
                        Text(check.title)
                        Spacer()
                        Text(check.value).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            } else {
                Text("Что беспокоит и что изменилось: врач увидит это первой строкой")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Файл для врача. PDF серверный: приложение его готовит и отдаёт
    /// системному меню, а не собирает документ само.
    private func vet(_: MedicalCard) -> some View {
        Section("Для врача") {
            Button {
                Task { await model.downloadPDF() }
            } label: {
                Label(model.isPreparingPDF ? "Готовим файл" : "Скачать PDF", systemImage: "arrow.down.doc")
            }
            .disabled(model.isPreparingPDF)
            if let file = model.pdfFile {
                ShareLink(item: file) {
                    Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

/// Плитка раздела: сколько записей и есть ли среди них просроченные.
private struct CardTileView: View {
    let tile: CardTile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tile.kind.title, systemImage: tile.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text(tile
                .count == 0 ? "Нет записей" :
                "\(tile.count) \(Words.pick(tile.count, one: "запись", few: "записи", many: "записей"))")
                .font(.title3.weight(.semibold))
            if let status = tile.statusText {
                Text(status).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Что открыть в форме записи: новую или существующую.
enum MedicalFormTarget: Identifiable {
    case new(app: AppModel)
    case edit(app: AppModel, record: MedicalRecord)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(_, record): record.id
        }
    }

    var app: AppModel {
        switch self {
        case let .new(app), let .edit(app, _): app
        }
    }
}
