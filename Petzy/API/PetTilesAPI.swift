import Foundation

/// Правка набора типов там, где нет формы питомца: лист «Что записать» и его
/// «Другие события», как на вебе.
///
/// Отдельного маршрута у сервера нет: набор едет вместе с карточкой, а карточка
/// заменяется целиком. Поэтому сначала читаем её, потом отправляем — иначе
/// сохранение затёрло бы имя, породу и заметки пустыми.
enum PetTilesAPI {
    static func save(_ client: APIClient, petID: String, tiles: TileSettings) async throws {
        let card = try await PetsAPI.card(client, id: petID)
        var draft = PetDraft.from(profile: card)
        draft.tiles = tiles
        try await PetsAPI.update(
            client,
            id: petID,
            draft: draft,
            photo: nil,
            removePhoto: false,
            baseVersion: card.updatedAt
        )
    }
}
