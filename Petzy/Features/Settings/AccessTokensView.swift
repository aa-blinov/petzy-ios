import SwiftUI

/// Доступы для ассистентов: персональные токены вместо пароля. Секрет
/// сервер отдаёт один раз, поэтому он висит на экране, пока его не забрали.
struct AccessTokensView: View {
    /// Форма правится прямо на экране, а `@State` пережил бы только её саму:
    /// вкладка пересоздаётся при смене состояния модели.
    @Bindable var model: AccessTokensModel

    @State private var pendingRevoke: AccessToken?

    var body: some View {
        List {
            failure
            created
            newAccess
            existing
        }
        .navigationTitle("Доступы для ассистентов")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .confirmationDialog(
            "Отозвать доступ?",
            isPresented: Binding(get: { pendingRevoke != nil }, set: {
                if !$0 {
                    pendingRevoke = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Отозвать", role: .destructive) {
                if let token = pendingRevoke {
                    Task { await model.revoke(id: token.id) }
                }
                pendingRevoke = nil
            }
            Button("Отмена") { pendingRevoke = nil }
        } message: {
            Text("Тот, кому он выдан, работать перестанет сразу")
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

    /// Секрет нового доступа. Он больше нигде не хранится: сервер знает только
    /// хэш, поэтому второй раз показать его нечем.
    @ViewBuilder
    private var created: some View {
        if let secret = model.secret {
            Section {
                ShareLink(item: secret) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                Text(secret)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Готово", action: model.forgetSecret)
            } header: {
                Text("Доступ создан")
            } footer: {
                Text("Сохраните секрет сейчас, второй раз его показать не получится")
            }
        }
    }

    private var newAccess: some View {
        Section {
            TextField("Например, домофон", text: $model.draft.name)
            Picker("Срок", selection: $model.draft.days) {
                ForEach(AccessTerm.all, id: \.days) { Text($0.title).tag($0.days) }
            }
            ForEach(AccessScope.allCases, id: \.self) { scope in
                Button {
                    toggle(scope)
                } label: {
                    HStack {
                        Text(scope.title)
                        Spacer()
                        if model.draft.scopes.contains(scope) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            if let problem = AccessTokenDraft.problem(model.draft) {
                Text(problem).foregroundStyle(.red)
            }
            Button("Создать") {
                Task { await model.create() }
            }
            .disabled(AccessTokenDraft.problem(model.draft) != nil)
        } header: {
            Text("Новый доступ")
        } footer: {
            Text("Вместо пароля: доступ видит только то, что вы отметили")
        }
    }

    private var existing: some View {
        Section {
            if model.tokens.isEmpty {
                Text("Доступов пока нет").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(model.tokens) { token in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(token.name)
                            Spacer()
                            if token.isRevoked {
                                Text("Отозван")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if token.isExpired {
                                Text("Срок истёк")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Отозвать") { pendingRevoke = token }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                    .tint(.red)
                            }
                        }
                        Text(token.scopes.map(AccessScope.title(of:)).joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let expires = token.expiresText {
                            Text(expires)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Выданные доступы")
        }
    }

    private func toggle(_ scope: AccessScope) {
        if model.draft.scopes.contains(scope) {
            model.draft.scopes.remove(scope)
        } else {
            model.draft.scopes.insert(scope)
        }
    }
}

/// На сколько дней живёт доступ. Сервер принимает любое число от 1 до 365,
/// но человеку нужны привычные сроки, а не поле с числом.
struct AccessTerm: Identifiable {
    let days: Int
    let title: String

    var id: Int {
        days
    }

    static let all = [
        AccessTerm(days: 7, title: "Неделя"),
        AccessTerm(days: 30, title: "Месяц"),
        AccessTerm(days: 90, title: "3 месяца"),
        AccessTerm(days: 365, title: "Год")
    ]
}
