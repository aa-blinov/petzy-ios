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
