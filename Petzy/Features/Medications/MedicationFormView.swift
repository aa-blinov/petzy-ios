import SwiftUI

/// Форма курса лекарства. Собирает `MedicationDraft` и отдаёт его модели:
/// ни путей, ни названий полей сервера здесь нет. Набор типов, единиц
/// измерения и соответствие формы ответа — как в веб-приложении, чтобы
/// человек не придумывал заново то, чему его научил веб.
struct MedicationFormView: View {
    let app: AppModel
    let model: MedicationsModel
    let target: MedicationFormTarget

    @Environment(\.dismiss) private var dismiss

    @State private var draft: MedicationDraft
    @State private var days: Set<Int>
    @State private var times: [String]
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var hasStart = true
    @State private var hasEnd = false

    /// Типы, которые чаще всего выбирают, как в вебе.
    static let kinds = [
        "Таблетка", "Капсула", "Ингаляция", "Капли", "Укол", "Мазь",
        "Гель", "Сироп", "Суспензия", "Порошок", "Спрей", "Паста"
    ]

    /// Единица, в которой такую форму обычно считают. Пустая единица показывала
    /// бы «ед.», а это ничего не говорит.
    static let unitForKind = [
        "Таблетка": "таб", "Капсула": "капс", "Капли": "кап",
        "Укол": "мл", "Сироп": "мл", "Суспензия": "мл"
    ]

