import XCTest

/// Лента — это и записи, и приёмы лекарств одним списком, как на вебе. Приём
/// открывается тем же листом, что и в разделе лекарств: перенести время или
/// отменить его можно там, где человек его увидел.
@MainActor
final class FeedIntakeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDoseRowOpensIntakeSheet() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        // Строка приёма отличается от записи меткой вида: на демо-стенде есть
        // отмеченные приёмы, и лента показывает их вместе с записями.
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dose-")).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 25),
            "в ленте нет приёма лекарства: \(app.debugDescription)"
        )
        row.tap()

        XCTAssertTrue(
            app.navigationBars["Приём"].waitForExistence(timeout: 15),
            "приём из ленты не открылся: \(app.debugDescription)"
        )
        XCTAssertTrue(app.buttons["Отменить приём"].exists, "в листе приёма нет отмены")

        // Снимок для README снимается здесь: лист открывает тест, а по
        // координатам в список не попасть.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "intake"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
