import Foundation
@testable import Petzy
import Testing

/// Оболочка приложения: список питомцев и выбор того, чей дневник открыт.
/// Выбор должен переживать перезапуск, а если питомца удалили на другом
/// устройстве, приложение обязано открыться на первом, а не на пустом экране.
@MainActor
@Suite("Выбранный питомец")
struct AppModelTests {
    private func loaded(_ state: PetsState) -> Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    private func stubPets(_ pets: [[String: Any]]) {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["pets": pets])
    }

    @Test("Выбор питомца переживает перезапуск")
    func selectionSurvivesRestart() async {
        StubURLProtocol.reset()
        let defaults = TestSupport.makeDefaults()
        let before = await TestSupport.makeModel(defaults: defaults)

        await before.select(petID: "pet-2")

        // Те же настройки, новый экземпляр модели. Это и есть перезапуск.
        let afterRestart = await TestSupport.makeModel(defaults: defaults)
        #expect(afterRestart.selectedPetID == "pet-2")
    }

    @Test("Без сохранённого выбора открывается первый питомец")
    func firstPetIsSelectedByDefault() async {
        stubPets([
            ["_id": "pet-1", "name": "Барсик", "species": "cat"],
            ["_id": "pet-2", "name": "Шарик", "species": "dog"]
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())

        await model.loadPets()

        #expect(model.pets.map(\.id) == ["pet-1", "pet-2"])
        #expect(model.selectedPetID == "pet-1")
        #expect(loaded(model.petsState))
        #expect(StubURLProtocol.requestedPaths == ["/api/pets"])
    }

    @Test("Выбранного питомца удалили на другом устройстве, открывается первый")
    func fallsBackWhenSelectedPetIsGone() async {
        stubPets([["_id": "pet-1", "name": "Барсик", "species": "cat"]])
        let defaults = TestSupport.makeDefaults()
        let before = await TestSupport.makeModel(defaults: defaults)
        await before.select(petID: "pet-gone")

        let afterRestart = await TestSupport.makeModel(defaults: defaults)
        await afterRestart.loadPets()

        #expect(afterRestart.selectedPetID == "pet-1")
    }

    @Test("Питомцев нет, выбирать нечего")
    func noPetsMeansNoSelection() async {
        stubPets([])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())

        await model.loadPets()

        #expect(model.selectedPetID == nil)
        #expect(model.pets.isEmpty)
        #expect(loaded(model.petsState))
    }

    /// Сессия умерла, пока список грузился. Молча показывать ошибку нельзя:
    /// пользователь будет думать, что сломался бэкенд, и ломиться в поддержку.
    @Test("Сессия закончилась, приложение возвращает экран входа")
    func deadSessionGoesBackToLogin() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 401, json: ["error": "Сессия закончилась"])
        StubURLProtocol.stub(status: 401, json: ["error": "refresh-токен недействителен"])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())

        await model.loadPets()

        #expect(StubURLProtocol.requestedPaths == ["/api/pets", "/api/auth/refresh"])
        #expect(model.state == .signedOut)
    }

    private func stubEvent(_ id: String, dateTime: String) -> [String: Any] {
        ["_id": id, "type": "weight", "date_time": dateTime, "comment": "", "fields": ["weight": 29.3]]
    }

    /// Лента читается курсором, а не по номеру страницы: запись, написанная
    /// пока шли по страницам, не должна сдвинуть выборку и потеряться.
    @Test("Лента дочитывается курсором до последней страницы")
    func feedFollowsCursorToTheEnd() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["event_types": [
            ["key": "weight", "label": "Вес", "icon": "scalemass", "fields": [[
                "name": "weight", "label": "Вес (кг)", "type": "number",
                "required": true, "min": 0.0, "max": 100.0, "options": nil
            ]]]
        ]])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": "cur-1"
        ])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e2", dateTime: "2026-10-17 09:00")],
            "next_cursor": nil
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.loadFeed()

        #expect(
            StubURLProtocol.requestedPaths == ["/api/event-types", "/api/events"],
            "лента пошла не туда: \(StubURLProtocol.requestedPaths)"
        )
        #expect(model.feedErrorText == nil, "ошибка загрузки: \(model.feedErrorText ?? "нет")")
        #expect(model.days.map(\.date) == ["2026-10-18"])
        #expect(model.hasMoreEvents)
        #expect(model.feedNextCursor == "cur-1")

        await model.loadMore()

        #expect(model.days.map(\.date) == ["2026-10-18", "2026-10-17"])
        #expect(model.days.flatMap(\.events).count == 2)
        #expect(model.hasMoreEvents == false)
        let lastQuery = StubURLProtocol.requests.last?.url?.query ?? ""
        #expect(lastQuery.contains("before=cur-1"), "вторая страница запрошена без курсора: \(lastQuery)")
    }

    /// Догружать больше нечего: повторный вызов не должен слать запрос в сервер.
    @Test("Последняя страница больше не читается")
    func lastPageIsNotRequestedAgain() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "event_types": [["key": "weight", "label": "Вес", "fields": []]]
        ])
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": nil
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")
        await model.loadFeed()
        let before = StubURLProtocol.requests.count

        await model.loadMore()

        #expect(StubURLProtocol.requests.count == before)
    }

    /// Ленту перечитывают по разным поводам: запись сохранили, очередь ушла,
    /// питомца переключили. Человек при этом остался на той же странице, и
    /// читать дальше неё незачем. Глубина восстанавливается, а не
    /// удваивается с каждым перечитыванием: иначе после нескольких сохранений
    /// приложение читало бы вдвое, вчетверо страниц — и упёрлось бы в лимит
    /// запросов, не спросив человека.
    @Test("Перечитывание ленты не читает больше страниц, чем человек дочитал")
    func reloadingFeedDoesNotReadMorePages() async {
        StubURLProtocol.reset()
        let types: [String: Any] = ["event_types": [["key": "weight", "label": "Вес", "fields": []]]]
        // Каждая страница отдаёт курсор: страниц может быть сколько угодно, и
        // перечитывание не должно решать за приложение, где лента кончилась.
        let page: [String: Any] = [
            "items": [stubEvent("e1", dateTime: "2026-10-18 09:00")],
            "next_cursor": "cur-1"
        ]
        // Заготовки идут в том же порядке, в каком уходят запросы: справочник
        // типов, первая страница и страница, до которой человек дочитал.
        for _ in 0 ..< 3 {
            StubURLProtocol.stub(status: 200, json: types)
            StubURLProtocol.stub(status: 200, json: page)
            StubURLProtocol.stub(status: 200, json: page)
        }
        // Лишняя страница в самом конце: на неё уйдёт заготовка, только если
        // глубина выросла сама.
        StubURLProtocol.stub(status: 200, json: page)
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.loadFeed()
        // Человек дочитал вторую страницу и остался на ней.
        await model.loadMore()
        // Два перечитывания: запись сохранили, потом ушла очередь.
        await model.loadFeed()
        await model.loadFeed()

        let feedRequests = StubURLProtocol.requestedPaths.filter { $0 == "/api/events" }
        let trace = StubURLProtocol.requests.map { "\($0.url?.path ?? "")?\($0.url?.query ?? "")" }
        #expect(
            feedRequests.count == 6,
            "лента прочитана \(feedRequests.count) раз вместо 6: \(trace)"
        )
    }

    /// Смена аккаунта, у которого питомцев нет, оставляла на экране чужую
    /// ошибку «Питомец не найден», а «Повторить» ничего не менял: ленты у
    /// нового аккаунта нет, и показывать надо пустоту, а не чужую ошибку.
    @Test("Без питомца лента пуста, а не с чужой ошибкой")
    func feedWithoutPetHasNoError() async {
        stubPets([])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.feedErrorText = "Питомец не найден"

        await model.loadPets()
        await model.loadFeed()

        #expect(model.feedErrorText == nil)
        #expect(model.rawEvents.isEmpty)
    }

    /// Фильтр истории принадлежит питомцу: оставленный от прежнего, он
    /// показывал новому питомцу пустую историю, и человек думал, что записей
    private func weightDraft() -> EventDraft {
        EventDraft(
            type: EventTypeInfo(key: "weight", label: "Вес", icon: "scale", category: "health", fields: [
                EventFieldInfo(
                    name: "weight", label: "Вес (кг)", type: "number",
                    required: true, min: 0, max: 100, options: nil
                )
            ], chart: nil),
            values: ["weight": "29,3"],
            comment: "после прогулки",
            date: "2026-10-18",
            time: "12:00"
        )
    }

    /// Запрос проверяется целиком: путь, тип и питомец в теле. Если хоть одное из
    /// этого разъедется, запись уйдёт не туда или потеряет значения.
    @Test("Новая запись уходит с типом, питомцем и значениями")
    func createEventSendsEverything() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["message": "Запись сохранена", "id": "e-new"])
        // После сохранения лента перечитывается целиком, ей нужны свои ответы.
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: ["items": [], "next_cursor": nil])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.createEvent(weightDraft())

        let request = StubURLProtocol.requests.first { $0.httpMethod == "POST" }
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/api/events")
        let body = TestSupport.body(of: request)
        #expect(body["type"] as? String == "weight")
        #expect(body["pet_id"] as? String == "pet-1")
        #expect(body["date"] as? String == "2026-10-18")
        #expect(body["time"] as? String == "12:00")
        #expect(body["comment"] as? String == "после прогулки")
        #expect((body["fields"] as? [String: Any])?["weight"] as? Double == 29.3)
        #expect(body["tz"] != nil, "часовой пояс телефона обязателен")
    }

    @Test("Правка уходит без типа и питомца, адрес содержит id записи")
    func updateEventSendsOnlyChanges() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["message": "Запись обновлена"])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())

        await model.updateEvent(id: "e-1", draft: weightDraft())

        let request = StubURLProtocol.requests.first { $0.httpMethod == "PUT" }
        #expect(request?.httpMethod == "PUT")
        #expect(request?.url?.path == "/api/events/e-1")
        let body = TestSupport.body(of: request)
        #expect(body["type"] == nil)
        #expect(body["pet_id"] == nil)
        #expect((body["fields"] as? [String: Any])?["weight"] as? Double == 29.3)
    }

    /// Удаление на сервере жёсткое и необратимое. Проверяем и запрос, и то,
    /// что запись действительно исчезла из ленты на экране.
    @Test("Удаление уходит отдельным запросом и убирает запись из ленты")
    func deleteEventRemovesItFromFeed() async {
        StubURLProtocol.reset()
        TestSupport.stubTypeReference()
        StubURLProtocol.stub(status: 200, json: [
            "items": [stubEvent("e-1", dateTime: "2026-10-18 09:00")],
            "next_cursor": nil
        ])
        StubURLProtocol.stub(status: 200, json: ["message": "Запись удалена"])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")
        await model.loadFeed()
        #expect(model.rawEvents.count == 1)

        await model.deleteEvent(id: "e-1")

        let request = StubURLProtocol.requests.first { $0.httpMethod == "DELETE" }
        #expect(request?.url?.path == "/api/events/e-1")
        #expect(model.rawEvents.isEmpty)
    }

    /// Ответ сервера с чужой ошибкой должен дойти до человека, а не молчать.
    @Test("Ошибка сохранения показывается")
    func saveErrorIsShown() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 422, json: [
            "code": "validation_error", "error": "Вес должен быть от 0 до 100"
        ])
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "pet-1")

        await model.createEvent(weightDraft())

        #expect(model.feedErrorText == "Вес должен быть от 0 до 100")
    }
}
