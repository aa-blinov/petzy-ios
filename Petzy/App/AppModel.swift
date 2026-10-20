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

    /// Показывалось ли первое знакомство с приложением. Ключ в UserDefaults:
    /// это не секрет, Keychain тут не нужен.
    static let onboardingKey = "seenOnboarding"

    var state: State = .restoring
    private(set) var isSigningIn = false
    /// Человек ещё не видел первый экран с объяснением. Отдельное поле, а не
    /// чтение `UserDefaults` на лету: запись в настройки экран не
    /// перерисовывает, и знакомство оставалось бы до перезапуска.
    internal(set) var needsOnboarding: Bool
    /// Администратор ли человек: только ему показывается список пользователей.
    var isAdmin = false
    var errorText: String?

    /// Требуется ли согласие с текущей редакцией политики. Сервер поднимает
    /// этот флаг, когда аккаунт создан администратором или когда политику
    /// поменяли после того, как человек с ней соглашался. Пишется из
    /// `AppModel+Session.swift`, поэтому без `private(set)`.
    var privacyConsentNeeded = false

    private(set) var petsState: PetsState = .loading
    private(set) var selectedPetID: String?

    /// Дни ленты выбранного питомца. Сами записи лежат в `rawEvents`: дни
    /// собираются из них на показ, иначе догруженная страница не срослась бы
    /// с уже показанными днями.
    /// Записи на показ. Пишет сюда и офлайн-слой из `AppModel+Feed.swift`,
    /// поэтому без `private(set)`, как и `historyRaw` рядом.
    var rawEvents: [PetEvent] = []
    /// Пишется из `AppModel+Feed.swift`, поэтому без `private(set)`, как
    /// и `historyCursor` рядом.
    var feedNextCursor: String?
    var hasMoreEvents = false
    /// Значения по умолчанию выбранного питомца: ими открывается новая запись.
    var formDefaults: FormDefaults = [:]
    private(set) var isLoadingFeed = false
    /// Едет ли следующая страница. Отдельный флаг от `isLoadingFeed`: первая
    /// страница и догрузка ходят в разное время, и догрузка не должна ждать
    /// первой — но и две догрузки одна за другой читать одну страницу нельзя,
    /// иначе записи покажутся дважды.
    private(set) var isLoadingMore = false
    var feedErrorText: String?
    /// Идёт ли отправка очереди. Отправка перечитывает ленту, а лента после
    /// успешной загрузки отправляет очередь: без этого флага они бы гоняли
    /// друг друга по кругу.
    var flushingPending = false
    /// Счётчик прокрутки ленты наверх. Повторное нажатие на активную вкладку
    /// само по себе ни к чему не приводит, а «В начало» ожидают от любого
    /// приложения. Счётчик, а не флаг: два нажатия подряд это два события.
    private(set) var feedScrollToTop = 0
    /// Что сказать о сохранённой записи, которой нет в загруженной части
    /// ленты. Запись с датой в прошлом после сохранения просто исчезает, и
    /// человек решает, что она не записалась.
    var feedNotice: String?
    /// Сколько страниц сверх первой дочитал человек и чей это дневник: у
    /// другого питомца своей второй страницы может не быть.
    private var feedDepth = 0
    private var feedPetID: String?
    var eventTypes: [String: EventTypeInfo] = [:]

    /// Типы, записи о которых у питомца есть. В фильтре истории показываются
    /// только они: питомцу, у которого никогда не было температуры,
    /// «Температура» предлагать незачем.
    var usedTypes: [String] = []
    var historyRaw: [PetEvent] = []
    var historyCursor: String?
    var hasMoreHistory = false
    var isLoadingHistory = false
    /// Открывали ли историю. После правки записи её перечитываем, но только
    /// если человек её уже видел: незапрошенная история грузиться не должна.
    var isHistoryLoaded = false
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
    /// Сессия открыта наружу: смена пароля возвращает новую пару токенов, и её
    /// обязан положить в хранилище тот, кто отправил запрос.
    let auth: AuthSession
    let defaults: UserDefaults
    /// Копия, очередь записей и признак «на экране копия».
    let offline: OfflineState
    /// Что сервер отказал отправить: «Запись изменили, пока вы её правили» и
    /// подобное. Человек должен узнать, что его правку затёрли, а не гадать.
    var queueRefusals: [String] = []

    /// Сколько раз очередь уходила на сервер. Разделы перечитываются по этому
    /// счётчику: отправленный курс должен появиться в списке сам, а не после
    /// ручного обновления. Пишет сюда `AppModel+Feed.swift`, поэтому без
    /// `private(set)`, как и `historyRaw` рядом.
    var queueFlushCount = 0

    /// Адрес и сеанс принимаются параметрами, а не берутся из `AppConfig`
    /// внутри: иначе модель нельзя проверить, запросы уходят мимо заглушки.
    init(
        auth: AuthSession,
        baseURL: URL = AppConfig.baseURL,
        urlSession: URLSession = AppConfig.urlSession,
        defaults: UserDefaults = .standard,
        store: LocalStore = LocalStore()
    ) {
        self.auth = auth
        self.defaults = defaults
        offline = OfflineState(store: store)
        selectedPetID = defaults.string(forKey: Self.selectedPetKey)
        needsOnboarding = !defaults.bool(forKey: Self.onboardingKey)
        client = APIClient(baseURL: baseURL, urlSession: urlSession, auth: auth)
    }

    /// Выбор питомца сохраняется сразу: переживать перезапуск должен и тот
    /// выбор, который пользователь ещё не успел увидеть на экране.
    func select(petID: String?) {
        let changed = selectedPetID != petID
        selectedPetID = petID
        defaults.set(petID, forKey: Self.selectedPetKey)
        guard changed else { return }
        // Фильтр истории принадлежит питомцу: оставленный от прежнего, он
        // показывал новому пустую историю, и человек думал, что записей нет.
        historyType = nil
        historyRaw = []
        historyCursor = nil
        isHistoryLoaded = false
        statsType = nil
        statsPoints = []
        // Типы тоже принадлежат питомцу: у нового их может не быть, а чужие
        // типы в фильтре истории и в выгрузке только сбивают с толку.
        usedTypes = []
        // Тип в выгрузке должен быть среди типов нового питомца, иначе
        // переключатель показывает пустоту.
        exportType = "all"
    }

    func loadPets() async {
        petsState = .loading
        do {
            let response = try await client.get("/api/pets", as: PetsResponse.self)
            petsState = .loaded(response.pets)
            offline.cache(
                events: rawEvents,
                types: eventTypes,
                pets: response.pets,
                petID: selectedPetID ?? ""
            )

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
            // Без связи питомцы берутся из копии: иначе приложение не знает,
            // чей дневник открыт, и переключатель с именем исчезают, хотя
            // лента и разделы из копии показываются.
            if apiError?.isTransport == true, !offline.snapshot.pets.isEmpty {
                petsState = .loaded(offline.snapshot.pets)
                return
            }
            petsState = .failed(apiError?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Первая страница ленты: заново, со справочником типов и выбранным питомцем.
    func loadFeed() async {
        guard let petID = selectedPetID else {
            // Питомца нет: ленты тоже нет, а чужая ошибка на экране («Питомец
            // не найден») сбивала бы с толку и не уходила по «Повторить».
            rawEvents = []
            feedErrorText = nil
            return
        }
        if feedPetID != petID {
            feedDepth = 0
            feedPetID = petID
        }
        // Сколько страниц человек уже дочитал. Лента после сохранения записи
        // читается заново первой страницей, и без этого человек терял место,
        // до которого дочитал, и догружал всё заново.
        let depth = feedDepth
        // Копия показывается до первого запроса: без связи человек увидит
        // дневник сразу, а не после ожидания, которое ничем не кончится.
        restoreFromCache()
        feedErrorText = nil
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            // Типы нужны и для названия записи, и для значка. Без них запись
            // неизвестного вида пришлось бы выкинуть, а это молчаливая потеря.
            let types = try await client.get("/api/event-types", as: EventTypesResponse.self)
            eventTypes = Dictionary(types.eventTypes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            // Список не чистим заранее: неудачный запрос не должен оставлять
            // на экране пустоту вместо того, что человек уже видел.
            try await apply(fetchPage(petID: petID, before: nil), appending: false)
            offline.isShowingCached = false
            showPending()
            offline.cache(events: rawEvents, types: eventTypes, pets: pets, petID: petID)
            // Сеть появилась: накопленное уходит само, без всякой кнопки.
            if offline.pendingCount > 0 {
                await flushQueue()
            }
            // Глубина восстанавливается, а не растёт. `loadMore` сам её
            // наращивает на каждую дочитанную страницу, и без сброса каждое
            // перечитывание ленты читало бы вдвое больше страниц, чем человек
            // дочитал: 1, 2, 4, 8... Никто этого не просил, а лимит запросов
            // и трафик страдали.
            feedDepth = 0
            for _ in 0 ..< depth {
                await loadMore()
            }
        } catch {
            handleFeedError(error)
        }
    }

    /// Следующая страница по курсору. Догружать нечего — запроса не будет:
    /// лишний запрос на последней странице это и лишний шаг к лимиту входа.
    func loadMore() async {
        guard hasMoreEvents, let cursor = feedNextCursor, let petID = selectedPetID, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            try await apply(fetchPage(petID: petID, before: cursor), appending: true)
            feedDepth += 1
        } catch {
            handleFeedError(error)
        }
    }

    /// Вернуть ленту наверх. Просьба приходит из вкладки: `TabView` о
    /// повторном нажатии на активную вкладку молчит.
    func scrollFeedToTop() {
        feedScrollToTop += 1
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
            // UI-тест проверяет вход, а не знакомство: первый экран спросил бы
            // лишний тап и уводил с экрана входа.
            skipOnboarding()
        }
        // Обратный случай: тест знакомства хочет увидеть первый экран, а
        // знакомство на телефоне уже пройдено.
        if ProcessInfo.processInfo.arguments.contains("-uiTestOnboarding") {
            defaults.set(false, forKey: Self.onboardingKey)
            needsOnboarding = true
        }
        await auth.restore()
        state = await auth.isSignedIn ? .signedIn : .signedOut
        if state == .signedIn {
            await loadConsent()
            await loadAdminRights()
        }
    }

    func signIn(username: String, password: String) async {
        isSigningIn = true
        errorText = nil
        defer { isSigningIn = false }

        do {
            try await auth.signIn(username: username, password: password)
            state = .signedIn
            await loadAdminRights()
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
