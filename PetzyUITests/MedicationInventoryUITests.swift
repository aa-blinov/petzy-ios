import XCTest

/// Форма курса: переключатель учёта остатка и его поле. Название заполняется
/// латиницей — кириллицу в этом симуляторе не набрать, а проверке важно
/// только, что оно не пустое.
@MainActor
final class MedicationInventoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Включённый учёт без остатка сохранять нельзя: сервер такой курс
    /// принимает, считать ему нечего, и на следующей правке переключатель вышел
    /// бы выключенным. Человек должен увидеть это до нажатия «Сохранить».
    func testInventoryWithoutAmountIsRefusedOnScreen() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")
        app.buttons["Лекарства"].tap()

        app.buttons["Новое лекарство"].tap()
        XCTAssertTrue(app.switches["Учитывать остаток"].waitForExistence(timeout: 25))

        // Тап по строке целиком переключатель не двигает: строка в дереве доступности
        // это внешний `Switch` на всю ширину, а сам переключатель лежит у её
        // правого края. Целимся туда.
        flipStock(in: app)
        XCTAssertEqual(app.switches["Учитывать остаток"].value as? String, "1")
        // Форма ленивая: поля ниже сгиба в дерево не попадают, пока их не
        // видно. Без прокрутки проверка ищет то, чего на экране нет.
        app.swipeUp()
        XCTAssertTrue(
            app.textFields["Сколько осталось"].waitForExistence(timeout: 10),
            "Поля остатка не появились после включения переключателя: \(app.debugDescription)"
        )
        flipStock(in: app)
        XCTAssertEqual(app.switches["Учитывать остаток"].value as? String, "0")
        XCTAssertFalse(app.textFields["Сколько осталось"].exists, "Поля остатка не скрылись")

        // Сохраняем с включённым учётом и пустым остатком: ради этого всё и
        // затевалось. Переключатель возвращаем во включённое состояние.
        flipStock(in: app)
        let name = app.textFields["Название"]
        for _ in 0 ..< 4 where !name.exists {
            app.swipeDown()
        }
        // Название латиницей: кириллица в этом симуляторе не набирается, а
        // проверке важно только, что название заполнено.
        XCTAssertTrue(name.waitForExistence(timeout: 10), "Поле названия не найдено: \(app.debugDescription)")
        name.tap()
        name.typeText("Test")
        app.buttons["Сохранить"].tap()

        XCTAssertTrue(
            app.staticTexts["Укажите остаток: без него учёт не работает"].waitForExistence(timeout: 20),
            "Форма сохранила курс с учётом остатка без самого остатка: \(app.debugDescription)"
        )
    }

    /// Переключатель учёта остатка: сам переключатель у правого края строки,
    /// а не строка целиком.
    private func flipStock(in app: XCUIApplication) {
        app.switches["Учитывать остаток"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .tap()
    }
}
