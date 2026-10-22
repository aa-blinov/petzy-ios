import SwiftUI

/// Что открыто в форме: новая запись выбранного типа или правка существующей.
/// Отдельная обёртка нужна `.sheet(item:)`, и заодно она хранит `id` записи
/// для правки, который самому черновику не полагается.
struct EventFormTarget: Identifiable {
    let id = UUID()
    let draft: EventDraft
    let recordID: String?
}

/// Форма новой записи и правки старой. Поля рисуются из описания типа: типов
/// записи тридцать пять, и писать под каждый свою форму было бы работой больше,
/// чем вся лента.
struct EventFormView: View {
    let model: AppModel
    /// `nil` — новая запись, иначе `id` правки.
    let recordID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var day: Date
    @State private var moment: Date
    /// Какое поле сейчас в фокусе. Return ведёт к следующему полю, а над
    /// цифровой клавиатурой стоит «Готово»: у неё клавиши Return нет.
    @FocusState private var focus: String?

    private let isNew: Bool

    init(model: AppModel, draft: EventDraft, recordID: String? = nil) {
        self.model = model
        self.recordID = recordID
        isNew = recordID == nil
        _draft = State(initialValue: draft)
        let calendar = Calendar.current
        _day = State(initialValue: Self.date(from: draft.date, calendar: calendar))
        _moment = State(initialValue: Self.time(from: draft.time, calendar: calendar))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Дата", selection: $day, displayedComponents: .date)
                    DatePicker("Время", selection: $moment, displayedComponents: .hourAndMinute)
                }
                Section {
                    ForEach(draft.type.fields) { field in
                        input(for: field)
                    }
                }
                Section("Комментарий") {
                    TextField("Что заметили", text: $draft.comment, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .focused($focus, equals: "comment")
                        .submitLabel(.done)
                        .onSubmit { moveFocus() }
                }
                if let problem = draft.problem {
                    Section {
                        Text(problem).foregroundStyle(.red)
                    }
                }
            }
            // Заголовок — название типа записи: «Правка» не говорит ни о
            // чём, а человек смотрит на поля и должен понимать, что правит.
            .navigationTitle(draft.type.label)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDone { focus = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(draft.problem != nil)
                }
            }
        }
    }

    @ViewBuilder
    private func input(for field: EventFieldInfo) -> some View {
        if let options = field.options, !options.isEmpty {
            Picker(field.label, selection: binding(for: field)) {
                Text("Не выбрано").tag("")
                ForEach(options, id: \.value) { option in
                    Text(option.text).tag(option.value)
                }
            }
        } else if field.type == "textarea" {
            // Подпись сверху, а не сбоку: многострочному полю сбоку места не
            // хватит. Так же и в вебе, там у textarea вертикальная раскладка.
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("", text: binding(for: field), axis: .vertical)
                    .lineLimit(3 ... 6)
                    .focused($focus, equals: field.name)
                    .submitLabel(.next)
                    .onSubmit { moveFocus() }
            }
        } else if field.type == "number" {
            // Подпись живёт в `LabeledContent`, а не в плейсхолдере поля:
            // плейсхолдер исчезает, как только человек что-то ввёл, и «150»
            // без слова «Вес корма (г)» на экране ничего не значит.
            LabeledContent(field.label) {
                TextField("", text: binding(for: field))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: field.name)
            }
        } else {
            LabeledContent(field.label) {
                TextField("", text: binding(for: field))
                    .focused($focus, equals: field.name)
                    .submitLabel(.next)
                    .onSubmit { moveFocus() }
            }
        }
    }

    /// Поля по порядку: Return ведёт к следующему. Поля с вариантами ответа
    /// пропускаются: в них нечего набирать.
    private var focusOrder: [String] {
        draft.type.fields.filter { ($0.options?.isEmpty ?? true) }.map(\.name) + ["comment"]
    }

    private func moveFocus() {
        guard let current = focus, let index = focusOrder.firstIndex(of: current) else { return }
        focus = index + 1 < focusOrder.count ? focusOrder[index + 1] : nil
    }

    private func binding(for field: EventFieldInfo) -> Binding<String> {
        Binding(
            get: { draft.values[field.name] ?? "" },
            set: { draft.values[field.name] = $0 }
        )
    }

    private func save() {
        var ready = draft
        ready.date = MomentText.isoDay(day, calendar: .current)
        ready.time = Self.clock(moment)
        Task {
            if let recordID {
                await model.updateEvent(id: recordID, draft: ready)
            } else {
                await model.createEvent(ready)
            }
            dismiss()
        }
    }

    // MARK: - Разбор даты и времени

    static func emptyDraft(type: EventTypeInfo) -> EventDraft {
        let now = Date()
        return EventDraft(
            type: type,
            values: [:],
            comment: "",
            date: MomentText.isoDay(now, calendar: .current),
            time: clock(now)
        )
    }

    /// `HH:mm` без локали и календаря: время человек вводит у себя и вводит
    /// его снова, часы устройства тут ни при чём.
    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func date(from text: String, calendar: Calendar) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components) ?? Date()
    }

    private static func time(from text: String, calendar: Calendar) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.hour = parts.count > 0 ? parts[0] : 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(from: components) ?? Date()
    }
}

/// Выбор типа записи под кнопкой «+». Типов тридцать пять, список ищется,
/// а не прокручивается до конца.
struct EventCatalogView: View {
    let model: AppModel
    let onPick: (EventTypeInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.types) { type in
                            Button {
                                onPick(type)
                            } label: {
                                CatalogRow(type: type, icon: model.icon(for: type.key))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Найти запись")
        .navigationTitle("Добавить запись")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Лист без кнопки закрытия закрывается только свайпом вниз, а на
            // этом устройстве рельс вкладок занимает правый край и жест неочевиден.
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }

    private var groups: [EventCatalog.Group] {
        EventCatalog.groups(EventCatalog.search(model.typeCatalog, query))
    }
}

/// Строка каталога: чем называется запись и что она попросит вписать.
/// Подпись «Просто отметка» нужна для типов без полей, иначе строка выглядит
/// оборванной.
private struct CatalogRow: View {
    let type: EventTypeInfo
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(type.label)
                Text(asks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var asks: String {
        let labels = type.fields.map(\.label)
        return labels.isEmpty ? "Просто отметка" : labels.joined(separator: ", ")
    }
}
