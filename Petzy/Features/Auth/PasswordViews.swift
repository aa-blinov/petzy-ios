import SwiftUI

/// Просьба о ссылке для смены пароля. Ответ сервера один и тот же на любой
/// логин: сказать «такого аккаунта нет» значит дать проверить, кто записан.
struct ForgotPasswordView: View {
    let model: AuthFlowModel

    @Environment(\.dismiss) private var dismiss
    @State private var login = ""

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
                if let notice = model.notice {
                    Section {
                        Label(notice, systemImage: "envelope")
                            .font(.subheadline)
                    }
                }
                Section {
                    TextField("Логин или почта", text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .onSubmit(send)
                } footer: {
                    Text("Письмо придёт на подтверждённую почту, а ссылка из него работает час")
                }
            }
            .navigationTitle("Забыли пароль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить", action: send)
                        .disabled(login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func send() {
        Task { await model.forgotPassword(login: login) }
    }
}

/// Новый пароль по ссылке из письма. Ссылка проверяется сразу: истёкшая должна
/// сказать об этом до того, как человек наберёт пароль.
struct ResetPasswordView: View {
    @Bindable var model: AuthFlowModel
    let token: String
    let onDone: () -> Void

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
                    SecureField("Новый пароль", text: $model.password)
                        .textContentType(.newPassword)
                } footer: {
                    Text("После смены пароля другие устройства выйдут из аккаунта")
                }
            }
            .navigationTitle("Новый пароль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { reset() }
                        .disabled(model.password.isEmpty || model.isResetLinkDead)
                }
            }
            // Привязано к токену, а не к появлению вида: вторая ссылка из
            // свежего письма открывает тот же экран заново, и без этого человек
            // увидел бы результат проверки прошлой ссылки.
            .task(id: token) { await model.checkResetLink(token) }
        }
    }

    private func reset() {
        Task {
            if await model.resetPassword(token: token) {
                onDone()
            }
        }
    }
}

/// Подтверждение почты по ссылке из письма.
struct VerifyEmailView: View {
    let model: AuthFlowModel
    let token: String
    let onDone: () -> Void

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
                if let notice = model.notice {
                    Section {
                        Label(notice, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }
                Section {
                    Text("Подтвердите адрес, чтобы можно было вернуть пароль")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Почта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Подтвердить") { Task { _ = await model.verifyEmail(token: token) } }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", action: onDone)
                }
            }
        }
    }
}
