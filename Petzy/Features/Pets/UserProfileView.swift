import SwiftUI

/// Чужой человек: кто он и какие питомцы у вас общие. Открывается из раздела
/// «Доступ» по логину: там видно, с кем поделён питомец, и рано или поздно
/// хочется понять, кто это.
struct UserProfileView: View {
    let client: APIClient
    let username: String
    let app: AppModel

    @Environment(\.dismiss) private var dismiss

    @State private var profile: UserProfile?
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            if let profile {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.title).font(.title3.weight(.semibold))
                        Text("@\(profile.username)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    let since = MomentText.russianDay(profile.createdAt) ?? profile.createdAt
                    LabeledContent("На Petzy с", value: since)
                }
                Section {
                    if profile.sharedPets.isEmpty {
                        Text("Общих питомцев нет").foregroundStyle(.secondary)
                    } else {
                        ForEach(profile.sharedPets) { pet in
                            Button {
                                // Питомец открывается в приложении: выбираем его
                                // и закрываем страницу. Отдельная копия медкарты
                                // здесь была бы вторым способом смотреть одно.
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
                } header: {
                    Text("Общие питомцы")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if profile == nil, errorText == nil {
                ProgressView()
            }
        }
        .task {
            do {
                profile = try await UsersAPI.profile(client, username: username)
            } catch {
                errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
