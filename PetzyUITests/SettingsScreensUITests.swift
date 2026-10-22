import XCTest

/// Каждый раздел настроек открывается. Заодно эти шаги дают снимки экранов для
/// README: по координатам в список не попасть, а тест нажимает по элементу.
@MainActor
final class SettingsScreensUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSettingsScreensOpen() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        app.buttons["Настройки"].tap()

        let screens = [
            ("Свои типы записей", "Свои типы записей"),
            ("Аккаунт", "Аккаунт"),
            ("Доступы для ассистентов", "Доступы для ассистентов"),
            ("Справка", "Справка")
        ]
        for (row, title) in screens {
            let button = app.buttons.containing(.staticText, identifier: row).firstMatch
            scroll(app, to: button)
            XCTAssertTrue(button.waitForExistence(timeout: 15), "нет строки «\(row)»")
            button.tap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 15),
                "раздел «\(title)» не открылся: \(app.debugDescription)"
            )
            attach(app, name: row)
            app.navigationBars[title].buttons.element(boundBy: 0).tap()
        }
    }

    /// Строка может быть ниже экрана: листаем, пока она не появится.
    private func scroll(_ app: XCUIApplication, to element: XCUIElement) {
        for _ in 0 ..< 4 where !element.exists {
            app.swipeUp()
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
