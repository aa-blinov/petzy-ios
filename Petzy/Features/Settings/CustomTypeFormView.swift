import SwiftUI

/// Форма своего типа записи: название, чем рисуется, какие поля человек в
/// неё вписывает и как выглядит график в истории. Открывается и на создание,
/// и на правку: заведённое подставляется само.
struct CustomTypeFormView: View {
    let model: CustomTypesModel
    /// Тип, который правят. `nil` — создаётся новый.
    let saved: EventTypeInfo?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomTypeDraft
    @State private var isSaving = false

    init(model: CustomTypesModel, saved: EventTypeInfo?) {
        self.model = model
        self.saved = saved
        _draft = State(initialValue: saved.map(CustomTypeDraft.from) ?? CustomTypeDraft())
    }

    var body: some View {
        Form {
            // Отказ сервера показываем здесь: за листом его не видно, и
            // человек решил бы, что кнопка не работает.
            if let text = model.errorText {
                Section {
                    Label(text, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            identity
            fields
            chart
        }
        .navigationTitle(saved == nil ? "Новый тип" : "Тип записи")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // «Отмена» только у нового типа: его заводят в листе, а правка
                // приходит из списка, где рядом уже есть кнопка «Назад».
                if saved == nil {
                    Button("Отмена") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    Task {
                        isSaving = true
                        if await model.save(draft) {
                            dismiss()
                        }
                        isSaving = false
                    }
                }
                .disabled(problem != nil || isSaving)
            }
        }
    }

    private var problem: String? {
        CustomTypeDraft.problem(draft)
    }

    private var identity: some View {
        Section {
            TextField("Например, Выгул", text: $draft.label)
            Picker("Значок", selection: $draft.icon) {
                ForEach(CustomIcon.allCases, id: \.self) { icon in
                    Label(icon.title, systemImage: icon.symbol).tag(icon)
                }
            }
            Picker("Цвет", selection: $draft.color) {
                ForEach(CustomColor.allCases, id: \.self) { color in
                    Text(color.title).tag(color)
                }
            }
        } header: {
            Text("Тип")
        } footer: {
            Text("Значок и цвет видны в ленте и в истории")
        }
    }

    private var fields: some View {
        Section {
            ForEach($draft.fields) { $field in
                fieldEditor($field)
            }
            .onDelete { draft.fields.remove(atOffsets: $0) }
            Button {
                draft.fields.append(CustomFieldDraft())
            } label: {
                Label("Добавить поле", systemImage: "plus")
            }
        } header: {
            Text("Поля")
        } footer: {
            Text(problem ?? "Имя поля латиницей получается из подписи само")
        }
    }

    private func fieldEditor(_ field: Binding<CustomFieldDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Подпись поля", text: labelBinding(field))
            Picker("Вид", selection: field.kind) {
                ForEach(CustomFieldKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            if field.wrappedValue.kind == .select {
                TextField("По одному в строке, можно «значение=Подпись»", text: field.options, axis: .vertical)
                    .lineLimit(2 ... 6)
            }
            TextField("Имя поля латиницей", text: field.name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle("Обязательное", isOn: field.required)
        }
        .padding(.vertical, 4)
    }

    private var chart: some View {
        Section {
            Picker("График", selection: $draft.chart.kind) {
                ForEach(CustomChartKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            if draft.chart.kind == .value {
                Picker("По какому полю", selection: $draft.chart.field) {
                    Text("Выберите поле").tag("")
                    ForEach(numberFields, id: \.name) { field in
                        Text(field.label).tag(field.name)
                    }
                }
                TextField("Подпись величины, например «Минут»", text: $draft.chart.valueLabel)
            }
        } header: {
            Text("График в истории")
        } footer: {
            Text("«По величине» рисует линию по числовому полю, остальное считает записи")
        }
    }

    private var numberFields: [CustomFieldDraft] {
        draft.fields.filter { $0.kind == .number && !$0.name.isEmpty }
    }

    /// Пока человек не трогал имя сам, оно идёт за подписью: править латиницу
    /// ради одного поля незачем.
    private func labelBinding(_ field: Binding<CustomFieldDraft>) -> Binding<String> {
        Binding(
            get: { field.wrappedValue.label },
            set: { new in
                field.wrappedValue.label = new
                if !field.wrappedValue.nameEdited {
                    field.wrappedValue.name = FieldName.from(new, existing: takenNames(except: field.wrappedValue.id))
                }
            }
        )
    }

    private func takenNames(except id: UUID) -> [String] {
        draft.fields.filter { $0.id != id }.map(\.name)
    }
}
