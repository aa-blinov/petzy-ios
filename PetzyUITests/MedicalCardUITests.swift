import XCTest

/// Медкарта: переход в раздел и назад. Плитки разделов лежат в строке списка,
/// а ссылка внутри строки перехватывала переход: тап по плитке открывал чужой
/// раздел, а «назад» открывал следующий раздел вместо возврата на медкарту.
@MainActor
final class MedicalCardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSectionOpensAndBackReturnsToCard() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")
        app.buttons["Медкарта"].tap()
        XCTAssertTrue(app.buttons["petSwitcher"].waitForExistence(timeout: 20), "Медкарта не открылась")

        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Прививки")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "Плитка «Прививки» не найдена")
        tile.tap()
        XCTAssertTrue(
            app.navigationBars["Прививки"].waitForExistence(timeout: 20),
            "Тап по плитке открыл не тот раздел: \(app.debugDescription)"
        )

        app.buttons["BackButton"].tap()
        XCTAssertTrue(
            app.buttons["petSwitcher"].waitForExistence(timeout: 20),
            "«Назад» не вернул на медкарту: \(app.debugDescription)"
        )
    }
}
