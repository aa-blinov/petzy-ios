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
}
