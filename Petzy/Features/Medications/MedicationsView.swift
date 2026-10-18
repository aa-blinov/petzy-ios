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
        .task(id: app.selectedPetID) {
            await model.load()
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
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let med = pendingDelete {
                    Task { await model.delete(med) }
                }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: {
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

    var app: AppModel {
        switch self {
        case let .new(app), let .edit(app, _): app
        }
    }
}
