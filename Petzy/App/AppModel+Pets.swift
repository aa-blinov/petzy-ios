import Foundation

extension AppModel {
    func loadPets() async {
        petsState = .loading
        do {
            let response = try await client.get("/api/pets", as: PetsResponse.self)
            petsState = .loaded(response.pets)
            offline.cache(
                events: rawEvents,
                types: eventTypes,
                pets: response.pets,
                petID: selectedPetID ?? "",
                owner: currentUser
            )

            // Питомца могли удалить или переименовать на другом устройстве, пока
            // телефон лежал в кармане. Молча открываем первого: иначе оболочка
            // осталась бы с выбором, которого в списке нет.
            if !response.pets.contains(where: { $0.id == selectedPetID }) {
                select(petID: response.pets.first?.id)
            }
        } catch {
            let apiError = error as? APIError
            if apiError?.isAuthProblem == true {
                endSession()
                return
            }
            // Без связи питомцы берутся из копии: иначе приложение не знает,
            // чей дневник открыт, и переключатель с именем исчезают, хотя
            // лента и разделы из копии показываются. Копия при этом своя:
            // чужой дневник на общем устройстве показывать нельзя.
            if apiError?.isTransport == true, canUseDiary, !offline.snapshot.pets.isEmpty {
                petsState = .loaded(offline.snapshot.pets)
                return
            }
            petsState = .failed(apiError?.errorDescription ?? error.localizedDescription)
        }
    }
}
