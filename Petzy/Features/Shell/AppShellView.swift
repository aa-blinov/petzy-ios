import SwiftUI

/// Оболочка приложения: пять вкладок веб-клиента и переключение питомца.
/// Само содержимое вкладок переезжает по этапам, см. docs/PORT-PLAN.md.
struct AppShellView: View {
    let model: AppModel

    var body: some View {
        // Подпись вкладки живёт в `Tab`, а не в самом содержимом. Без неё
        // кнопка остаётся без имени и схлопывается в узкую полосу у края.
        TabView {
            Tab("Лента", systemImage: "list.bullet") {
                PlaceholderSection(model: model, title: "Лента", systemImage: "list.bullet")
            }
            Tab("Лекарства", systemImage: "pills") {
                PlaceholderSection(model: model, title: "Лекарства", systemImage: "pills")
            }
            Tab("Медкарта", systemImage: "cross.case") {
                PlaceholderSection(model: model, title: "Медкарта", systemImage: "cross.case")
            }
            Tab("Документы", systemImage: "doc") {
                PlaceholderSection(model: model, title: "Документы", systemImage: "doc")
            }
            Tab("Настройки", systemImage: "gearshape") {
                SettingsSection(model: model)
            }
        }
        .task { await model.loadPets() }
    }
}

/// Настройки переезжают на этапе 9, но выход из аккаунта нужен уже сейчас:
/// без него из приложения не выйти, а человеку не нужно выгружать телефон,
/// чтобы сменить пользователя.
private struct SettingsSection: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Button("Выйти", role: .destructive, action: model.signOut)
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: model) }
            }
        }
    }
}

/// Заглушка раздела, который ещё не перенесён. Показывает честное «ещё нет»,
/// а не пустой список: пустой список читается как «у питомца нет записей».
private struct PlaceholderSection: View {
    let model: AppModel
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: model) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Не загрузились питомцы, а с ними и весь смысл раздела. Показываем
        // это на весь экран, а не мелкой строкой в панели.
        if case let .failed(text) = model.petsState {
            ContentUnavailableView {
                Label("Не загрузилось", systemImage: "exclamationmark.triangle")
            } description: {
                Text(text)
            } actions: {
                Button("Повторить") { Task { await model.loadPets() } }
            }
        } else {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text("Этот раздел ещё не перенесён сюда")
            }
        }
    }
}

/// Переключатель питомца. Живёт в панели слева, где в вебе тоже стоит выбор
/// питомца. Кнопка «+» сюда не попадает: она добавляет запись в ленте,
/// а лента переезжает на этапе 2.
struct PetSwitcher: View {
    let model: AppModel

    var body: some View {
        switch model.petsState {
        case .loading:
            ProgressView()
        case .failed:
            // Причина уже показана на весь экран, второй раз в панели не надо.
            EmptyView()
        case .loaded:
            Menu {
                ForEach(model.pets) { pet in
                    Button { model.select(petID: pet.id) } label: {
                        if pet.id == model.selectedPetID {
                            Label(pet.name, systemImage: "checkmark")
                        } else {
                            Text(pet.name)
                        }
                    }
                }
            } label: {
                Label(model.selectedPet?.name ?? "Питомец", systemImage: "pawprint")
            }
        }
    }
}
