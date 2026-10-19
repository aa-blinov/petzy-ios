import SwiftUI

@main
struct PetzyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model: AppModel
    @State private var flow: AuthFlowModel

    init() {
        let auth = AuthSession(baseURL: AppConfig.baseURL, urlSession: AppConfig.urlSession)
        let app = AppModel(auth: auth)
        // Модель входа одна на всё приложение: её пересоздание на каждом
        // перерисовывании окна теряло бы набранное и отправленные запросы.
        _model = State(initialValue: app)
        _flow = State(initialValue: AuthFlowModel(client: app.client, auth: auth, app: app))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, flow: flow)
                .tint(Accent.color)
                // Интерфейс русский и переключения языка в нём нет, поэтому локаль
                // задана явно: на английском устройстве дата в форме выходила бы
                // как «18 Oct 2026», а в ленте «Сегодня» и в числах — как деньги.
                .environment(\.locale, Locale(identifier: "ru_RU"))
                // Человек вышел из метро и открыл приложение: связь появилась,
                // и записи, ждавшие её, должны уйти сами.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.flushQueue() }
                }
        }
    }
}
