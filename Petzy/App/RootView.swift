import SwiftUI

struct RootView: View {
    let model: AppModel
    let flow: AuthFlowModel

    /// Ссылка из письма. Пока у приложения нет подписи разработчика, письмо
    /// открывает веб-версию, а сюда попадёт ссылка вида `petzy://`.
    @State private var link: AppLink?

    var body: some View {
        Group {
            if let link {
                linkScreen(link)
            } else {
                main
            }
        }
        .task { await model.start() }
        .onOpenURL { url in
            link = AppLink.parse(url)
        }
    }

    @ViewBuilder
    private var main: some View {
        switch model.state {
        case .restoring:
            ProgressView()
        case .signedOut:
            LoginView(model: model, flow: flow)
        case .signedIn:
            if model.privacyConsentNeeded {
                PrivacyView(model: flow, showsAgree: true) { model.acceptPrivacyConsent() }
            } else {
                AppShellView(model: model, flow: flow)
            }
        }
    }

    @ViewBuilder
    private func linkScreen(_ link: AppLink) -> some View {
        switch link {
        case let .resetPassword(token):
            ResetPasswordView(model: flow, token: token) { self.link = nil }
        case let .verifyEmail(token):
            VerifyEmailView(model: flow, token: token) { self.link = nil }
        }
    }
}
