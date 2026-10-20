import SwiftUI

/// Значения по умолчанию для формы записи. Новая запись открывается ими
/// уже заполненной, поэтому набирать корм или вес каждый день не нужно.
struct FormDefaultsView: View {
    let model: FormDefaultsModel
    let app: AppModel

    @State private var query = ""
    /// Какое поле сейчас в фокусе. У поля с цифровой клавиатурой нет клавиши
    /// Return, и без кнопки «Готово» над ней её нечем убрать.
    @FocusState private var focus: String?

    var body: some View {
        List {
            if let problem = model.errorText {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            if types.isEmpty, !query.isEmpty {
                // Пустой поиск должен говорить об этом: молчаливый белый
                // список выглядит как поломка.
                Section {
                    ContentUnavailableView.search(text: query)
                }
            }
            ForEach(types) { type in
                // Раздел на тип, а не на категорию: одинаковые поля есть у
                // разных типов («Корм» у кормления и у туалета), и без названия
                // типа не понять, к чему значение относится.
                Section {
                    ForEach(type.fields) { field in
                        input(field, of: type)
                    }
                } header: {
                    Label(type.label, systemImage: app.icon(for: type.key))
                }
            }
        }
        .searchable(text: $query, prompt: "Найти поле")
        .navigationTitle("Значения по умолчанию")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDone { focus = nil }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.isSaving ? "Сохраняем" : "Сохранить") {
                    Task { await model.save() }
                }
                .disabled(model.isSaving)
            }
        }
    }

    /// Типы с полями, в порядке каталога под «+». Типы без полей пропускают:
    /// набирать там нечего.
    private var types: [EventTypeInfo] {
        EventCatalog.search(model.types(app.typeCatalog), query)
    }

    @ViewBuilder
    private func input(_ field: EventFieldInfo, of type: EventTypeInfo) -> some View {
        let text = Binding(
            get: { model.value(field, of: type.key) },
            set: { model.set($0, for: field, of: type.key) }
        )
        if let options = field.options, !options.isEmpty {
            Picker(field.label, selection: text) {
                Text("Не выбрано").tag("")
                ForEach(options, id: \.value) { Text($0.text).tag($0.value) }
            }
        } else if field.type == "number" {
            TextField(field.label, text: text)
                .keyboardType(.decimalPad)
                .focused($focus, equals: "\(type.key)-\(field.name)")
        } else {
            TextField(field.label, text: text)
                .focused($focus, equals: "\(type.key)-\(field.name)")
        }
    }
}
