import XCTest

/// Доступы для ассистентов: строка в настройках открывает свой экран, а не
/// молчит. Экран не входил ни в один тест, и первый же тап по нему вопрос и
/// задал.
@MainActor
final class AccessTokensUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTokensScreenOpensFromSettings() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        app.buttons["Настройки"].tap()

        let title = "Доступы для ассистентов"
        // Строка живёт ниже первого экрана настроек: до неё надо доскроллить.
        let row = app.buttons.containing(.staticText, identifier: title).firstMatch
        for _ in 0 ..< 4 where !row.exists {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 20), "нет строки доступов: \(app.debugDescription)")
        row.tap()

        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 20),
            "строка доступов не открыла экран: \(app.debugDescription)"
        )
    }
}
