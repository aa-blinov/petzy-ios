import SwiftUI

/// Ссылка для врача. Секрет сервер показывает один раз и больше не хранит,
/// поэтому адрес висит на экране до конца сессии и уходит системным меню.
struct MedicalShareSheet: View {
    let model: MedicalCardModel

    @Environment(\.dismiss) private var dismiss
    @State private var days = 7
    @State private var pendingRevoke: LiveShare?

    var body: some View {
        NavigationStack {
            List {
                failure
                created
                Section {
                    Picker("Сколько дней", selection: $days) {
                        ForEach(MedicalShareDays.all, id: \.self) { Text(MedicalShareDays.title($0)).tag($0) }
                    }
                    Button("Создать ссылку") {
                        Task { await model.createShare(days: days) }
                    }
                } header: {
                    Text("Новая ссылка")
                } footer: {
                    Text("Откроет медкарту без входа, поэтому ссылку лучше отдать врачу, а не выложить")
                }
                live
            }
            .navigationTitle("Ссылка для врача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task { await model.loadShares() }
        }
        .confirmationDialog(
            "Отозвать ссылку?",
            isPresented: Binding(get: { pendingRevoke != nil }, set: {
                if !$0 {
                    pendingRevoke = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Отозвать", role: .destructive) {
                if let share = pendingRevoke {
                    Task { await model.revoke(share) }
                }
                pendingRevoke = nil
            }
            Button("Отмена") { pendingRevoke = nil }
        } message: {
            Text("Ссылка перестанет открывать медкарту сразу")
        }
    }

    /// Ошибка показывается тут, а не на экране медкарты: лист с ссылкой
    /// открыт поверх, и уведомление снизу закрыло бы его вместе с адресом,
    /// который сервер показывает один раз.
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

    @ViewBuilder
    private var created: some View {
        if let share = model.share, let url = share.url {
            Section {
                ShareLink(item: url) {
                    Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                }
                if let expires = share.expiresAt {
                    Text(MomentText.russianDay(MomentText.day(of: expires)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Ссылка готова")
            } footer: {
                // Адрес показывается один раз: сервер хранит только хэш и
                // восстановить его не может.
                Text("Сохраните ссылку сейчас, второй раз её показать не получится")
            }
        }
    }

    private var live: some View {
        Section {
            if model.shares.isEmpty {
                Text("Действующих ссылок нет").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(model.shares) { share in
                    HStack {
                        Text(share.expiresText ?? "Без срока")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Отозвать") { pendingRevoke = share }
                            .buttonStyle(.borderless)
                            .tint(.red)
                    }
                }
            }
        } header: {
            Text("Действующие ссылки")
        } footer: {
            Text("Сама ссылка не показывается: сервер хранит только её хэш")
        }
    }
}
