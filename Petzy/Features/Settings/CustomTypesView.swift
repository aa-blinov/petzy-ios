import SwiftUI

/// Свои типы записей: человек заводит тип со своими полями, и он появляется
/// под кнопкой «+» рядом со встроенными. Встроенные здесь не показываются:
/// их и так видно в выборе типа, а правки они не принимают.
struct CustomTypesView: View {
    let model: CustomTypesModel

    @State private var adding = false
    /// Тип на правке. Переход из кода, а не `NavigationLink`: ссылка внутри
    /// строки ломает удаление этой же строки, ряд с открытым свайп-действием
    /// исчезает из списка, и UIKit роняет приложение.
    @State private var editing: EventTypeInfo?
    @State private var isEditing = false

    var body: some View {
        List {
            failure
            existing
        }
        // Список простой, а не сгруппированный: удаление строки из
        // сгруппированного списка роняет UIKit с «Invalid number of items in
        // section», проверено на симуляторе. У ленты и документов тот же
        // приём с `swipeActions`, и там он не падает.
        .listStyle(.plain)
        .navigationTitle("Свои типы записей")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isEditing) {
            if let editing {
                CustomTypeFormView(model: model, saved: editing)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $adding) {
            // Свой NavigationStack: лист открывается без оболочки, а кнопки
            // «Отмена» и «Сохранить» рисует именно он.
            NavigationStack {
                CustomTypeFormView(model: model, saved: nil)
            }
        }
        // Именно alert, а не confirmationDialog: поповер поверх открытого
        // свайп-действия роняет список внутри UIKit, а alert показывается
        // другим способом и список не трогает.
        .alert(deleteTitle, isPresented: dialogBinding) {
            // Тип с записями сервер не удаляет, поэтому и кнопки удаления при
            // нём нет: обещать то, что потом откажут, незачем.
            if model.canDelete {
                Button("Удалить", role: .destructive) {
                    Task { await model.deletePending() }
                }
            }
            Button(model.canDelete ? "Отмена" : "Понятно", role: .cancel) { model.cancelDelete() }
        } message: {
            Text(deleteMessage)
        }
    }

    private var dialogBinding: Binding<Bool> {
        Binding(
            get: { model.pendingDelete != nil },
            set: {
                if !$0 {
                    model.cancelDelete()
                }
            }
        )
    }

    private var deleteTitle: String {
        model.canDelete ? "Удалить тип «\(model.pendingDelete?.label ?? "")»?" : "Тип удалить нельзя"
    }

    /// Что скажет диалог: пустой тип удаляется, тип с записями — нет.
    private var deleteMessage: String {
        guard model.canDelete else {
            let gone = model.pendingCount ?? 0
            let word = Words.pick(gone, one: "запись", few: "записи", many: "записей")
            return "У него \(gone) \(word). Удалить можно только пустой тип, а переименовать можно любой"
        }
        return "У него нет ни одной записи"
    }

    @ViewBuilder
    private var failure: some View {
        if let text = model.errorText {
            Section {
                Label(text, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private var existing: some View {
        Section {
            if model.isLoading, model.types.isEmpty {
                ProgressView()
            } else if model.types.isEmpty {
                Text("Своих типов пока нет")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.types) { type in
                    row(type)
                }
            }
        } footer: {
            Text("Свои типы появляются в выборе под кнопкой «+» в группе «Свои»")
        }
    }

    /// Строка как в вебе: слева название, справа кнопка-корзина. Свайпа здесь
    /// нет намеренно: `swipeActions` в этом списке роняет UIKit при удалении
    /// строки («Invalid number of items in section»), проверено на симуляторе
    /// шесть раз из шести. В ленте и документах тот же приём не падает.
    private func row(_ type: EventTypeInfo) -> some View {
        HStack(spacing: 12) {
            // Название — кнопка, а не жест: жестом строку не откроет голос.
            Button {
                editing = type
                isEditing = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: EventIcon.symbol(for: type.icon))
                            .foregroundStyle(.tint)
                        Text(type.label)
                    }
                    Text(fieldsText(of: type))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                Task { await model.prepareDelete(type) }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityLabel("Удалить тип \(type.label)")
        }
    }

    private func fieldsText(of type: EventTypeInfo) -> String {
        type.fields.isEmpty
            ? "Без полей"
            : type.fields.map(\.label).joined(separator: ", ")
    }
}