    static let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    init(app: AppModel, model: MedicationsModel, target: MedicationFormTarget) {
        self.app = app
        self.model = model
        self.target = target
        let source = switch target {
        case .new:
            MedicationDraft(
                petID: app.selectedPetID ?? "",
                name: "",
                kind: "Таблетка",
                schedule: DoseSchedule(days: [], times: []),
                asNeeded: false
            )
        case let .edit(_, med):
            MedicationDraft(
                petID: med.petID,
                name: med.name,
                kind: med.kind,
                strength: med.strength,
                doseUnit: med.doseUnit,
                defaultDose: med.defaultDose,
                schedule: med.schedule,
                asNeeded: med.asNeeded,
                inventoryEnabled: med.stock != nil,
                inventoryCurrent: med.stock?.current,
                inventoryTotal: med.stock?.total,
                inventoryWarningDays: med.stock?.warningDays,
                startedOn: med.startedOn,
                endedOn: med.endedOn
            )
        }
        _draft = State(initialValue: source)
        _days = State(initialValue: Set(source.schedule.days))
        _times = State(initialValue: source.schedule.times)
        if let iso = source.startedOn {
            _startDate = State(initialValue: Self.date(from: iso) ?? .now)
        }
        if let iso = source.endedOn, let parsed = Self.date(from: iso) {
            _endDate = State(initialValue: parsed)
            _hasEnd = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                basics
                schedule
                if draft.inventoryEnabled {
                    stock
                }
                dates
                notes
            }
            .navigationTitle(isEditing ? "Лекарство" : "Новое лекарство")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // MARK: - Поля

    private var basics: some View {
        Section("Лекарство") {
            TextField("Название", text: $draft.name)
            Picker("Форма", selection: $draft.kind) {
                ForEach(Self.kinds, id: \.self) { Text($0) }
            }
            .onChange(of: draft.kind) { _, new in
                // Единицу и форму ответа подставляем, только если человек
                // ничего не выбрал сам: выбранное руками не затираем.
                if draft.doseUnit == nil, let unit = Self.unitForKind[new] {
                    draft.doseUnit = unit
                }
            }
            TextField("Дозировка, например 500 мг", text: Binding(
                get: { draft.strength ?? "" },
                set: { draft.strength = $0.isEmpty ? nil : $0 }
            ))
            TextField("Сколько давать", text: Binding(
                get: { draft.defaultDose.map(Amount.text) ?? "" },
                set: { draft.defaultDose = $0.isEmpty ? nil : Double($0.replacingOccurrences(of: ",", with: ".")) }
            ))
            .keyboardType(.decimalPad)
            TextField("Единица, например таб", text: Binding(
                get: { draft.doseUnit ?? "" },
                set: { draft.doseUnit = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    private var schedule: some View {
        Section {
            Toggle("По необходимости", isOn: $draft.asNeeded)
            if !draft.asNeeded {
                HStack(spacing: 6) {
                    ForEach(0 ..< 7, id: \.self) { index in
                        let picked = days.contains(index)
                        Button {
                            if picked {
                                days.remove(index)
                            } else {
                                days.insert(index)
                            }
                        } label: {
                            Text(Self.weekdays[index])
                                .font(.subheadline.weight(picked ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(picked ? Color.accentColor.opacity(0.18) : Color.clear,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach($times, id: \.self) { $item in
                    DatePicker(
                        "Приём в \(item)",
                        selection: Binding(
                            get: { Self.date(from: item) ?? .now },
                            set: { item = Self.time(from: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
                .onDelete { times.remove(atOffsets: $0) }
                Button("Добавить время") { times.append(Self.time(from: .now)) }
            }
        } header: {
            Text("Расписание")
        } footer: {
            if !draft.asNeeded, days.isEmpty, !times.isEmpty {
                Text("Выберите дни недели, иначе курс не будет никогда")
                    .foregroundStyle(.red)
            } else if draft.asNeeded {
                Text("Такой курс не напоминает о времени: приём отмечают, когда дают")
            }
        }
    }

    private var stock: some View {
        Section("Остаток") {
            TextField("Сколько осталось", text: numberBinding(\.inventoryCurrent))
                .keyboardType(.decimalPad)
            TextField("Сколько в упаковке", text: numberBinding(\.inventoryTotal))
                .keyboardType(.decimalPad)
            TextField("Предупредить за дней", text: numberBinding(\.inventoryWarningDays))
                .keyboardType(.numberPad)
        }
    }

    private var dates: some View {
        Section("Курс") {
            Toggle("Задать начало", isOn: $hasStart)
            if hasStart {
                DatePicker("Начало", selection: $startDate, displayedComponents: .date)
            }
            Toggle("Задать окончание", isOn: $hasEnd)
            if hasEnd {
                DatePicker("Окончание", selection: $endDate, displayedComponents: .date)
                    .disabled(endDate < startDate)
            }
        }
    }

    private var notes: some View {
        Section("Заметки") {
            TextField("От чего или для чего", text: Binding(
                get: { draft.purpose ?? "" },
                set: { draft.purpose = $0.isEmpty ? nil : $0 }
            ))
            TextField("Кто назначил", text: Binding(
                get: { draft.prescribedBy ?? "" },
                set: { draft.prescribedBy = $0.isEmpty ? nil : $0 }
            ))
            TextField("Комментарий", text: Binding(
                get: { draft.comment ?? "" },
                set: { draft.comment = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
                .lineLimit(2 ... 4)
        }
    }

    // MARK: - Разбор и сохранение

    /// Числовое поле, где пустая строка означает «не задано», а не ноль:
    /// остаток 0 и незаданный остаток — разные вещи.
    private func numberBinding(_ keyPath: WritableKeyPath<MedicationDraft, Double?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath].map(Amount.text) ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : Double($0.replacingOccurrences(of: ",", with: ".")) }
        )
    }

    private func save() {
        draft.schedule = DoseSchedule(
            days: draft.asNeeded ? [] : days.sorted(),
            times: draft.asNeeded ? [] : times.sorted()
        )
        draft.startedOn = hasStart ? Self.iso(from: startDate) : nil
        // Пустая строка на сервере значит «убери дату», а `nil` — «не трогай».
        // Пустая строка на сервере значит «убери дату», а `nil` — «не трогай».
        draft.endedOn = hasEnd ? Self.iso(from: endDate) : ""
        Task {
            let saved: Bool = switch target {
            case .new:
                await model.create(draft)
            case let .edit(_, med):
                await model.update(med.id, draft: draft)
            }
            if saved {
                dismiss()
            }
        }
    }

    static func iso(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func time(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
