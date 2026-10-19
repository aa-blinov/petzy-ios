import SwiftUI

/// Пользователи: список, поиск, создание, правка и отключение. Экран
/// виден только администратору, остальным сервер всё равно откажет.
struct UsersView: View {
    /// Поиск привязан к модели, поэтому она нужна как `@Bindable`: поле ищет
    /// само, а не по кнопке.
    @Bindable var model: UsersModel

    @State private var adding = false
    @State private var editing: UserInfo?
    @State private var isEditing = false

    var body: some View {
        List {
            failure
            if model.users.isEmpty, !model.isLoading, model.errorText == nil {
                Section {
                    Text(model.query.isEmpty ? "Пользователей нет" : "Никого не нашлось")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(model.users) { user in
                        row(user)
                    }
                } header: {
                    Text("Всего \(model.total)")
                }
            }
        }
        .navigationTitle("Пользователи")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, prompt: "Логин или имя")
        .onChange(of: model.query) { model.searchChanged() }
        .navigationDestination(isPresented: $isEditing) {
            if let editing {
                UserFormView(model: model, user: editing)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $adding) {
            NavigationStack {
                UserFormView(model: model, user: nil)
            }
        }
    }

    @ViewBuilder
    private var failure: some View {
        if let text = model.errorText {
            Section {
                Label(text, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Строка без `NavigationLink`: как и в своих типах, ссылка внутри строки
    /// ломает удаление этой же строки.
    private func row(_ user: UserInfo) -> some View {
        Button {
            editing = user
            isEditing = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.title)
                    if user.isAdmin {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Администратор")
                    }
                }
                if !user.isActive {
                    Text("Отключён")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if !user.email.isEmpty {
                    Text(user.email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

/// Карточка человека: имя, почта, смена пароля и отключение. Создание идёт
/// через тот же экран, только с пустым человеком.
struct UserFormView: View {
    let model: UsersModel
    /// Человек, которого правят. `nil` — создаётся новый.
    let user: UserInfo?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserDraft
    @State private var newPassword = ""
    @State private var isWorking = false
    @State private var pendingDisable = false

    init(model: UsersModel, user: UserInfo?) {
        self.model = model
        self.user = user
        var draft = UserDraft()
        draft.username = user?.username ?? ""
        draft.fullName = user?.fullName ?? ""
        draft.email = user?.email ?? ""
        _draft = State(initialValue: draft)
    }

    var body: some View {
        Form {
            identity
            password
            disabling
        }
        // Заголовок короткий: рядом с «Отмена» и «Сохранить» длинный
        // обрезается прямо в букве.
        .navigationTitle(user == nil ? "Новый" : "Пользователь")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if user == nil {
                    Button("Отмена") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    Task {
                        isWorking = true
                        let saved = user == nil
                            ? await model.create(draft)
                            : await model.update(user!, draft: draft)
                        if saved {
                            dismiss()
                        }
                        isWorking = false
                    }
                }
                .disabled(problem != nil || isWorking)
            }
        }
        .confirmationDialog(
            "Отключить «\(user?.username ?? "")»?",
            isPresented: $pendingDisable,
            titleVisibility: .visible
        ) {
            Button("Отключить", role: .destructive) {
                Task {
                    isWorking = true
                    await model.disable(user)
                    isWorking = false
                    dismiss()
                }
            }
            Button("Отмена") { pendingDisable = false }
        } message: {
            Text("Человек перестанет входить, его записи останутся на месте")
        }
    }

    private var problem: String? {
        UserDraft.problem(draft, isNew: user == nil)
    }

    private var identity: some View {
        Section {
            TextField("Логин", text: $draft.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(user != nil)
            TextField("Имя", text: $draft.fullName)
            TextField("Почта", text: $draft.email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
        } header: {
            Text("Кто это")
        } footer: {
            Text(problem ?? "Логин и почту можно поменять, имя и почту видно самому человеку")
        }
    }

    private var password: some View {
        Section {
            if user == nil {
                SecureField("Пароль от 6 символов", text: $draft.password)
            } else {
                SecureField("Новый пароль от 6 символов", text: $newPassword)
                Button("Сменить пароль") {
                    Task {
                        isWorking = true
                        if await model.resetPassword(for: user, to: newPassword) {
                            newPassword = ""
                        }
                        isWorking = false
                    }
                }
                .disabled(newPassword.count < 6 || isWorking)
            }
        } header: {
            Text("Пароль")
        } footer: {
            Text(user == nil ? "Пароль придёт человеку, он сможет его поменять сам" :
                "Смена пароля выводит человека из всех сессий")
        }
    }

    private var disabling: some View {
        Section {
            if let user, !user.isAdmin {
                Button(role: .destructive) {
                    pendingDisable = true
                } label: {
                    Label("Отключить", systemImage: "person.crop.circle.badge.xmark")
                }
                .tint(.red)
            }
        } footer: {
            Text("Отключение мягкое: человек не войдёт, но записи и история останутся")
        }
    }
}
