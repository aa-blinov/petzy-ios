import SwiftUI

/// Курсы лекарств выбранного питомца. Экран только рисует состояние модели:
/// что показывать, в каком порядке и что делать после действия решает
/// `MedicationsModel`, а разбор ответа живёт в `MedicationsAPI`.
struct MedicationsView: View {
    /// `@Bindable`, а не `let`: поиск пишется прямо в модель, иначе строка
    /// поиска жила бы во вьюхе и терялась при пересоздании вкладки.
    @Bindable var model: MedicationsModel
    let app: AppModel

    @State private var editing: MedicationFormTarget?
    @State private var pendingDelete: Medication?
    @State private var restocking: Medication?
    @State private var dosing: Medication?
    @State private var pickedIntake: MedicationIntake?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Лекарства")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: app) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editing = .new(app: app)
                        } label: {
                            Label("Новое лекарство", systemImage: "plus")
                        }
                    }
                }
                .searchable(text: $model.search, prompt: "Найти лекарство")
                .refreshable { await model.load() }
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
            await model.loadIntakes()
        }
        .task(id: ObjectIdentifier(model)) {
            await model.load()
            await model.loadIntakes()
            // Расписание пришло — по нему ставится план напоминаний. Без
            // разрешения и при выключенном переключателе это ничего не делает.
            await app.refreshReminders(courses: model.medications, petName: app.selectedPet?.name)
        }
        .sheet(item: $editing) { target in
            MedicationFormView(app: app, model: model, target: target)
        }
        .sheet(item: $restocking) { med in
            RestockSheet(model: model, medication: med)
        }
        .sheet(item: $dosing) { med in
            DoseSheet(model: model, medication: med)
        }
        .sheet(item: $pickedIntake) { intake in
            IntakeSheet(model: model, intake: intake)
        }
        .alert(
            "Не получилось",
            isPresented: Binding(get: { model.errorText != nil }, set: {
                if !$0 {
                    model.errorText = nil
                }
            })
        ) {
            Button("Понятно", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
        .alert(
            "Записано",
            isPresented: Binding(get: { model.notice != nil }, set: {
                if !$0 {
                    model.notice = nil
                }
            })
        ) {
            Button("Понятно", role: .cancel) { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .confirmationDialog(
            "Удалить лекарство?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { med in
            Button("Удалить", role: .destructive) {
                Task { await model.delete(med) }
            }
            // Без роли `.cancel`: в iOS 26 такая кнопка выносится из карточки
            // и в поповере не рисуется, а закрыть диалог становится нечем.
            Button("Отмена") { pendingDelete = nil }
        } message: { _ in
            Text("Курс и его отметки о приёмах пропадут")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.medications.isEmpty {
            ProgressView()
        } else if model.medications.isEmpty, model.errorText == nil {
            ContentUnavailableView {
                Label("Лекарств нет", systemImage: "pills")
            } description: {
                Text("Добавьте курс, и здесь будут отметки о приёмах")
            } actions: {
                Button("Добавить лекарство") { editing = .new(app: app) }
            }
        } else {
            list
                .safeAreaInset(edge: .top) { overdueBanner }
        }
    }

    /// Полоса о просроченном приёме: число на вкладке говорит «что-то
    /// просрочено», а здесь человек видит, что именно и когда.
    @ViewBuilder
    private var overdueBanner: some View {
        if let dose = model.overdueDose {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Просрочен приём: \(dose.name)").font(.subheadline.weight(.medium))
                    Text("Был в \(dose.time)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.08))
        }
    }

    private var list: some View {
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
            ForEach(model.visibleMedications) { med in
                MedicationCard(
                    med: med,
                    now: Self.nowTime,
                    onGiveNow: { dosing = med },
                    onRestock: { restocking = med },
                    onEdit: { editing = .edit(app: app, med: med) },
                    onToggleCourse: { Task { await model.toggleCourse(med) } }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Изменить") { editing = .edit(app: app, med: med) }
                    Button("Удалить", role: .destructive) { pendingDelete = med }
                        .tint(.red)
                }
            }
            if model.search.isEmpty, !model.intakes.isEmpty {
                Section {
                    ForEach(model.intakes.prefix(10)) { intake in
                        Button {
                            pickedIntake = intake
                        } label: {
                            IntakeRow(intake: intake)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Последние приёмы")
                } footer: {
                    Text("Тап по приёму меняет его время или отменяет его")
                }
            }
            if model.search.isEmpty, model.endedCount > 0, model.endedCount < model.medications.count {
                Button(model.showsEnded ? "Скрыть завершённые" : "Завершённые курсы: \(model.endedCount)") {
                    model.showsEnded.toggle()
                }
                .font(.subheadline)
            }
        }
        .listStyle(.plain)
    }

    static var nowTime: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Строка отмеченного приёма: что дали, когда и сколько. Тап открывает
/// правку времени.
private struct IntakeRow: View {
    let intake: MedicationIntake

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pills")
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(intake.skipped ? "Пропущенный приём" : intake.medicationName)
                    .font(.subheadline)
                Text(
                    intake.skipped
                        ? "\(MomentText.humanDay(intake.day)), \(intake.time)"
                        : "\(MomentText.humanDay(intake.day)) в \(intake.time)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if intake.dose > 0 {
                Text(Amount.text(intake.dose)).font(.subheadline).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

/// Что открыть: новый курс или правка существующего. Экрану не нужен id
/// записи и ключ её полей, ему нужен готовый черновик.
enum MedicationFormTarget: Identifiable {
    case new(app: AppModel)
    case edit(app: AppModel, med: Medication)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(_, med): med.id
        }
    }
}
