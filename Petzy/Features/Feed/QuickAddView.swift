import SwiftUI

/// Что записать: свой набор кнопок у каждого питомца, в его порядке. Полный
/// каталог — за строкой «Все типы»: у кошки не должно быть «Прогулки», а до
/// «Кормления» не должно быть пяти прокруток.
struct QuickAddView: View {
    let model: AppModel
    let onPick: (EventTypeInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var saving = false
    @State private var errorText: String?

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
            if !tiles.isEmpty, model.selectedPet?.isOwner != false {
                Section {
                    Button {
                        editing = true
                    } label: {
                        Label("Другие события", systemImage: "square.grid.2x2")
                    }
                } footer: {
                    Text("Остальное — в правке набора: записать можно то, что на «+»")
                }
            }
            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Что записать")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $editing) {
            // Как на вебе: дверь ведёт не в каталог записей, а в набор питомца.
            // Записать можно ровно то, что на «+», и набор сначала пополняют.
            TileSettingsView(initial: tilesSettings, catalog: model.typeCatalog) { updated in
                Task { await save(updated) }
            }
        }
        .overlay {
            if saving {
                ProgressView("Сохранение")
            }
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

    /// Набор питомца как он есть: его правит «Другие события».
    private var tilesSettings: TileSettings {
        model.selectedPet?.tiles ?? TileSettings()
    }

    /// Сохранение набора прямо из листа: формы питомца здесь нет, поэтому
    /// карточка читается и отправляется целиком (см. `PetTilesAPI`).
    private func save(_ updated: TileSettings) async {
        guard let petID = model.selectedPetID else { return }
        saving = true
        defer { saving = false }
        do {
            try await PetTilesAPI.save(model.client, petID: petID, tiles: updated)
            errorText = nil
            await model.loadPets()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Что на «+»: видимые типы питомца в его порядке.
    private var tiles: [EventTypeInfo] {
        let catalog = model.typeCatalog
        let visible = catalog.filter { tilesSettings.isShown($0.key) }
        let ordered = tilesSettings.ordered(visible.map(\.key))
        let byKey = Dictionary(uniqueKeysWithValues: visible.map { ($0.key, $0) })
        return ordered.compactMap { byKey[$0] }
    }
}
