import SwiftUI

/// Раздел «Доступ»: кто ещё ведёт этого питомца. Владелец приглашает логином и
/// забирает доступ, остальным остаётся выйти. Отдельный файл, потому что экран
/// «О питомце» и без него длинный.
///
/// Вопрос о логине и подтверждение выхода живут здесь, а не на форме: SwiftUI
/// показывает только последний `.alert` одной цепочки, и три алерта на форме
/// оставили бы работающим один.
struct PetAccessSection: View {
    let profile: PetProfile?
    let isNew: Bool
    let model: PetProfileModel
    let app: AppModel

    @State private var inviting = false
    @State private var inviteName = ""
    @State private var askingLeave = false

    var body: some View {
        if let profile, !isNew {
            if profile.currentUserIsOwner {
                owner(profile)
            } else {
                guest
            }
        }
    }

    private func owner(_ profile: PetProfile) -> some View {
        Section {
            ForEach(profile.sharedWith, id: \.self) { username in
                person(username, note: "Ведёт питомца", action: "Забрать") {
                    Task { await model.revoke(username: username) }
                }
            }
            ForEach(profile.shareInvites, id: \.self) { username in
                person(username, note: "Приглашение не принято", action: "Отменить") {
                    Task { await model.revoke(username: username) }
                }
            }
            Button {
                inviteName = ""
                inviting = true
            } label: {
                Label("Пригласить человека", systemImage: "person.badge.plus")
            }
            // Ответ сервера — здесь, а не вверху формы: приглашают снизу, и
            // сообщение сверху человек не увидел бы.
            if let error = model.accessError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Доступ")
        } footer: {
            Text("Приглашённый увидит питомца и сможет вести записи"
                + ", а удалить его или передать другому не сможет")
        }
        .alert("Пригласить человека", isPresented: $inviting) {
            TextField("Логин", text: $inviteName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Пригласить") {
                Task { await model.invite(username: inviteName) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Человек увидит питомца после того, как примет приглашение")
        }
    }

    private var guest: some View {
        Section {
            Button("Выйти из питомца", role: .destructive) { askingLeave = true }
        } footer: {
            Text("Питомец останется у владельца, ваши записи — тоже")
        }
        // Форма у чужого питомца выключена: править его данные нельзя. Выйти
        // из него — можно, и выключенность не должна мешать.
        .disabled(false)
        .alert("Выйти из питомца?", isPresented: $askingLeave) {
            Button("Выйти", role: .destructive) {
                Task { await model.leave() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Питомец останется у владельца, ваши записи — тоже")
        }
    }

    /// Строка человека, с которым поделён питомец: логин, что он значит, и
    /// действие.
    private func person(
        _ username: String,
        note: String,
        action: String,
        run: @escaping () -> Void
    ) -> some View {
        HStack {
            NavigationLink {
                UserProfileView(app: app, username: username)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(username).font(.subheadline)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action, action: run)
                .font(.subheadline)
                .foregroundStyle(.tint)
        }
    }
}
