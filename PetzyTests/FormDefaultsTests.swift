import Foundation
@testable import Petzy
import Testing

/// Значения по умолчанию лежат на питомце, а не в справочнике типов: их видят
/// все, кто добавляет этому питомцу записи.
@MainActor
@Suite("Значения по умолчанию: контракт и форма")
struct FormDefaultsTests {
    private func card(defaults: [String: [String: String]]) -> [String: Any] {
        ["pet": [
            "_id": "pet-1", "name": "Рекс", "species": "dog", "breed": "", "gender": "",
            "is_neutered": NSNull(), "birth_date": NSNull(), "health_notes": "",
            "photo_url": NSNull(), "current_user_is_owner": true,
            "form_defaults": defaults
        ]]
    }

    @Test("Значения по умолчанию читаются из карточки питомца")
    func defaultsAreReadFromPetCard() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: card(defaults: [
            "weight": ["weight": "29,3"], "feeding": ["food": "Сухой корм"]
        ]))
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let defaults = try await PetsAPI.formDefaults(client, id: "pet-1")

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/pet-1"])
        #expect(defaults["weight"]?["weight"] == "29,3")
        #expect(defaults["feeding"]?["food"] == "Сухой корм")
    }

    /// Набор заменяется целиком, поэтому тело проверяется целиком: пустое
    /// значение в наборе означало бы «убери», а лишний тип — «удали всё у него».
    @Test("Сохранение уходит набором, ответ читается обратно")
    func saveSendsWholeSet() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["form_defaults": ["weight": ["weight": "29,4"]]])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let saved = try await PetsAPI.saveFormDefaults(client, id: "pet-1", defaults: [
            "weight": ["weight": "29,4"]
        ])

        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "PUT")
        #expect(request?.url?.path == "/api/pets/pet-1/form-defaults")
        #expect(TestSupport.body(of: request)["form_defaults"] as? [String: [String: String]] == [
            "weight": ["weight": "29,4"]
        ])
        #expect(saved["weight"]?["weight"] == "29,4")
    }

    /// Главное, ради чего всё затевалось: новая запись открывается уже
    /// заполненной. Без этого значения были бы просто ещё одной настройкой.
    @Test("Новая запись открывается со значениями по умолчанию")
    func newDraftIsPrefilled() async {
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.formDefaults = [
            "weight": ["weight": "29,3"],
            "feeding": ["food": "Сухой корм"]
        ]
        let weight = EventTypeInfo(key: "weight", label: "Вес", icon: "scale", category: "health", fields: [
            EventFieldInfo(
                name: "weight",
                label: "Вес (кг)",
                type: "number",
                required: true,
                min: 0,
                max: 100,
                options: nil
            )
        ], chart: nil)
        let feeding = EventTypeInfo(key: "feeding", label: "Кормление", icon: "fork", category: "feeding", fields: [
            EventFieldInfo(
                name: "food",
                label: "Что дали",
                type: "text",
                required: false,
                min: nil,
                max: nil,
                options: nil
            ),
            EventFieldInfo(
                name: "amount",
                label: "Сколько",
                type: "number",
                required: false,
                min: nil,
                max: nil,
                options: nil
            )
        ], chart: nil)

        let weightDraft = model.newDraft(for: weight)
        let feedingDraft = model.newDraft(for: feeding)

        #expect(weightDraft.values["weight"] == "29,3")
        #expect(feedingDraft.values["food"] == "Сухой корм")
        #expect(feedingDraft.values["amount"] == nil, "поле без значения по умолчанию осталось заполненным")
        #expect(model.newDraft(for: feeding).date == feedingDraft.date, "дата не должна прыгать при открытии формы")
    }

    /// Без сохранённых значений форма открывается пустой: значения по
    /// умолчанию не должны мешать, когда их нет.
    @Test("Без сохранённых значений форма пустая")
    func draftIsEmptyWithoutDefaults() async {
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        let weight = EventTypeInfo(key: "weight", label: "Вес", icon: "scale", category: "health", fields: [
            EventFieldInfo(
                name: "weight",
                label: "Вес (кг)",
                type: "number",
                required: true,
                min: 0,
                max: 100,
                options: nil
            )
        ], chart: nil)

        #expect(model.newDraft(for: weight).values.isEmpty)
    }

    /// Набор заменяется сервером целиком, поэтому упавшая загрузка не должна
    /// оставлять его пустым: человек открыл настройки, вписал одно значение и
    /// стёр всё остальное одним сохранением.
    @Test("Неудачная загрузка не обнуляет набор")
    func failedLoadKeepsPreviousValues() async {
        let model = await TestSupport.makeModel(defaults: TestSupport.makeDefaults())
        model.select(petID: "p1")
        model.formDefaults = ["weight": ["food": "Обычный"]]
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 500, json: [
            "success": false, "error": "Сервер недоступен", "code": "server_error"
        ])

        await model.loadFormDefaults()

        #expect(model.formDefaults == ["weight": ["food": "Обычный"]])
    }
}
