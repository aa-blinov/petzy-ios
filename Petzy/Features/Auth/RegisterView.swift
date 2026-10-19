import SwiftUI

/// Регистрация. Сервер выдаёт токены сразу, поэтому после успеха человек уже
/// внутри приложения и вход ему повторять не нужно.
struct RegisterView: View {
    /// `@Bindable`, а не `let`: форма правит черновик в модели напрямую, и без
    /// этого поля не пишутся.
    @Bindable var model: AuthFlowModel
    let onPolicy: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if let text = model.errorText {
                    Section {
                        Label(text, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    field(
                        TextField("Логин", text: $model.draft.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(),
                        problem: .username
                    )
                    field(
                        TextField("Как к вам обращаться", text: $model.draft.fullName)
                            .textContentType(.name),
                        problem: .fullName
                    )
                    field(
                        SecureField("Пароль", text: $model.draft.password)
                            .textContentType(.newPassword),
                        problem: .password
                    )
                    TextField("Почта для восстановления пароля", text: $model.draft.email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                } header: {
                    Text("Аккаунт")
                } footer: {
                    Text("Почта нужна, чтобы вернуть пароль. Письмо с подтверждением придёт на неё")
                }
                Section {
                    Toggle("Согласен с политикой обработки данных", isOn: $model.draft.consent)
                    if model.problems.contains(.consent) {
                        Text(RegistrationField.consent.text)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Прочитать политику", action: onPolicy)
                        .font(.subheadline)
                }
            }
            .navigationTitle("Новый аккаунт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { register() }
                        .disabled(isSaving)
                }
            }
        }
    }

    /// Поле и подсказка под ним: человек видит, что именно надо заполнить.
    @ViewBuilder
    private func field(_ content: some View, problem which: RegistrationField) -> some View {
        content
        if model.problems.contains(which) {
            Text(which.text)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func register() {
        isSaving = true
        Task {
            // Закрывать лист не нужно: при успехе корень приложения сам
            // переключается на оболочку. А при отказе закрывать нельзя —
            // человек увидел бы пустой экран вместо того, что исправить.
            _ = await model.register()
            isSaving = false
        }
    }
}
