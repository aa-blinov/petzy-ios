import SwiftUI

/// Что на «+» у питомца и в каком порядке. Список один и он же порядок:
/// перетаскивание ставит частые записи наверх, переключатель убирает лишние с
/// «+», не теряя их из каталога. Сохраняется вместе с питомцем, отдельной
/// кнопки нет.
///
/// Своё состояние, а не биндинг на черновик формы: правка, до которой форма не
/// досматривает, терялась бы молча. Здесь она копится локально и уходит в
/// форму одним куском при выходе.
struct TileSettingsView: View {
    let catalog: [EventTypeInfo]
    /// Отдать правку форме: она запишет её в черновик и сохранит вместе с
    /// остальными полями питомца.
    let onCommit: (TileSettings) -> Void

    @State private var tiles: TileSettings

    init(initial: TileSettings, catalog: [EventTypeInfo], onCommit: @escaping (TileSettings) -> Void) {
        self.catalog = catalog
        self.onCommit = onCommit
        _tiles = State(initialValue: initial)
    }

    var body: some View {
        List {
            Section {
                ForEach(rows, id: \.key) { type in
                    Toggle(isOn: shown(type.key)) {
                        Label(type.label, systemImage: icon(type.key))
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Перетащите частые записи наверх. Выключенные останутся в «Всех типах»")
            }
        }
        .toolbar { EditButton() }
        .navigationTitle("Типы на «+»")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { onCommit(tiles) }
    }

    /// Строки в том порядке, в каком они на «+»: сначала поставленные
    /// человеком, потом остальные.
    private var rows: [EventTypeInfo] {
        let byKey = Dictionary(catalog.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return tiles.ordered(catalog.map(\.key)).compactMap { byKey[$0] }
    }

    /// Переключатель пишет в `visible` явное «да» или «нет»: умолчание потом
    /// уже не переиграет выбор человека.
    private func shown(_ key: String) -> Binding<Bool> {
        Binding(
            get: { tiles.isShown(key) },
            set: { tiles.visible[key] = $0 }
        )
    }

    /// Перетаскивание задаёт порядок всех строк: и видимых, и скрытых.
    private func move(from source: IndexSet, to destination: Int) {
        var keys = rows.map(\.key)
        keys.move(fromOffsets: source, toOffset: destination)
        tiles.order = keys
    }

    /// Знак типа: тот же, что в каталоге и на «+». У части типов сервер знака
    /// не присылает, и `EventIcon` подставляет свой, иначе строка стояла бы
    /// без знака рядом с остальными.
    private func icon(_ key: String) -> String {
        EventIcon.symbol(for: catalog.first { $0.key == key }?.icon)
    }
}
