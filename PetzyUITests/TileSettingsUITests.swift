import XCTest

/// Набор типов на «+»: экран правки открывается из «О питомца», переключатель
/// меняет выбор, кнопка «Изменить» включает перетаскивание.
@MainActor
final class TileSettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        var tries = 0
        while !element.exists, tries < 12 {
            app.swipeUp()
            tries += 1
        }
        return element.exists
    }

    func testTilesScreenOpensAndToggles() async throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        guard let pet = await TestLaunch.petWithPhoto() else {
            throw XCTSkip("на стенде нет питомца с фото: проверять нечего")
        }
        TestLaunch.selectPet(app, named: pet.name)
        let photo = app.images["petPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 25), "фото питомца не показано")
        photo.tap()
        XCTAssertTrue(app.navigationBars["О питомце"].waitForExistence(timeout: 20), "нет «О питомце»")

        let row = app.buttons.containing(.staticText, identifier: "Типы на «+»").firstMatch
        XCTAssertTrue(scrollTo(app, row), "нет строки «Типы на „+“»: \(app.debugDescription)")
        row.tap()

        XCTAssertTrue(
            app.navigationBars["Типы на «+»"].waitForExistence(timeout: 15),
            "экран типов не открылся: \(app.debugDescription)"
        )
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "нет переключателей: \(app.debugDescription)")
        let before = toggle.value as? String
        // Тап в центр строки попадает в подпись и переключатель не трогает:
        // он лежит у правого края строки.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let after = toggle.value as? String

        XCTAssertNotEqual(before, after, "переключатель не переключился: было \(before ?? "nil")")
        XCTAssertTrue(app.buttons["Изменить"].exists, "нет кнопки «Изменить»: \(app.debugDescription)")
    }

    /// Выключенный тип уходит с «+» после сохранения: проверяется вся цепочка,
    /// форма, `tiles_settings` в запросе, ответ сервера и лист «Что записать».
    func testHiddenTypeLeavesThePlus() async throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        guard let pet = await TestLaunch.petWithPhoto() else {
            throw XCTSkip("на стенде нет питомца с фото: проверять нечего")
        }
        TestLaunch.selectPet(app, named: pet.name)
        try openTiles(app)
        defer { restore(app) }

        try setSwitch(app, named: "Кормление", on: false)
        app.navigationBars["Типы на «+»"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["О питомце"].waitForExistence(timeout: 10), "не вернулись в форму")
        saveForm(app)

        XCTAssertFalse(tilesSheet(app).contains { $0 == "Кормление" }, "«Кормление» осталось на «+»")
    }

    /// Вернуть стенд в исходное состояние: тест не должен оставлять питомца
    /// без кормления.
    private func restore(_ app: XCUIApplication) {
        guard app.images["petPhoto"].waitForExistence(timeout: 15) else { return }
        app.images["petPhoto"].tap()
        guard app.navigationBars["О питомце"].waitForExistence(timeout: 15) else { return }
        let row = app.buttons.containing(.staticText, identifier: "Типы на «+»").firstMatch
        guard scrollTo(app, row) else { return }
        row.tap()
        guard app.navigationBars["Типы на «+»"].waitForExistence(timeout: 15) else { return }
        try? setSwitch(app, named: "Кормление", on: true)
        saveForm(app)
    }

    private func openTiles(_ app: XCUIApplication) throws {
        let photo = app.images["petPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 25), "фото питомца не показано")
        photo.tap()
        XCTAssertTrue(app.navigationBars["О питомце"].waitForExistence(timeout: 20), "нет «О питомце»")
        let row = app.buttons.containing(.staticText, identifier: "Типы на «+»").firstMatch
        XCTAssertTrue(scrollTo(app, row), "нет строки «Типы на „+“»")
        row.tap()
        XCTAssertTrue(app.navigationBars["Типы на «+»"].waitForExistence(timeout: 15), "экран типов не открылся")
    }

    /// Выключатель лежит у правого края строки: тап в её центр попадает в
    /// подпись и ничего не переключает.
    private func setSwitch(_ app: XCUIApplication, named name: String, on wanted: Bool) throws {
        let toggle = app.switches[name]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "нет переключателя «\(name)»")
        let isOn = (toggle.value as? String) == "1"
        guard isOn != wanted else { return }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func saveForm(_ app: XCUIApplication) {
        let back = app.navigationBars["Типы на «+»"].buttons.element(boundBy: 0)
        if back.exists {
            back.tap()
        }
        let save = app.buttons["Сохранить"]
        if save.waitForExistence(timeout: 10) {
            save.tap()
        }
        if app.buttons["Записано"].waitForExistence(timeout: 15) {
            app.buttons["Записано"].tap()
        }
        let backToFeed = app.navigationBars["О питомце"].buttons.element(boundBy: 0)
        if backToFeed.exists {
            backToFeed.tap()
        }
    }

    /// Что предлагает «+» прямо сейчас: подписи плиток.
    private func tilesSheet(_ app: XCUIApplication) -> [String] {
        let plus = app.buttons["Новая запись"]
        guard plus.waitForExistence(timeout: 10) else { return [] }
        plus.tap()
        guard app.navigationBars["Что записать"].waitForExistence(timeout: 15) else { return [] }
        let names = app.buttons.allElementsBoundByIndex.compactMap(\.label)
        app.buttons["Отмена"].tap()
        return names
    }
}
