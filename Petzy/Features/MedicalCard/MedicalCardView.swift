import SwiftUI

/// Медкарта выбранного питомца. Экран рисует состояние `MedicalCardModel` и
/// ничего не знает про пути и ключи ответа.
struct MedicalCardView: View {
    let model: MedicalCardModel
    let app: AppModel

    @State private var form: MedicalFormTarget?
    @State private var pendingDelete: MedicalRecord?
    @State private var profile = false
    @State private var prep = false
    @State private var sharing = false
    /// Какой раздел открыт. Переход идёт по пути, а не ссылкой: ссылка внутри
    /// строки списка отдавала переход самой строке, и тап по плитке открывал
    /// чужой раздел, а «назад» вёл к следующему разделу вместо медкарты.
    @State private var path: [MedicalKind] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Медкарта")
                .navigationDestination(for: MedicalKind.self) { kind in
                    MedicalKindSectionView(
                        model: model,
                        app: app,
                        kind: kind,
                        onEdit: { form = .edit(app: app, record: $0) }
                    )
                }
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
        // Ключ здесь — сама модель, а не выбранный питомец: оболочка
        // пересоздаёт её на каждого питомца и делает это позже смены питомца.
        // По `selectedPetID` задача перезапускалась бы на старой модели, а на
        // экране уже была бы новая и пустая: раздел врал, что данных нет.
        .task(id: app.queueFlushCount) {
            // Раздел перечитывается, когда очередь ушла на сервер. При запуске
            // счётчик ноль, и второй раз читать незачем: раздел и так открыт
            // своим task, а вторая загрузка без сети кончилась бы ошибкой
            // поверх копии.
            guard app.queueFlushCount > 0 else { return }
            await model.load()
        }
        .task(id: ObjectIdentifier(model)) {
            await model.load()
        }
        .sheet(item: $form) { target in
            MedicalRecordFormView(app: app, model: model, target: target)
        }
        .sheet(isPresented: $profile) {
            MedicalProfileFormView(model: model, card: model.card)
        }
        .sheet(isPresented: $prep) {
            VisitPrepFormView(model: model, card: model.card)
        }
        .sheet(isPresented: $sharing) {
            MedicalShareSheet(model: model)
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
            Button("Отмена") { pendingDelete = nil }
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
            Button("Отмена") { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
        .alert("Готово", isPresented: Binding(get: { model.notice != nil }, set: {
            if !$0 {
                model.notice = nil
            }
        })) {
            Button("Понятно") { model.notice = nil }
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
            if model.isShowingCached {
                Section {
                    CachedNotice()
                }
            }
            if !model.pending.isEmpty {
                Section {
                    ForEach(model.pending) { write in
                        PendingRow(write: write) { model.removePending(write) }
                    }
                } header: {
                    Text("Не отправлено")
                }
            }
            header(card)
            Section("Разделы") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(card.tiles) { tile in
                        Button {
                            path.append(tile.kind)
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
            Button("Профиль для врача") { profile = true }
                .font(.subheadline)
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
        Section {
            if let prep = card.visitPrep {
                if let complaint = prep.complaint, !complaint.isEmpty {
                    Text(complaint).font(.subheadline)
                }
                // Сначала что изменилось, потом «как обычно»: в этом порядке
                // врач это читает, и словами, а не ключами `changed`.
                let values = Dictionary(uniqueKeysWithValues: prep.checks.map { ($0.id, $0.value) })
                let changed = VisitChecks.changed(values)
                if !changed.isEmpty {
                    Text("Изменилось: \(changed.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                let normal = VisitChecks.normal(values)
                if !normal.isEmpty {
                    Text("Как обычно: \(normal.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Что беспокоит и что изменилось: врач увидит это первой строкой")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Правка внутри своей секции: отдельной строкой над «К приёму» она
            // читалась как заголовок соседнего раздела.
            Button("Изменить") { prep = true }
                .font(.subheadline)
        } header: {
            Text("К приёму")
        }
    }

    /// Файл для врача. PDF серверный: приложение его готовит и отдаёт
    /// системному меню, а не собирает документ само.
    private func vet(_ card: MedicalCard) -> some View {
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
            Button {
                sharing = true
            } label: {
                Label("Ссылка для врача", systemImage: "link")
            }
            .disabled(card.canEdit != true)
        }
    }
}

/// Плитка раздела: сколько записей и есть ли среди них просроченные.
private struct CardTileView: View {
    let tile: CardTile

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Стрелка говорит, что плитка открывается. Раньше её рисовала
            // система у ссылки, а ссылка внутри строки списка ломала переход.
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        // По верху, а не по центру: плитки в ряду выравниваются по высоте самой
        // высокой, и подпись снизу уезжала бы от заголовка на пол-экрана.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
