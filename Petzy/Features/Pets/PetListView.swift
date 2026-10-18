import SwiftUI

struct PetListView: View {
    let client: APIClient
    let onSignOut: () -> Void

    @State private var state: ListState = .loading

    private enum ListState {
        case loading
        case loaded([Pet])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Мои питомцы")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Выйти", action: onSignOut)
                    }
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
        case let .failed(text):
            ContentUnavailableView {
                Label("Список не загрузился", systemImage: "exclamationmark.triangle")
            } description: {
                Text(text)
            } actions: {
                Button("Повторить") { Task { await load() } }
            }
        case let .loaded(pets):
            if pets.isEmpty {
                ContentUnavailableView("Пока нет питомцев", systemImage: "pawprint")
            } else {
                List(pets) { pet in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pet.name).font(.headline)
                        Text(subtitle(for: pet))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            let response = try await client.get("/api/pets", as: PetsResponse.self)
            state = .loaded(response.pets)
        } catch {
            let apiError = error as? APIError
            if apiError?.isAuthProblem == true {
                onSignOut()
                return
            }
            state = .failed(apiError?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Части строки через запятую: точка-разделитель «·» в интерфейсе не используем,
    /// как в веб-приложении (AGENTS.md репозитория petzy).
    private func subtitle(for pet: Pet) -> String {
        var parts: [String] = []
        if let species = PetSpecies.label(for: pet.species) {
            parts.append(species)
        }
        if let breed = pet.breed, !breed.isEmpty {
            parts.append(breed)
        }
        if let birthDate = pet.birthDate, !birthDate.isEmpty {
            parts.append(Self.formatDay(birthDate))
        }
        return parts.isEmpty ? "Без описания" : parts.joined(separator: ", ")
    }

    /// Бэкенд отдаёт дату как `2021-08-01`, показываем `01.08.2021`.
    /// Форматируем строками, а не DateFormatter: локаль приложения тут не должен
    /// влиять на вид даты.
    private static func formatDay(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
}
