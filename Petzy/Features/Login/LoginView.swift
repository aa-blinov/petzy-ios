import SwiftUI

struct LoginView: View {
    let model: AppModel
    let flow: AuthFlowModel

    /// По умолчанию пусто. UI-тест подставляет учётные данные через переменные
    /// окружения запуска (`PETZY_TEST_LOGIN`, `PETZY_TEST_PASSWORD`): софтверная
    /// клавиатура симулятора в этом окружении теряет буквы, и набирать пароль
    /// через `typeText` было бы ненадёжно.
    @State private var username = ProcessInfo.processInfo.environment["PETZY_TEST_LOGIN"] ?? ""
    @State private var password = ProcessInfo.processInfo.environment["PETZY_TEST_PASSWORD"] ?? ""
    @State private var registering = false
    @State private var forgot = false

    /// Какое поле сейчас в фокусе. Return в «Логине» ведёт в «Пароль»:
    /// без этого подпись «Далее» на клавиатуре обещает переход, а ничего не
    /// делает.
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case login
        case password
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.needsOnboarding {
                    OnboardingView(
                        onDone: model.skipOnboarding,
                        onRegister: { model.skipOnboarding(); registering = true }
                    )
                } else {
                    form
                }
            }
            .navigationTitle("Войти")
            // На первом экране заголовок «Войти» ничего не объясняет: там ещё
            // нет ни входа, ни регистрации.
            .toolbar(model.needsOnboarding ? .hidden : .visible, for: .navigationBar)
            .task { await flow.loadRegistrationStatus() }
            .sheet(isPresented: $registering) {
                RegisterView(model: flow)
            }
            .sheet(isPresented: $forgot) {
                ForgotPasswordView(model: flow)
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                // Подпись стоит рядом с полем, а не вместо него: плейсхолдер
                // исчезает от первого символа, и поле оставалось без ничего, а
                // строка ошибки под ним повторяла ту же фразу. Подсказка —
                // пример, а не указание.
                LabeledContent("Логин") {
                    TextField("например, demo", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.next)
                        .focused($focus, equals: .login)
                        .onSubmit { focus = .password }
                }

                LabeledContent("Пароль") {
                    // Плейсхолдера нет вовсе: подпись и ошибка говорят всё, а
                    // пустая подсказка оставила бы строку без единого слова.
                    SecureField("", text: $password)
                        .textContentType(.password)
                        // Пароль нельзя начинать с заглавной и нельзя
                        // «исправлять» по словарю: иначе введённое не совпадёт с
                        // настоящим.
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit(submit)
                }
            }

            if let errorText = model.errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: submit) {
                    if model.isSigningIn {
                        ProgressView()
                    } else {
                        Text("Войти")
                    }
                }
                .disabled(!canSubmit)
            }

            Section {
                Button("Забыли пароль?") { forgot = true }
                // Кнопки регистрации нет, когда сервер её закрыл: человек не
                // должен упираться в отказ после заполнения всей формы.
                if flow.registrationIsOpen {
                    Button("Создать аккаунт") { registering = true }
                }
                NavigationLink {
                    HelpView()
                } label: {
                    Text("Справка")
                }
                .font(.subheadline)
            }
        }
    }

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !model.isSigningIn
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await model.signIn(username: username, password: password) }
    }
}
