import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .restoring:
                ProgressView()
            case .signedOut:
                LoginView(
                    isSigningIn: model.isSigningIn,
                    errorText: model.errorText,
                    onSignIn: model.signIn
                )
            case .signedIn:
                PetListView(client: model.client, onSignOut: model.signOut)
            }
        }
        .task { await model.start() }
    }
}
