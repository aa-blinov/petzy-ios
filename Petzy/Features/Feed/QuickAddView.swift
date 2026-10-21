import SwiftUI

/// Что записать: свой набор кнопок у каждого питомца, в его порядке. Полный
/// каталог — за строкой «Все типы»: у кошки не должно быть «Прогулки», а до
/// «Кормления» не должно быть пяти прокруток.
struct QuickAddView: View {
    let model: AppModel
    let onPick: (EventTypeInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingAll = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        List {
            if tiles.isEmpty {
                Section {
                    Text("На «+» пока ничего нет. Выберите типы в «О питомце»")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(tiles) { type in
                            Button {
                                onPick(type)
                            } label: {
                                tile(type)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Button {
                    showingAll = true
                } label: {
                    Label("Все типы", systemImage: "square.grid.2x2")
                }
            }
        }
        .navigationTitle("Что записать")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingAll) {
            EventCatalogView(model: model, onPick: onPick)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }

    /// Плитка типа: знак и название.
    private func tile(_ type: EventTypeInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: model.icon(for: type.key))
                .font(.title3)
                .foregroundStyle(.tint)
            Text(type.label)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }

    /// Что на «+»: видимые типы питомца в его порядке.
    private var tiles: [EventTypeInfo] {
        let catalog = model.typeCatalog
        let visible = catalog.filter { model.selectedPet?.tiles.isShown($0.key) ?? true }
        let ordered = model.selectedPet?.tiles.ordered(visible.map(\.key)) ?? visible.map(\.key)
        let byKey = Dictionary(uniqueKeysWithValues: visible.map { ($0.key, $0) })
        return ordered.compactMap { byKey[$0] }
    }
}
