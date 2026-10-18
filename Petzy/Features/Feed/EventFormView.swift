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

    /// Пустая форма выбранного типа на текущий момент.
    init(model: AppModel, type: EventTypeInfo) {
        self.init(model: model, draft: Self.emptyDraft(type: type))
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
                }
                if let problem = draft.problem {
                    Section {
                        Text(problem).foregroundStyle(.red)
                    }
                }
            }
            // На экране шириной 466 pt заголовок не влезает между «Отмена» и
            // «Сохранить» и обрезается, поэтому у правки он короткий.
            .navigationTitle(isNew ? "Новая запись" : "Правка")
            .navigationBarTitleDisplayMode(.inline)
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
        } else if field.type == "number" {
            TextField(field.label, text: binding(for: field))
                .keyboardType(.decimalPad)
        } else {
            TextField(field.label, text: binding(for: field))
        }
    }

    private func binding(for field: EventFieldInfo) -> Binding<String> {
        Binding(
            get: { draft.values[field.name] ?? "" },
            set: { draft.values[field.name] = $0 }
        )
    }

    private func save() {
        var ready = draft
        ready.date = Feed.isoDay(day, calendar: .current)
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
            date: Feed.isoDay(now, calendar: .current),
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
