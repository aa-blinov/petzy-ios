import Foundation
@testable import Petzy
import Testing

/// Фото питомца качается один раз за сессию: без памяти каждый показ карточки
/// дёргал сеть заново и мигал значком вида на месте фото.
@Suite("Загрузчик фото питомцев")
struct PetPhotoLoaderTests {
    private func loader() -> (PetPhotoLoader, URL) {
        StubURLProtocol.reset()
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://petzy.example/pets/1/photo?v=1")!
        return (PetPhotoLoader(session: StubURLProtocol.makeSession()), url)
    }

    @Test("Повторный запрос не ходит в сеть")
    func secondReadComesFromMemory() async {
        let (loader, url) = loader()
        StubURLProtocol.stub(status: 200, data: Data([0xFF, 0xD8, 0xFF]), headers: [:])

        let first = await loader.imageData(for: url)
        let second = await loader.imageData(for: url)

        #expect(first == Data([0xFF, 0xD8, 0xFF]))
        #expect(second == first)
        #expect(StubURLProtocol.requests.count == 1, "второй показ докачал файл заново")
    }

    @Test("Параллельные читатели делят один запрос")
    func concurrentReadsShareOneRequest() async {
        let (loader, url) = loader()
        StubURLProtocol.stub(status: 200, data: Data([0xFF, 0xD8, 0xFF]), headers: [:])

        async let first = loader.imageData(for: url)
        async let second = loader.imageData(for: url)
        let (one, two) = await (first, second)

        #expect(one == Data([0xFF, 0xD8, 0xFF]))
        #expect(two == one)
        #expect(StubURLProtocol.requests.count == 1, "параллельные показы скачали дважды")
    }

    @Test("Ошибка не запоминается")
    func failureIsNotCached() async {
        let (loader, url) = loader()
        StubURLProtocol.stubOffline()

        #expect(await loader.imageData(for: url) == nil)

        StubURLProtocol.stub(status: 200, data: Data([0xFF, 0xD8, 0xFF]), headers: [:])
        #expect(await loader.imageData(for: url) == Data([0xFF, 0xD8, 0xFF]))
    }
}
