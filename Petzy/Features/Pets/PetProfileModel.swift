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
    /// Чтение упало: карточка не пришла, и форма осталась пустой. Сохранять
    /// её нельзя, сервер заменяет карточку целиком.
    private(set) var loadFailed = false
    var errorText: String?
    /// Питомец записан в телефон и ждёт связи. Пока это так, форма закрывается
    /// по кнопке «Понятно», а не сама.
    var notice: String?
    /// Питомец уже в очереди: второй раз сохранять нельзя, иначе завелся бы
    /// второй такой же.
    private(set) var isQueued = false
    /// Питомец удалён: список питомцев пора перечитать, а экран закрыть.
    private(set) var isDeleted = false
    /// Питомец добавлен: его надо выбрать и показать в списке.
    private(set) var createdID: String?

    private let client: APIClient
    private let petID: String?
    private let offline: OfflineState

    init(client: APIClient, petID: String?, offline: OfflineState) {
        self.client = client
        self.petID = petID
        self.offline = offline
        draft = PetDraft()
    }

    /// Экран нового питомца: сохранять ещё нечего, ждать нечего.
    var isNew: Bool {
        petID == nil
    }

    /// Питомцем поделились: карточку не правят и не удаляют, сервер и не даст.
    var canEdit: Bool {
        guard loadFailed else { return true }
        return isNew
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
            loadFailed = false
        } catch {
            loadFailed = true
            errorText = Self.text(of: error)
        }
    }

    /// Сохранение. У созданного питомца сервер возвращает карточку сам, у
    /// правки — только «Данные питомца обновлены», и её приходится перечитывать.
    @discardableResult
    func save(photo: UploadFile?, removePhoto: Bool) async -> Bool {
        guard canEdit else {
            errorText = "Карточка не загрузилась, сохранять нечего"
            return false
        }
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
                    removePhoto: removePhoto,
                    baseVersion: profile?.updatedAt
                )
                await load()
            } else {
                profile = try await PetsAPI.create(client, draft: draft, photo: photo)
                createdID = profile?.id
            }
            return true
        } catch {
            // Без связи питомец не теряется: он ждёт в очереди и уйдёт на
            // сервер сам, когда связь вернётся.
            if (error as? APIError)?.isTransport == true {
                queue(photo: photo, removePhoto: removePhoto)
                return true
            }
            // Питомца поменяли, пока человек его правил. Остаётся версия
            // сервера, и её надо показать, а не держать на экране старую.
            if (error as? APIError)?.code == "conflict" {
                await load()
            }
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Ставит питомца в очередь. Создание и правка идут разными запросами, но
    /// очередь одна: путь, метод и тело.
    private func queue(photo: UploadFile?, removePhoto: Bool) {
        guard let petID else {
            let localID = "local-" + UUID().uuidString
            let body = PetsAPI.createBody(draft: draft, photo: photo, localID: localID)
            enqueue(localID: localID, title: draft.name, method: "POST", path: "/api/pets", body: body)
            notice = "Питомец записан в телефон, уйдёт на сервер, когда появится связь"
            return
        }
        // Версия та, что человек видел: сервер откажет, если карточку поменяли
        // с тех пор, и останется версия сервера.
        let body = PetsAPI.updateBody(
            draft: draft,
            photo: photo,
            removePhoto: removePhoto,
            baseVersion: profile?.updatedAt
        )
        enqueue(
            localID: petID,
            title: draft.name,
            method: "PUT",
            path: "/api/pets/" + AppModel.query(petID),
            body: body
        )
        notice = "Правка сохранена в телефон, уйдёт на сервер, когда появится связь"
    }

    private func enqueue(localID: String, title: String, method: String, path: String, body: MultipartBody) {
        guard let contentType = body.contentType else { return }
        offline.enqueue(PendingWrite(
            localID: localID,
            petID: localID,
            kind: .pet,
            title: title,
            method: method,
            path: path,
            payload: body.data,
            contentType: contentType
        ))
        isQueued = true
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
