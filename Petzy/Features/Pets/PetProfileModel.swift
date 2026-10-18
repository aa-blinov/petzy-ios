import Foundation
import Observation

/// Состояние экрана «О питомце». Знает про запросы и что после них показать,
/// но не знает про JSON: разбор лежит в `PetsAPI`, экран рисует то, что здесь.
/// Питомца может не быть вовсе: та же форма заводит нового.
@MainActor
@Observable
final class PetProfileModel {
    private(set) var profile: PetProfile?
    /// То, что человек набирает. Форма правит черновик напрямую, а сервер
    /// видит его только в момент сохранения.
    var draft: PetDraft
    /// Что пропадёт вместе с питомцем. Читается перед вопросом об удалении.
    private(set) var impact: PetDeletionImpact?
    private(set) var isLoading = false
    var errorText: String?
    /// Питомец удалён: список питомцев пора перечитать, а экран закрыть.
    private(set) var isDeleted = false
    /// Питомец добавлен: его надо выбрать и показать в списке.
    private(set) var createdID: String?

    private let client: APIClient
    private let petID: String?

    init(client: APIClient, petID: String?) {
        self.client = client
        self.petID = petID
        draft = PetDraft()
    }

    /// Экран нового питомца: сохранять ещё нечего, ждать нечего.
    var isNew: Bool {
        petID == nil
    }

    /// Питомцем поделились: карточку не правят и не удаляют, сервер и не даст.
    var canEdit: Bool {
        profile?.currentUserIsOwner ?? true
    }

    /// Названия видов для выбора. Порядок как в вебе, человек узнаёт нужный
    /// с первого экрана, а не ищет в списке.
    var speciesKinds: [PetSpecies.Kind] {
        PetSpecies.all
    }

    func load() async {
        guard let petID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await PetsAPI.card(client, id: petID)
            profile = loaded
            draft = PetDraft(
                name: loaded.name,
                species: loaded.species,
                breed: loaded.breed,
                birthDate: loaded.birthDate.flatMap(MomentText.date(from:)),
                gender: loaded.gender,
                neutering: loaded.neutering,
                healthNotes: loaded.healthNotes
            )
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Сохранение. У созданного питомца сервер возвращает карточку сам, у
    /// правки — только «Данные питомца обновлены», и её приходится перечитывать.
    @discardableResult
    func save(photo: UploadFile?, removePhoto: Bool) async -> Bool {
        if let problem = PetDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            if let petID {
                try await PetsAPI.update(
                    client,
                    id: petID,
                    draft: draft,
                    photo: photo,
                    removePhoto: removePhoto
                )
                await load()
            } else {
                profile = try await PetsAPI.create(client, draft: draft, photo: photo)
                createdID = profile?.id
            }
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Что пропадёт вместе с питомцем. Читается до вопроса: человек должен
    /// увидеть цифры, а не «точно удалить?».
    func prepareDeletion() async {
        guard let petID else { return }
        do {
            impact = try await PetsAPI.deletionImpact(client, id: petID)
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Удаление. Отмены на сервере нет, поэтому вопрос задаётся заранее и с
    /// цифрами, а не после нажатия.
    func delete() async {
        guard let petID else { return }
        errorText = nil
        do {
            try await PetsAPI.delete(client, id: petID)
            isDeleted = true
        } catch {
            errorText = Self.text(of: error)
        }
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
