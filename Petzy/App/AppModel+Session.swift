import Foundation

extension AppModel {
    /// Администратор ли человек. Пока не узнали, список пользователей в
    /// настройках не показывается: сервер всё равно откажет.
    func loadAdminRights() async {
        isAdmin = await (try? AccountAPI.isAdmin(client)) ?? false
    }
}

extension AppModel {
    /// Вошёл ли человек: после регистрации и смены пароля по ссылке да, хотя
    /// форма входа их не показывала.
    var isSignedIn: Bool {
        state == .signedIn
    }

    /// Сессия началась не через форму входа: регистрация и смена пароля по
    /// ссылке отдают токены сразу и заводят человека внутрь приложения.
    func acceptSession() {
        state = .signedIn
        errorText = nil
    }

    /// Согласие спрашивается при каждом входе: редакция политики может
    /// поменяться, пока телефон лежал в кармане. Ответ не пришёл — вопрос не
    /// показываем: лучше пропустить проверку, чем застрять на пустом экране.
    func loadConsent() async {
        privacyConsentNeeded = await (try? AccountAPI.consentNeeded(client)) ?? false
    }

    func acceptPrivacyConsent() {
        privacyConsentNeeded = false
    }

    /// Человек ещё не видел первый экран с объяснением.
    var needsOnboarding: Bool {
        !defaults.bool(forKey: Self.onboardingKey)
    }

    func skipOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
    }
}
