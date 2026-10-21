import Foundation

extension AppModel {
    /// Права администратора и логин человека. Один маршрут `/api/auth/session`
    /// отдаёт и то, и другое. Логин нужен, чтобы копия дневника принадлежала
    /// своему человеку: на общем устройстве следующий вошедший не должен видеть
    /// чужой дневник.
    func loadSession() async {
        guard let session = try? await AccountAPI.session(client) else { return }
        isAdmin = session.isAdmin
        bindUser(session.username)
        // Приглашения к чужим питомцам приходят с сессией: они не про
        // выбранного питомца, а про человека.
        await loadInvites()
        // Напоминания пересобираются при каждом входе: расписание могли
        // поменять с другого устройства, а план в системе от этого не
        // обновляется сам.
        await refreshRemindersFromServer()
    }
}

extension AppModel {
    /// Копию показывают только её владельцу: на общем устройстве следующий
    /// вошедший не должен видеть чужой дневник.
    var canUseDiary: Bool {
        offline.belongs(to: currentUser)
    }

    /// Логин человека, которому принадлежит открытый дневник и копия на
    /// устройстве.
    func bindUser(_ username: String?) {
        currentUser = username
        defaults.set(username, forKey: Self.currentUserKey)
        offline.bind(owner: username)
    }

    /// Выход из аккаунта. Дневник с устройства уходит вместе с ним: человек
    /// нажал «Выйти», и его записи здесь не остаются.
    func signOut() {
        endSession(clearsDiary: true)
    }

    /// Сессия кончилась сама, без выхода: человек этого не выбирал, и в
    /// следующий раз ему покажут его записи. Поэтому копия дневника с
    /// устройства не уходит — уйдёт, когда за её владельцем придёт другой
    /// человек.
    func endSession(clearsDiary: Bool = false) {
        Task { await auth.signOut() }
        errorText = nil
        state = .signedOut
        if clearsDiary {
            offline.clear()
            bindUser(nil)
        }
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
    ///
    /// Логин, когда он известен, — это логин из формы. При смене пароля по
    /// ссылке его узнает сервер, и тогда копия дневника становится его.
    func acceptSession(username: String? = nil) async {
        state = .signedIn
        errorText = nil
        if let username {
            bindUser(username)
        }
        await loadSession()
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
    func skipOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
        needsOnboarding = false
    }
}
