import Foundation
@testable import Petzy
import Testing

/// Локальная копия: то, чем приложение пользуется без сети. Хранилище должно
/// переживать круг сохранения и чтения и не ломать запуск на битом файле:
/// человек без сети должен увидеть пустую ленту, а не краш.
@Suite("Офлайн: локальная копия")
struct LocalStoreTests {
    @Test("Снимок переживает сохранение и чтение")
    func snapshotRoundTrips() {
        let store = LocalStore(url: Self.tempURL())
        store.save(Self.sample)

        let loaded = LocalStore(url: store.url).load()

        #expect(loaded.syncAt == "2026-10-19T08:12:40Z")
        #expect(loaded.pets.map(\.id) == ["p1"])
        #expect(loaded.pets.first?.name == "Рекс")
        #expect(loaded.eventTypes["weight"]?.label == "Вес")
        #expect(loaded.feed["p1"]?.first?.event?.id == "e1")
        #expect(loaded.feed["p1"]?.first?.event?.comment == "Поел")
    }

    /// Копия ленты держит и приём, и запись: приём — такой же факт дневника, и
    /// без сети он должен оставаться на месте.
    @Test("Приём переживает запись и чтение копии")
    func intakeSurvivesRoundTrip() {
        let url = Self.tempURL()
        var snapshot = Self.sample
        snapshot.feed["p1"] = [.intake(MedicationIntake(
            id: "a1",
            medicationID: "m1",
            medicationName: "Мелоксидил",
            day: "2026-10-19",
            time: "19:21",
            dose: 2.5,
            unit: "мл",
            skipped: false
        ))]
        LocalStore(url: url).save(snapshot)

        let loaded = LocalStore(url: url).load()

        let dose = loaded.feed["p1"]?.first?.intake
        #expect(dose?.medicationName == "Мелоксидил")
        #expect(dose?.doseText == "2,5 мл")
        #expect(dose?.day == "2026-10-19")
        #expect(dose?.time == "19:21")
    }

    @Test("Без файла копия пустая, а не ошибка")
    func missingFileGivesEmptySnapshot() {
        let loaded = LocalStore(url: Self.tempURL()).load()

        #expect(loaded.pets.isEmpty)
        #expect(loaded.feed.isEmpty)
        #expect(loaded.syncAt == nil)
    }

    /// Битый файл копии это не повод не запускаться: приложение открылось, показало
    /// пустую ленту и попросило сеть. Оно не должно падать на мусоре в своём же
    /// файле.
    @Test("Битый файл даёт пустую копию, а не падение")
    func corruptFileGivesEmptySnapshot() throws {
        let url = Self.tempURL()
        try Data("{ это не json".utf8).write(to: url)

        let loaded = LocalStore(url: url).load()

        #expect(loaded.pets.isEmpty)
        #expect(loaded.feed.isEmpty)
    }

    /// Повторное сохранение заменяет копию, а не дописывает её: без этого с
    /// каждым запуском файл рос бы вдвое.
    @Test("Повторное сохранение заменяет копию")
    func saveReplacesPrevious() {
        let url = Self.tempURL()
        var first = Self.sample
        first.feed = ["p1": []]
        LocalStore(url: url).save(first)

        var second = Self.sample
        second.feed = [:]
        LocalStore(url: url).save(second)

        let loaded = LocalStore(url: url).load()
        #expect(loaded.feed.isEmpty)
        #expect(loaded.pets.count == 1)
    }

    /// Очередь офлайн-записей переживает перезапуск: иначе человек набрал
    /// запись в метро, а наверху её нет.
    @Test("Очередь офлайн-записей переживает перезапуск")
    func queueSurvivesRelaunch() {
        let url = Self.tempURL()
        var snapshot = Self.sample
        snapshot.queue = [PendingWrite(
            localID: "abc-123",
            petID: "p1",
            kind: .event,
            title: "Вес",
            method: "POST",
            path: "/api/events",
            payload: Self.payload()
        )]
        LocalStore(url: url).save(snapshot)

        let loaded = LocalStore(url: url).load()

        #expect(loaded.queue.count == 1)
        #expect(loaded.queue.first?.localID == "abc-123")
        #expect(loaded.queue.first?.title == "Вес")
        #expect(loaded.queue.first?.path == "/api/events")
        let body = try? JSONDecoder().decode(PendingBody.self, from: loaded.queue.first?.payload ?? Data())
        #expect(body?.comment == "В метро", "тело запроса должно пережить перезапуск как есть")
    }

    /// Тело запроса, каким его кладёт в очередь.
    static func payload() -> Data {
        let body = PendingBody(
            date: "2026-10-19",
            time: "08:00",
            zone: "Asia/Almaty",
            type: "weight",
            comment: "В метро",
            fields: ["weight": .number(29.3)]
        )
        return (try? JSONEncoder().encode(body)) ?? Data()
    }

    // MARK: - Образцы

    static var sample: OfflineSnapshot {
        var snapshot = OfflineSnapshot()
        snapshot.syncAt = "2026-10-19T08:12:40Z"
        snapshot.pets = [Pet(
            id: "p1",
            name: "Рекс",
            species: "dog",
            breed: nil,
            birthDate: nil,
            gender: nil,
            photoURL: nil,
            updatedAt: nil
        )]
        snapshot.eventTypes = ["weight": EventTypeInfo(
            key: "weight",
            label: "Вес",
            icon: "scalemass",
            category: "health",
            fields: [],
            chart: nil
        )]
        snapshot.feed = ["p1": [.event(PetEvent(
            id: "e1",
            type: "weight",
            dateTime: "2026-10-19T08:00:00+05:00",
            comment: "Поел",
            fields: ["weight": .number(29.3)],
            isDeleted: false
        ))]]
        return snapshot
    }

    static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("petzy-offline-\(UUID().uuidString).json")
    }
}
