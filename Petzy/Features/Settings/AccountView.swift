import SwiftUI

/// Аккаунт: почта для восстановления пароля, смена пароля и удаление. Один
/// экран, а не три: всё здесь про одно и то же, и разводить по вложенным
/// экранам незачем.
struct AccountView: View {
    @State private var model: AccountModel

    @State private var askingDelete = false

    init(client: APIClient, auth: AuthSession, app: AppModel) {
        _model = State(initialValue: AccountModel(client: client, auth: auth, app: app))
    }

    var body: some View {
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
            identity
            emailSection
            passwordSection
            deletion
        }
        .navigationTitle("Аккаунт")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .alert("Удалить аккаунт?", isPresented: $askingDelete) {
            Button("Удалить", role: .destructive) { Task { await model.deleteAccount() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(model.plan?.warning ?? "Аккаунт удалится безвозвратно")
        }
    }

    /// Логин и имя. Имя приходят с сервера, а поменять его отсюда нельзя:
    /// такого маршрута у него нет.
    private var identity: some View {
        Section("Кто вы") {
            LabeledContent("Логин", value: model.info?.username ?? "")
            if let name = model.info?.fullNameText {
                LabeledContent("Имя", value: name)
            }
        }
    }

    private var emailSection: some View {
        Section {
            if let pending = model.info?.pendingText {
                Label(pending, systemImage: "envelope.badge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Отправить письмо ещё раз") {
                    Task { await model.resendVerification() }
                }
                .font(.subheadline)
            }
            TextField("Ваша почта", text: $model.email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            SecureField("Ваш пароль", text: $model.emailPassword)
            Button("Сохранить почту") {
                Task { await model.saveEmail() }
            }
        } header: {
            Text("Почта для восстановления пароля")
        } footer: {
            // Письмо о подтверждении на новый адрес, а старый работает, пока
            // новый не подтвердили. Без этой строки человек решит, что почта
            // сменилась сразу.
            Text(model.info?.mailEnabled == false
                ? "Письма на этом сервере не настроены, подтверждение не придёт"
                : "На новый адрес придёт письмо, старый будет работать до подтверждения")
        }
    }

    private var passwordSection: some View {
        Section {
            SecureField("Текущий пароль", text: $model.currentPassword)
            SecureField("Новый пароль", text: $model.newPassword)
            Button("Изменить пароль") {
                Task { await model.changePassword() }
            }
        } header: {
            Text("Пароль")
        } footer: {
            Text("После смены пароля другие устройства выйдут из аккаунта")
        }
    }

    private var deletion: some View {
        Section {
            SecureField("Ваш пароль", text: $model.deletePassword)
            Button("Удалить аккаунт", role: .destructive) {
                // Вопрос ждёт превью: `alert` читает свой текст в момент
                // показа и потом не обновляет его, а «безвозвратно» вместо
                // «перейдут к family» обмануло бы человека.
                Task {
                    await model.prepareDeletion()
                    askingDelete = true
                }
            }
            if let plan = model.plan, !plan.canDelete {
                Text("Аккаунт администратора удалить нельзя")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Удаление аккаунта")
        } footer: {
            Text("Питомцы и все записи удалятся вместе с аккаунтом")
        }
    }
}
