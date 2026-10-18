import SwiftUI

@main
struct PetzyApp: App {
    @State private var model = AppModel(
        auth: AuthSession(baseURL: AppConfig.baseURL, urlSession: AppConfig.urlSession)
    )

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Accent.color)
                // Интерфейс русский и переключения языка в нём нет, поэтому локаль
                // задана явно: на английском устройстве дата в форме выходила бы
                // как «18 Oct 2026», а в ленте «Сегодня» и в числах — как деньги.
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}
