import SwiftUI

struct LoginView: View {
    let isSigningIn: Bool
    let errorText: String?
    let onSignIn: (String, String) async -> Void

    /// По умолчанию пусто. UI-тест подставляет учётные данные через переменные
    /// окружения запуска (`PETZY_TEST_LOGIN`, `PETZY_TEST_PASSWORD`): софтверная
    /// клавиатура симулятора в этом окружении теряет буквы, и набирать пароль
    /// через `typeText` было бы ненадёжно.
    @State private var username = ProcessInfo.processInfo.environment["PETZY_TEST_LOGIN"] ?? ""
    @State private var password = ProcessInfo.processInfo.environment["PETZY_TEST_PASSWORD"] ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Логин", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)

                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        // Пароль нельзя начинать с заглавной и нельзя «исправлять»
                        // по словарю: иначе введённое не совпадёт с настоящим.
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(submit)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        if isSigningIn {
                            ProgressView()
                        } else {
                            Text("Войти")
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Войти")
        }
    }

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !isSigningIn
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await onSignIn(username, password) }
    }
}
