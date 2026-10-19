import SwiftUI

/// Оболочка приложения: пять вкладок веб-клиента и переключение питомца.
/// Само содержимое вкладок переезжает по этапам, см. docs/PORT-PLAN.md.
struct AppShellView: View {
    let model: AppModel
    let flow: AuthFlowModel

    /// Модели разделов живут здесь, а не внутри вкладок: значок на панели вкладок
    /// рисует сам TabView, и содержимое экрана он не видит.
    @State private var medications: MedicationsModel?
    @State private var medicalCard: MedicalCardModel?
    @State private var documents: DocumentsModel?
    @State private var tab: ShellTab = .feed

    /// Повторное нажатие на активную вкладку `TabView` пропускает мимо: выбор
    /// не меняется, и сеттер не вызывается. Своя привязка это видит и
    /// возвращает ленту наверх, как в любом приложении.
    private var tabBinding: Binding<ShellTab> {
        Binding(
            get: { tab },
            set: { new in
                if new == tab, new == .feed {
                    model.scrollFeedToTop()
                }
                tab = new
            }
        )
    }

    var body: some View {
        // Подпись вкладки живёт в `Tab`, а не в самом содержимом. Без неё
        // кнопка остаётся без имени и схлопывается в узкую полосу у края.
        TabView(selection: tabBinding) {
            Tab("Лента", systemImage: "list.bullet", value: .feed) {
                FeedView(model: model)
            }
            Tab("Лекарства", systemImage: "pills", value: .medications) {
                if let medications {
                    MedicationsView(model: medications, app: model)
                }
            }
            // Значок на вкладке: сколько приёмов просрочено. Своей точки
            // значок не рисует, только число, и оно полезнее пустого кружка.
            .badge(medications?.overdueCount ?? 0)
            Tab("Медкарта", systemImage: "cross.case", value: .medicalCard) {
                if let medicalCard {
                    MedicalCardView(model: medicalCard, app: model)
                }
            }
            // Значок считает просроченные прививки и обработки: о них узнают,
            // не заходя внутрь, и он гаснет сам после повторной записи.
            .badge(medicalCard?.overdueCount ?? 0)
            Tab("Документы", systemImage: "doc", value: .documents) {
                if let documents {
                    DocumentsView(model: documents, app: model)
                }
            }
            // Значок считает документы с истёкшим сроком: о них узнают, не
            // заходя внутрь.
            .badge(documents?.expired ?? 0)
            Tab("Настройки", systemImage: "gearshape", value: .settings) {
                SettingsSection(model: model, flow: flow)
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
            // Значения по умолчанию тоже питомца, а не аккаунта: у другого
            // питомца свой набор.
            await model.loadFormDefaults()
        }
    }
}

/// Пять вкладок. Значение нужно для выбора в `TabView`: без него не видно
/// повторное нажатие на активную вкладку.
private enum ShellTab: Hashable {
    case feed
    case medications
    case medicalCard
    case documents
    case settings
}

/// Настройки переезжают на этапе 9, но выход из аккаунта нужен уже сейчас:
/// без него из приложения не выйти, а человеку не нужно выгружать телефон,
/// чтобы сменить пользователя.
private struct SettingsSection: View {
    let model: AppModel
    let flow: AuthFlowModel

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
                    HelpView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Справка", systemImage: "questionmark.circle")
                        Text("Как всё устроено и что делать, если что-то не выходит")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    PrivacyView(model: flow, showsAgree: false) {}
                } label: {
                    Label("Политика обработки данных", systemImage: "hand.raised")
                        .font(.subheadline)
                }
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
                    AccessTokensView(model: AccessTokensModel(client: model.client))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Доступы для ассистентов", systemImage: "key")
                        Text("Токен вместо пароля для человека или скрипта")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    FormDefaultsView(
                        model: FormDefaultsModel(
                            client: model.client,
                            petID: model.selectedPetID ?? "",
                            defaults: model.formDefaults,
                            app: model
                        ),
                        app: model
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Значения по умолчанию", systemImage: "text.badge.checkmark")
                        Text("Чем новая запись открывается уже заполненной")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    CustomTypesView(model: CustomTypesModel(client: model.client))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Свои типы записей", systemImage: "square.stack.3d.up")
                        Text("Своё название и свои поля вместо готовых")
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
                // Панель в iOS 26 сворачивает `Label` до одного значка, а
                // `.labelStyle(.titleAndIcon)` не помогает: имя питомца
                // пропадало, и по одному знаку не видно, чей дневник открыт.
                HStack(spacing: 4) {
                    Image(systemName: "pawprint")
                    Text(model.selectedPet?.name ?? "Питомец")
                }
            }
        }
    }
}
