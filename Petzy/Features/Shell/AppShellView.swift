import SwiftUI

/// Оболочка приложения: пять вкладок веб-клиента и переключение питомца.
/// Само содержимое вкладок переезжает по этапам, см. docs/PORT-PLAN.md.
struct AppShellView: View {
    let model: AppModel

    /// Модели разделов живут здесь, а не внутри вкладок: значок на панели вкладок
    /// рисует сам TabView, и содержимое экрана он не видит.
    @State private var medications: MedicationsModel?
    @State private var medicalCard: MedicalCardModel?
    @State private var documents: DocumentsModel?

    var body: some View {
        // Подпись вкладки живёт в `Tab`, а не в самом содержимом. Без неё
        // кнопка остаётся без имени и схлопывается в узкую полосу у края.
        TabView {
            Tab("Лента", systemImage: "list.bullet") {
                FeedView(model: model)
            }
            Tab("Лекарства", systemImage: "pills") {
                if let medications {
                    MedicationsView(model: medications, app: model)
                }
            }
            // Значок на вкладке: сколько приёмов просрочено. Своей точки
            // значок не рисует, только число, и оно полезнее пустого кружка.
            .badge(medications?.overdueCount ?? 0)
            Tab("Медкарта", systemImage: "cross.case") {
                if let medicalCard {
                    MedicalCardView(model: medicalCard, app: model)
                }
            }
            // Значок считает просроченные прививки и обработки: о них узнают,
            // не заходя внутрь, и он гаснет сам после повторной записи.
            .badge(medicalCard?.overdueCount ?? 0)
            Tab("Документы", systemImage: "doc") {
                if let documents {
                    DocumentsView(model: documents, app: model)
                }
            }
            // Значок считает документы с истёкшим сроком: о них узнают, не
            // заходя внутрь.
            .badge(documents?.expired ?? 0)
            Tab("Настройки", systemImage: "gearshape") {
                SettingsSection(model: model)
            }
        }
        .task { await model.loadPets() }
        .task(id: model.selectedPetID) {
            // Модель пересоздаётся на каждый питомца: питомец приходит в её
            // запросы, и подменить его на ходу значило бы ждать ответа по
            // чужому курсу.
            guard let petID = model.selectedPetID else { return }
            medications = MedicationsModel(client: model.client, petID: petID)
            medicalCard = MedicalCardModel(client: model.client, petID: petID)
            documents = DocumentsModel(client: model.client, petID: petID)
        }
    }
}

/// Настройки переезжают на этапе 9, но выход из аккаунта нужен уже сейчас:
/// без него из приложения не выйти, а человеку не нужно выгружать телефон,
/// чтобы сменить пользователя.
private struct SettingsSection: View {
    let model: AppModel

    @State private var exporting = false
    @State private var addingPet = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PetProfileView(client: model.client, petID: model.selectedPetID, app: model)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("О питомце", systemImage: "pawprint")
                        Text(model.selectedPet?.name ?? "Имя, фото, порода и заметки")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    addingPet = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Добавить питомца", systemImage: "plus.circle")
                        Text("Второй питомец для того же аккаунта")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                // Без `.plain` вся строка красится в акцент и читается как
                // ссылка, а не как пункт настроек рядом с «Историей».
                .buttonStyle(.plain)
                NavigationLink {
                    AccountView(client: model.client, auth: model.auth, app: model)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Аккаунт", systemImage: "person.crop.circle")
                        Text("Почта, пароль и удаление аккаунта")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    HistoryView(model: model)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("История записей", systemImage: "clock.arrow.circlepath")
                        Text("Всё за всё время, фильтр по типу и графики")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    exporting = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Экспорт записей", systemImage: "arrow.down.doc")
                        Text("Скачать записи питомца таблицей")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                // Без `.plain` вся строка красится в акцент и читается как
                // ссылка, а не как пункт настроек рядом с «Историей».
                .buttonStyle(.plain)
                Button("Выйти", role: .destructive, action: model.signOut)
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: model) }
            }
            .sheet(isPresented: $exporting) {
                ExportSheet(model: model)
            }
            .sheet(isPresented: $addingPet) {
                // Свой NavigationStack: лист открывается без оболочки, а панель
                // с «Отмена» и «Сохранить» рисует именно она. Из «Настроек» тот
                // же экран открывается ссылкой внутри их стека.
                NavigationStack {
                    PetProfileView(client: model.client, petID: nil, app: model)
                }
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
