import Foundation

/// Снимок того, что приложение уже видела: копия для работы без сети. Лежит
/// одним файлом, потому что разделов много, а писать их по одному — значит
/// половину забыть сохранить.
struct OfflineSnapshot: Codable, Sendable {
    /// Момент последней полной синхронизации, в UTC до секунды: с него
    /// приложение спрашивает `GET /api/sync`.
    var syncAt: String?
    var pets: [Pet] = []
    var eventTypes: [String: EventTypeInfo] = [:]
    /// Записи по питомцам. Ключ — `pet_id`.
    var events: [String: [PetEvent]] = [:]
    /// Записи, которые человек сделал без сети и которые ещё не ушли.
    var queue: [PendingWrite] = []

    init() {}
}

/// Запись, сделанная без сети. Лежит в очереди, пока не отправлена.
struct PendingWrite: Codable, Sendable, Identifiable {
    var id: String {
        localID
    }

    /// Имя, которым устройство назвало запись. По нему же её можно править и
    /// удалить, пока сервер не дал своей `id`.
    let localID: String
    let petID: String
    var body: PendingBody
}

/// Тело офлайн-записи: ровно то, что уходит в `POST /api/events`, плюс пояс,
/// без которого сервер записал бы время по своим часам.
struct PendingBody: Codable, Sendable {
    let date: String
    let time: String
    /// Ключ на стороне сервера короткий, `tz`. Имя в Swift длинное, потому что
    /// трёхбуквенное ловит линтер, а «zone» ещё и читается рядом с датой.
    let zone: String
    let type: String
    var comment: String
    var fields: [String: FieldValue]

    enum CodingKeys: String, CodingKey {
        case date, time, type, comment, fields
        case zone = "tz"
    }
}

/// Локальная копия на диске. Пишется целиком и атомарно: оборванная запись
/// файла означала бы, что у человека пропал дневник.
final class LocalStore: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "ru.petzy.offline.store")

    init(url: URL = LocalStore.defaultURL) {
        self.url = url
    }

    /// Копия лежит в Application Support: это данные приложения, а не его
    /// мусор, и систему их не жалко вычищать при нехватке места.
    static var defaultURL: URL {
        let folder = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("offline.json")
    }

    /// Читает копию. Битый файл это пустая копия, а не падение: человек без
    /// сети должен увидеть пустую ленту и попросить сеть, а не краш.
    func load() -> OfflineSnapshot {
        queue.sync {
            guard let data = try? Data(contentsOf: url) else { return OfflineSnapshot() }
            return (try? JSONDecoder().decode(OfflineSnapshot.self, from: data)) ?? OfflineSnapshot()
        }
    }

    func save(_ snapshot: OfflineSnapshot) {
        queue.sync {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
