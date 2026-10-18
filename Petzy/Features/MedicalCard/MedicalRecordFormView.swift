import SwiftUI

/// Раздел медкарты целиком: записи вида, с повтором по дате и с удалением.
struct MedicalKindSectionView: View {
    let model: MedicalCardModel
    let app: AppModel
    let kind: MedicalKind
    let onEdit: (MedicalRecord) -> Void

    @State private var pendingDelete: MedicalRecord?
    @State private var showsAll = false

    var body: some View {
        List {
            ForEach(records) { record in
                row(record)
            }
            if hasMore {
                Button(showsAll ? "Свернуть" : "Показать все") {
                    showsAll.toggle()
                    if showsAll {
                        Task { await model.loadAllRecords(of: kind) }
                    }
                }
                .font(.subheadline)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadAllRecords(of: kind) }
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
    }

    private var records: [MedicalRecord] {
        showsAll ? model.records(of: kind) : Array(model.records(of: kind).prefix(10))
    }

    private var hasMore: Bool {
        (model.card?.count(for: kind) ?? 0) > records.count
    }

    private func row(_ record: MedicalRecord) -> some View {
        Button {
            onEdit(record)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.title).font(.headline)
                    Spacer()
                    if record.isOverdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Просрочено")
                    }
                }
                Text(MomentText.russianDay(record.date)).font(.subheadline).foregroundStyle(.secondary)
                if let next = record.nextDue {
                    Text("Повтор: \(MomentText.russianDay(next))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let status = record.statusText {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(record.isOverdue ? .red : .secondary)
                }
                if let clinic = record.clinic, !clinic.isEmpty {
                    Text(clinic).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Изменить") { onEdit(record) }
            Button("Удалить", role: .destructive) { pendingDelete = record }
                .tint(.red)
        }
    }
}

/// Форма записи медкарты. Поля своего вида показывает, чужие прячет: сервер
/// всё равно их отбросит, а человек в лишних полях ошибётся.
struct MedicalRecordFormView: View {
    let app: AppModel
    let model: MedicalCardModel
    let target: MedicalFormTarget

    @Environment(\.dismiss) private var dismiss

    @State private var draft: MedicalRecordDraft
    @State private var date = Date.now
    @State private var nextDue = Date.now
    @State private var hasNextDue = false

    init(app: AppModel, model: MedicalCardModel, target: MedicalFormTarget) {
        self.app = app
        self.model = model
        self.target = target
        let base = switch target {
        case .new:
            MedicalRecordDraft(
                petID: app.selectedPetID ?? "",
                kind: .vaccination,
                date: MedicalRecordFormView.iso(.now),
                title: ""
            )
        case let .edit(_, record):
            MedicalRecordDraft(
                petID: app.selectedPetID ?? "",
                kind: record.kind,
                date: record.date,
                title: record.title,
                nextDue: record.nextDue,
                clinic: record.clinic,
                vet: record.vet,
                note: record.note
            )
        }
        _draft = State(initialValue: base)
        if let parsed = MedicalRecordFormView.date(from: base.date) {
            _date = State(initialValue: parsed)
        }
        if let next = base.nextDue, let parsed = MedicalRecordFormView.date(from: next) {
            _nextDue = State(initialValue: parsed)
            _hasNextDue = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Вид") {
                    Picker("Вид записи", selection: $draft.kind) {
                        ForEach(MedicalKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Название", text: $draft.title)
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                }
                repeating
                Section("Запись") {
                    TextField(
                        "Клиника",
                        text: Binding(get: { draft.clinic ?? "" }, set: { draft.clinic = $0.isEmpty ? nil : $0 })
                    )
                    TextField(
                        "Врач",
                        text: Binding(get: { draft.vet ?? "" }, set: { draft.vet = $0.isEmpty ? nil : $0 })
                    )
                    TextField(
                        "Комментарий",
                        text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0.isEmpty ? nil : $0 }),
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                }
            }
            .navigationTitle(isEditing ? "Правка записи" : "Новая запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(MedicalRecordDraft.problem(currentDraft) != nil)
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = target {
            return true
        }
        return false
    }

    /// Повтор есть только у прививок и обработок: у визита к врачу и у
    /// операции «повторить через полгода» не бывает.
    @ViewBuilder
    private var repeating: some View {
        if draft.kind == .vaccination || draft.kind == .parasite {
            Section("Повтор") {
                Toggle("Задать дату повтора", isOn: $hasNextDue)
                if hasNextDue {
                    DatePicker("Повтор", selection: $nextDue, in: date..., displayedComponents: .date)
                }
                if draft.kind == .vaccination {
                    Picker("От чего защищает", selection: Binding(
                        get: { draft.protects ?? "" },
                        set: { draft.protects = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Не выбрано").tag("")
                        ForEach(MedicalKind.protects.sorted(by: { $0.key < $1.key }), id: \.key) { key, title in
                            Text(title).tag(key)
                        }
                    }
                    TextField("Номер партии", text: Binding(
                        get: { draft.batch ?? "" },
                        set: { draft.batch = $0.isEmpty ? nil : $0 }
                    ))
                } else {
                    Picker("От кого", selection: Binding(
                        get: { draft.target ?? "" },
                        set: { draft.target = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Не выбрано").tag("")
                        ForEach(MedicalKind.targets.sorted(by: { $0.key < $1.key }), id: \.key) { key, title in
                            Text(title).tag(key)
                        }
                    }
                }
            }
        } else if draft.kind == .visit {
            Section("Жалобы") {
                TextField("Что беспокоит", text: Binding(
                    get: { draft.complaint ?? "" },
                    set: { draft.complaint = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .lineLimit(2 ... 5)
                TextField("Диагноз", text: Binding(
                    get: { draft.diagnosis ?? "" },
                    set: { draft.diagnosis = $0.isEmpty ? nil : $0 }
                ))
                TextField("Назначения", text: Binding(
                    get: { draft.recommendations ?? "" },
                    set: { draft.recommendations = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .lineLimit(2 ... 5)
            }
        }
    }

    /// Черновик с подставленными датами: кнопка «Сохранить» проверяет именно
    /// его, иначе отключилась бы по устаревшему состоянию.
    private var currentDraft: MedicalRecordDraft {
        var value = draft
        value.date = Self.iso(date)
        value.nextDue = hasNextDue ? Self.iso(nextDue) : nil
        return value
    }

    private func save() {
        let value = currentDraft
        Task {
            let saved: Bool = switch target {
            case .new:
                await model.save(value)
            case let .edit(_, record):
                await model.update(record.id, draft: value)
            }
            if saved {
                dismiss()
            }
        }
    }

    static func iso(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
