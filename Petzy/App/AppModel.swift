import Foundation
import Observation

/// Состояние списка питомцев. Тот же набор, что был в списке питомцев:
/// грузим, показали или объяснили, почему не вышло.
enum PetsState: Equatable {
    case loading
    case loaded([Pet])
    case failed(String)
}

/// Состояние приложения: вход и то, чей дневник открыт.
@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn
    }

    /// Идентификатор выбранного питомца в UserDefaults. Это не секрет, Keychain
    /// тут не нужен; секрет только у refresh-токена.
    private static let selectedPetKey = "selectedPetId"

    private(set) var state: State = .restoring
    private(set) var isSigningIn = false
    var errorText: String?

    private(set) var petsState: PetsState = .loading
    private(set) var selectedPetID: String?

    /// Дни ленты выбранного питомца. Сами записи лежат в `rawEvents`: дни
    /// собираются из них на показ, иначе догруженная страница не срослась бы
    /// с уже показанными днями.
    private(set) var rawEvents: [PetEvent] = []
    private(set) var feedNextCursor: String?
    private(set) var hasMoreEvents = false
    private(set) var isLoadingFeed = false
    private(set) var feedErrorText: String?
    var eventTypes: [String: EventTypeInfo] = [:]

    /// Типы, записи о которых у питомца есть. В фильтре истории показываются
    /// только они: питомцу, у которого никогда не было температуры,
    /// «Температура» предлагать незачем.
    var usedTypes: [String] = []
    var historyRaw: [PetEvent] = []
    var historyCursor: String?
    var hasMoreHistory = false
    var isLoadingHistory = false
    var historyErrorText: String?
    /// Выбранный фильтр по типу. `nil` — «Все».
    var historyType: String?
    var statsPoints: [EventStatsPoint] = []
    /// Свойства истории меняются из `AppModel+History.swift`, а `private(set)`
    /// не даёт сеттеру выйти за пределы файла объявления.
    ///
    /// Тип, по которому грузились точки графика. Точки всегда относятся к
    /// нему, и держать рядом ещё и выбранный фильтр означало бы, что график
    /// исчезает при смене фильтра на «Все», хотя точки на экране ещё есть.
    var statsType: String?
    /// Выбранный период графика в днях.
    var statsPeriodDays = 30
    /// Выбор в выгрузке живёт в модели, а не во `@State` вида: вкладка
    /// пересоздаётся, когда меняется состояние модели, и выбранный тип
    /// возвращался бы к «Все» прямо на глазах у человека.
    var exportType = "all"
    var exportFormat = "csv"
    var isExporting = false
    var exportErrorText: String?
    /// Последний выгруженный файл: из него открывается системный лист
    /// «Поделиться».
    var exportedFile: URL?

    /// Готовая лента по дням. Пусто, пока грузится или грузить нечего.
    var days: [EventDay] {
        Feed.group(rawEvents, knownTypes: Set(eventTypes.keys))
    }

    /// Типы записи для выбора под кнопкой «+». Порядок внутри групп задаёт
    /// сравнение по-русски: справочник приходит словарём, порядок в нём
    /// никакой.
    var typeCatalog: [EventTypeInfo] {
        eventTypes.values.sorted {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    /// Описание типа по ключу. `nil`, если тип не пришёл: правку незнакомой
    /// записи открыть нечем, и лучше ничего не сделать, чем показать пустую форму.
    func typeInfo(for key: String) -> EventTypeInfo? {
        eventTypes[key]
    }

    /// Питомцы из последнего успешного ответа. Пустой список, пока грузится
    /// или грузить нечего.
    var pets: [Pet] {
        if case let .loaded(pets) = petsState {
            return pets
        }
        return []
    }

    /// Питомец, чей дневник открыт. `nil`, пока список не пришёл.
    var selectedPet: Pet? {
        pets.first { $0.id == selectedPetID }
    }

    let client: APIClient
    private let auth: AuthSession
    private let defaults: UserDefaults

    /// Адрес и сеанс принимаются параметрами, а не берутся из `AppConfig`
    /// внутри: иначе модель нельзя проверить, запросы уходят мимо заглушки.
    init(
        auth: AuthSession,
        baseURL: URL = AppConfig.baseURL,
        urlSession: URLSession = AppConfig.urlSession,
        defaults: UserDefaults = .standard
    ) {
        self.auth = auth
        self.defaults = defaults
        selectedPetID = defaults.string(forKey: Self.selectedPetKey)
        client = APIClient(baseURL: baseURL, urlSession: urlSession, auth: auth)
    }

    /// Выбор питомца сохраняется сразу: переживать перезапуск должен и тот
    /// выбор, который пользователь ещё не успел увидеть на экране.
    func select(petID: String?) {
        selectedPetID = petID
        defaults.set(petID, forKey: Self.selectedPetKey)
    }

    func loadPets() async {
        petsState = .loading
        do {
            let response = try await client.get("/api/pets", as: PetsResponse.self)
            petsState = .loaded(response.pets)
            // Питомца могли удалить или переименовать на другом устройстве, пока
            // телефон лежал в кармане. Молча открываем первого: иначе оболочка
            // осталась бы с выбором, которого в списке нет.
            if !response.pets.contains(where: { $0.id == selectedPetID }) {
                select(petID: response.pets.first?.id)
            }
        } catch {
            let apiError = error as? APIError
            if apiError?.isAuthProblem == true {
                signOut()
                return
            }
            petsState = .failed(apiError?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Первая страница ленты: заново, со справочником типов и выбранным питомцем.
    func loadFeed() async {
        guard let petID = selectedPetID else { return }
        rawEvents = []
        feedNextCursor = nil
        hasMoreEvents = false
        feedErrorText = nil
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            // Типы нужны и для названия записи, и для значка. Без них запись
            // неизвестного вида пришлось бы выкинуть, а это молчаливая потеря.
            let types = try await client.get("/api/event-types", as: EventTypesResponse.self)
            eventTypes = Dictionary(types.eventTypes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            try await apply(fetchPage(petID: petID, before: nil), appending: false)
        } catch {
            handleFeedError(error)
        }
    }

    /// Следующая страница по курсору. Догружать нечего — запроса не будет:
    /// лишний запрос на последней странице это и лишний шаг к лимиту входа.
    func loadMore() async {
        guard hasMoreEvents, let cursor = feedNextCursor, let petID = selectedPetID else { return }
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            try await apply(fetchPage(petID: petID, before: cursor), appending: true)
        } catch {
            handleFeedError(error)
        }
    }

    /// Сохраняет новую запись и, если получилось, перечитывает ленту: запись
    /// должна появиться сразу, а не после ручного обновления.
    func createEvent(_ draft: EventDraft) async {
        guard let petID = selectedPetID else { return }
        feedErrorText = nil
        do {
            let request = EventRequest.create(draft, petID: petID)
            _ = try await client.post("/api/events", body: request, as: EventSavedResponse.self)
            await loadFeed()
        } catch {
            handleFeedError(error)
        }
    }

    /// Правка существующей записи.
    func updateEvent(id: String, draft: EventDraft) async {
        feedErrorText = nil
        do {
            let request = EventRequest.update(draft)
            _ = try await client.put("/api/events/\(id)", body: request, as: EventSavedResponse.self)
            await loadFeed()
        } catch {
            handleFeedError(error)
        }
    }

    /// Удаление. Убираем из своей копии только после ответа сервера: иначе
    /// запись исчезла бы с экрана, но осталась бы в базе, и человек бы её
    /// искал, думая, что неудачно сохранил.
    func deleteEvent(id: String) async {
        feedErrorText = nil
        do {
            try await client.delete("/api/events/\(id)")
            rawEvents.removeAll { $0.id == id }
        } catch {
            handleFeedError(error)
        }
    }

    /// Название типа записи, каким его знает справочник.
    func label(for type: String) -> String {
        eventTypes[type]?.label ?? type
    }

    /// Имя из набора веба переводится в значок системы, иначе значок был бы пустым.
    func icon(for type: String) -> String {
        EventIcon.symbol(for: eventTypes[type]?.icon)
    }

    /// Подпись поля так, как её назвал человек, а не ключ из записи.
    func fieldLabel(_ name: String, of type: String) -> String {
        eventTypes[type]?.fields.first { $0.name == name }?.label ?? name
    }

    private func fetchPage(petID: String, before: String?) async throws -> EventsPage {
        // with_deleted=1: удалённая запись приходит надгробием, и приложение
        // знает, что её надо убрать из своей копии. Сами надгробия на показ
        // не идут, их отсекает Feed.group.
        var path = "/api/events?with_deleted=1&page_size=100&pet_id=" + Self.query(petID)
        if let before {
            path += "&before=" + Self.query(before)
        }
        return try await client.get(path, as: EventsPage.self)
    }

    private func apply(_ page: EventsPage, appending: Bool) {
        rawEvents = appending ? rawEvents + page.items : page.items
        feedNextCursor = page.nextCursor
        hasMoreEvents = page.nextCursor != nil
    }

    private func handleFeedError(_ error: Error) {
        let apiError = error as? APIError
        if apiError?.isAuthProblem == true {
            signOut()
            return
        }
        feedErrorText = apiError?.errorDescription ?? error.localizedDescription
    }

    /// Экранирование значения для строки запроса. `nonisolated`, потому что
    /// пути строит и слой API, а он не привязан к главному актору.
    nonisolated static func query(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    func start() async {
        // Прогон UI-теста начинает с чистого листа: Keychain от прошлого раза
        // иначе уводит с экрана входа, и проверять вход нечем.
        if ProcessInfo.processInfo.arguments.contains("-uiTestSignedOut") {
            await auth.signOut()
        }
        await auth.restore()
        state = await auth.isSignedIn ? .signedIn : .signedOut
    }

    func signIn(username: String, password: String) async {
        isSigningIn = true
        errorText = nil
        defer { isSigningIn = false }

        do {
            try await auth.signIn(username: username, password: password)
            state = .signedIn
        } catch {
            // Неверный пароль приходит 401, но текст здесь серверный:
            // «Неверный логин или пароль», а не «сессия закончилась».
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
            state = .signedOut
        }
    }

    func signOut() {
        Task { await auth.signOut() }
        errorText = nil
        state = .signedOut
    }
}
