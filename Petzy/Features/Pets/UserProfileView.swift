import SwiftUI

/// Чужой человек: кто он и какие питомцы у вас общие. Открывается из раздела
/// «Доступ» по логину: там видно, с кем поделён питомец, и рано или поздно
/// хочется понять, кто это.
struct UserProfileView: View {
    let app: AppModel
    let username: String

    @Environment(\.dismiss) private var dismiss
    @State private var model: UserProfileModel

    init(app: AppModel, username: String) {
        self.app = app
        self.username = username
        _model = State(initialValue: UserProfileModel(client: app.client, username: username))
    }

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            if let profile = model.profile {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.title).font(.title3.weight(.semibold))
                        Text("@\(profile.username)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    LabeledContent("На Petzy с", value: profile.sinceText)
                }
                Section {
                    pets(profile.sharedPets)
                } header: {
                    Text("Общие питомцы")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.isLoading {
                ProgressView()
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private func pets(_ pets: [UserProfile.SharedPet]) -> some View {
        if pets.isEmpty {
            Text("Общих питомцев нет").foregroundStyle(.secondary)
        } else {
            ForEach(pets) { pet in
                Button {
                    // Питомец открывается в приложении: выбираем его и
                    // закрываем страницу. Отдельная копия медкарты здесь была бы
                    // вторым способом смотреть одно и то же.
                    app.select(petID: pet.id)
                    dismiss()
                } label: {
                    HStack {
                        Label(pet.name, systemImage: "pawprint")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
