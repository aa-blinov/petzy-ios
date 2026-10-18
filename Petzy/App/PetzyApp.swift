import SwiftUI

@main
struct PetzyApp: App {
    @State private var model = AppModel(
        auth: AuthSession(baseURL: AppConfig.baseURL, urlSession: AppConfig.urlSession)
    )

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
