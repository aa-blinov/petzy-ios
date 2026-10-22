import Foundation

/// Фото питомцев с памятью на сессию. Карточка питомца показывается в ленте,
/// в медкарте и в его форме, и без памяти каждый показ качал файл заново, а на
/// его месте мигало пустое. Системный кеш тут не спасает полностью: он хранит
/// ответ, но вид всё равно проходит через пустое состояние и развертку.
///
/// Память только на сессию: подпись ссылки живёт недолго, и вчерашний байт
/// показывать нельзя. Поэтому NSCache, а не диск.
actor PetPhotoLoader {
    static let shared = PetPhotoLoader()

    private let session: URLSession
    private let cache = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Байты фото или `nil`, если скачать не вышло. Ошибка не запоминается:
    /// сеть могла пропасть на секунду, и следующий показ пробует снова.
    /// Параллельные читатели делят один запрос, а не устраивают гонку.
    func imageData(for url: URL) async -> Data? {
        if let hit = cache.object(forKey: url as NSURL) {
            return hit as Data
        }
        if let running = inFlight[url] {
            return await running.value
        }
        let task = Task { [session] () -> Data? in
            // Пустой ответ и чужой статус — не фото: кешировать страницу
            // ошибки значило бы показывать её вместо питомца до конца сессии.
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  !data.isEmpty
            else { return nil }
            return data
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if let data {
            cache.setObject(data as NSData, forKey: url as NSURL)
        }
        return data
    }
}
