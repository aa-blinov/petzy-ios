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
        .confirmationDialog(
            model.canDelete ? "Удалить тип «\(model.pendingDelete?.label ?? "")»?" : "Тип удалить нельзя",
            isPresented: Binding(get: { model.pendingDelete != nil }, set: {
                if !$0 {
                    model.cancelDelete()
                }
            }),
            titleVisibility: .visible
        ) {
            // Тип с записями сервер не удаляет, поэтому и кнопки удаления при
            // нём нет: обещать то, что потом откажут, незачем.
            if model.canDelete {
                Button("Удалить", role: .destructive) {
                    Task { await model.deletePending() }
                }
            }
            // Без роли `.cancel`: в iOS 26 такая кнопка выносится из карточки
            // и в поповере не рисуется вовсе, а закрыть диалог становится нечем.
            Button("Понятно") { model.cancelDelete() }
        } message: {
            let gone = model.pendingCount ?? 0
            let word = Words.pick(gone, one: "запись", few: "записи", many: "записей")
            if model.canDelete {
                Text("У него нет ни одной записи")
            } else {
                Text("У него \(gone) \(word). Удалить можно только пустой тип, а переименовать можно любой")
            }
        }
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

    private func row(_ type: EventTypeInfo) -> some View {
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
            .padding(.vertical, 2)
        }
        // Без `.plain` вся строка красится в акцент и читается как ссылка.
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await model.prepareDelete(type) }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func fieldsText(of type: EventTypeInfo) -> String {
        type.fields.isEmpty
            ? "Без полей"
            : type.fields.map(\.label).joined(separator: ", ")
    }
}
